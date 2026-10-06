import hashlib
import pathlib
import re
import shutil
import socket
import struct
import subprocess
import tempfile
import threading
import unittest
from requests.utils import parse_dict_header
from rtsp_codec_relay import SdpCodecRelay, _digest, _messages


class RelayTests(unittest.TestCase):
    def test_digest_uses_original_historical_uri(self):
        uri = 'rtsp://192.168.1.3/Streaming/tracks/1001?starttime=20261006T200000Z&endtime=20261006T200030Z'
        header = 'Digest username="admin", realm="recorder", nonce="abc", uri="rtsp://127.0.0.1/", response="old", qop="auth", nc="00000001", cnonce="xyz"'
        result = parse_dict_header(_digest(header, 'DESCRIBE', uri, 'admin', 'SECRET')[7:])
        md5 = lambda text: hashlib.md5(text.encode()).hexdigest()
        expected = md5(md5('admin:recorder:SECRET') + ':abc:00000001:xyz:auth:' + md5('DESCRIBE:' + uri))
        self.assertEqual(result['response'], expected)
        self.assertEqual(result['uri'], uri)
        self.assertNotIn('SECRET', str(result))
        client_uri = 'rtsp://127.0.0.1/'
        client_response = md5(md5('admin:recorder:SECRET') + ':abc:00000001:xyz:auth:' + md5('DESCRIBE:' + client_uri))
        valid = header.replace('response="old"', 'response="' + client_response + '"')
        self.assertEqual(_digest(valid,'DESCRIBE',uri,'admin','SECRET',client_uri), _digest(valid,'DESCRIBE',uri,'admin','SECRET'))
        with self.assertRaises(ValueError):
            _digest(header,'DESCRIBE',uri,'admin','SECRET',client_uri)
        with self.assertRaises(ValueError):
            _digest(header.replace('username="admin"', 'username="other"'), 'DESCRIBE', uri, 'admin', 'SECRET')

    def test_only_hevc_sdp_changes_rtp_bytes_stay_exact(self):
        relay = SdpCodecRelay('rtsp://192.168.1.3/Streaming/tracks/1001?starttime=a&endtime=b', 'admin', 'secret')
        relay.local_authority = '127.0.0.1:12345'
        body = b'v=0\r\nm=video 0 RTP/AVP 96\r\na=rtpmap:96 H265/90000\r\na=fmtp:96 sprop-vps=private;sprop-sps=private\r\na=control:trackID=1\r\n'
        message = b'RTSP/1.0 200 OK\r\nContent-Type: application/sdp\r\nContent-Length: ' + str(len(body)).encode() + b'\r\n\r\n' + body
        changed = relay._response(message)
        header, sdp = changed.split(b'\r\n\r\n')
        self.assertIn(b'H264/90000', sdp)
        self.assertNotIn(b'sprop-vps', sdp)
        self.assertIn(b'packetization-mode=1', sdp)
        self.assertIn(str(len(sdp)).encode(), header)
        packet = b'$\x00\x00\x04abcd'
        self.assertEqual(relay._request(packet), packet)
        self.assertEqual(relay._response(packet), packet)
        self.assertTrue(relay.corrected)
        with self.assertRaises(ValueError):
            relay._request(b'DESCRIBE rtsp://other/Streaming/tracks/1001 RTSP/1.0\r\n\r\n')

    @unittest.skipUnless(shutil.which('ffmpeg'), 'native FFmpeg RTP fixture')
    def test_native_h264_payload_with_wrong_hevc_sdp_decodes_through_relay(self):
        with tempfile.TemporaryDirectory() as tmp:
            raw = pathlib.Path(tmp) / 'source.h264'
            output = pathlib.Path(tmp) / 'clip.mp4'
            subprocess.run(['ffmpeg','-nostdin','-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=320x180:rate=25','-t','3','-c:v','libx264','-preset','ultrafast','-x264-params','aud=1:repeat-headers=1:keyint=25','-f','h264',str(raw)],check=True,capture_output=True,timeout=20)
            nals = [n for n in re.split(b'\x00\x00(?:\x00)?\x01', raw.read_bytes()) if n]
            listener = socket.socket()
            listener.bind(('127.0.0.1',0))
            listener.listen(1)
            port = listener.getsockname()[1]
            uri = f'rtsp://127.0.0.1:{port}/Streaming/tracks/1001?starttime=20261006T200000Z&endtime=20261006T200003Z'
            errors = []
            stop = threading.Event()
            def serve():
                try:
                    connection,_ = listener.accept()
                    with connection:
                        connection.settimeout(1)
                        for request in _messages(connection,stop):
                            if request.startswith(b'$'):
                                continue
                            header = request.split(b'\r\n\r\n')[0].decode()
                            method = header.split()[0]
                            cseq = re.search(r'(?im)^CSeq:\s*(\d+)', header)[1]
                            if method == 'DESCRIBE' and 'Authorization:' not in header:
                                connection.sendall(f'RTSP/1.0 401 Unauthorized\r\nCSeq: {cseq}\r\nWWW-Authenticate: Digest realm="recorder", nonce="abcdef123456"\r\n\r\n'.encode())
                                continue
                            if method == 'DESCRIBE':
                                authorization = re.search(r'(?im)^Authorization:\s*(.*)',header)[1].strip()
                                fields = parse_dict_header(authorization[7:])
                                self.assertEqual(fields['uri'],uri)
                                md5 = lambda text: hashlib.md5(text.encode()).hexdigest()
                                self.assertEqual(fields['response'],md5(md5('admin:recorder:secret')+':abcdef123456:'+md5('DESCRIBE:'+uri)))
                            headers = f'RTSP/1.0 200 OK\r\nCSeq: {cseq}\r\nSession: 123456\r\n'
                            body = b''
                            if method == 'DESCRIBE':
                                body = b'v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=fixture\r\nt=0 0\r\na=control:*\r\nm=video 0 RTP/AVP 96\r\nc=IN IP4 127.0.0.1\r\na=rtpmap:96 H265/90000\r\na=control:trackID=1\r\n'
                                headers += f'Content-Type: application/sdp\r\nContent-Base: {uri}/\r\nContent-Length: {len(body)}\r\n'
                            elif method == 'SETUP':
                                headers += 'Transport: RTP/AVP/TCP;unicast;interleaved=0-1\r\n'
                            elif method == 'OPTIONS':
                                headers += 'Public: OPTIONS, DESCRIBE, SETUP, PLAY, TEARDOWN\r\n'
                            connection.sendall((headers+'\r\n').encode()+body)
                            if method == 'PLAY':
                                seq, frame = 0, -1
                                for nal in nals:
                                    if nal[0]&31 == 9:
                                        frame += 1
                                    parts = [nal] if len(nal)<=1200 else [bytes([(nal[0]&224)|28, (nal[0]&31)|(128 if i==0 else 0)|(64 if i+1198>=len(nal)-1 else 0)])+nal[1+i:1+i+1198] for i in range(0,len(nal)-1,1198)]
                                    for i,part in enumerate(parts):
                                        packet = struct.pack('!BBHII',128,96|(128 if i==len(parts)-1 else 0),seq, max(frame,0)*3600,1234)+part
                                        connection.sendall(b'$\x00'+len(packet).to_bytes(2,'big')+packet)
                                        seq = (seq+1)%65536
                                stop.wait(2)
                                return
                except (BrokenPipeError, ConnectionResetError):
                    pass
                except Exception as exc:
                    errors.append(type(exc).__name__)
            thread = threading.Thread(target=serve,daemon=True)
            thread.start()
            try:
                with SdpCodecRelay(uri,'admin','secret') as relay:
                    result = subprocess.run(['ffmpeg','-nostdin','-loglevel','error','-y','-rtsp_transport','tcp','-timeout','5000000','-i',relay.uri.replace('rtsp://','rtsp://admin:secret@'),'-t','1','-an','-c:v','libx264',str(output)],capture_output=True,timeout=20)
                    self.assertEqual(result.returncode,0,result.stderr.decode(errors='replace'))
                    self.assertTrue(relay.corrected)
                    self.assertGreater(output.stat().st_size,1000)
                decoded = subprocess.run(['ffmpeg','-nostdin','-loglevel','error','-i',str(output),'-f','null','-'],capture_output=True,timeout=10)
                self.assertEqual(decoded.returncode,0,decoded.stderr)
                self.assertEqual(errors,[])
            finally:
                stop.set()
                listener.close()
                thread.join(timeout=3)


if __name__ == '__main__':
    unittest.main()
