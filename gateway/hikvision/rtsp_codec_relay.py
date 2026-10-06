"""Loopback-only RTSP SDP correction; RTP and the historical URI stay unchanged."""
from __future__ import annotations
import hashlib
import hmac
import re
import socket
import threading
from urllib.parse import urlsplit, urlunsplit
from requests.utils import parse_dict_header


def _digest(header, method, uri, username, password, client_uri=None):
    if not header.startswith('Digest '):
        return header
    fields = parse_dict_header(header[7:])
    if fields.get('username') != username:
        raise ValueError('relay_auth_user')
    algorithm = fields.get('algorithm', 'MD5').upper()
    if algorithm not in {'MD5', 'MD5-SESS', 'SHA-256', 'SHA-256-SESS'}:
        raise ValueError('relay_auth_algorithm')
    hash_fn = hashlib.sha256 if algorithm.startswith('SHA-256') else hashlib.md5
    def digest(value):
        return hash_fn(value.encode('utf-8')).hexdigest()
    nonce = fields['nonce']
    a1 = digest(f"{username}:{fields['realm']}:{password}")
    if algorithm.endswith('-SESS'):
        a1 = digest(f"{a1}:{nonce}:{fields['cnonce']}")
    a2 = digest(f'{method}:{uri}')
    qop = fields.get('qop')
    if qop and qop != 'auth':
        raise ValueError('relay_auth_qop')
    def response_for(a2):
        return digest(f"{a1}:{nonce}:{fields['nc']}:{fields['cnonce']}:{qop}:{a2}") if qop else digest(f'{a1}:{nonce}:{a2}')
    if client_uri is not None:
        if fields.get('uri') != client_uri or not hmac.compare_digest(fields.get('response', ''), response_for(digest(f'{method}:{client_uri}'))):
            raise ValueError('relay_client_authentication')
    response = response_for(a2)
    fields.update(uri=uri, response=response)
    if any('"' in str(v) or '\r' in str(v) or '\n' in str(v) for v in fields.values()):
        raise ValueError('relay_auth_fields')
    return 'Digest ' + ', '.join(f'{k}="{v}"' for k,v in fields.items())


def _messages(sock, stop):
    buffer = b''
    while not stop.is_set():
        if buffer.startswith(b'$') and len(buffer) >= 4:
            length = 4 + int.from_bytes(buffer[2:4], 'big')
        elif not buffer.startswith(b'$') and b'\r\n\r\n' in buffer:
            end = buffer.index(b'\r\n\r\n') + 4
            match = re.search(br'(?im)^Content-Length:\s*(\d+)\s*$', buffer[:end])
            body = int(match[1]) if match else 0
            if end > 65536 or body > 262144:
                raise ValueError('relay_message_limit')
            length = end + body
        else:
            length = None
        if length is not None and len(buffer) >= length:
            message, buffer = buffer[:length], buffer[length:]
            yield message
            continue
        try:
            data = sock.recv(32768)
        except socket.timeout:
            continue
        if not data:
            return
        buffer += data
        if len(buffer) > 327680:
            raise ValueError('relay_buffer_limit')


class SdpCodecRelay:
    def __init__(self, uri, username, password):
        self.parts = urlsplit(uri)
        self.username, self.password = username, password
        self.stop = threading.Event()
        self.sockets = []
        self.corrected = False
        self.failed = False

    def __enter__(self):
        self.listener = socket.socket()
        self.listener.bind(('127.0.0.1', 0))
        self.listener.listen(1)
        self.listener.settimeout(1)
        self.sockets.append(self.listener)
        self.local_authority = '127.0.0.1:' + str(self.listener.getsockname()[1])
        self.uri = urlunsplit(('rtsp', self.local_authority, self.parts.path, self.parts.query, ''))
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()
        return self

    def _request(self, message):
        if message.startswith(b'$'):
            return message
        header, body = message.split(b'\r\n\r\n', 1)
        lines = header.decode('latin1').split('\r\n')
        method, uri, protocol = lines[0].split(' ', 2)
        client_uri = uri
        if uri != '*':
            parsed = urlsplit(uri)
            root = self.parts.path.rstrip('/').lower()
            path = parsed.path.rstrip('/').lower()
            if parsed.hostname not in {'127.0.0.1', self.parts.hostname} or (path != root and not path.startswith(root + '/')):
                raise ValueError('relay_uri_scope')
            if method == 'DESCRIBE' and parsed.query != self.parts.query:
                raise ValueError('relay_time_scope')
            uri = urlunsplit(('rtsp', self.parts.netloc, parsed.path, parsed.query, ''))
        lines[0] = f'{method} {uri} {protocol}'
        for i,line in enumerate(lines[1:], 1):
            if line.lower().startswith('authorization:'):
                lines[i] = 'Authorization: ' + _digest(line.split(':', 1)[1].strip(), method, uri, self.username, self.password, client_uri)
        return ('\r\n'.join(lines) + '\r\n\r\n').encode('latin1') + body

    def _localize(self, value):
        # A recorder may add its default RTSP port in Content-Base even
        # when the search URI omits it. Replacing only the host would
        # otherwise produce two ports on the loopback URI.
        origin = r'rtsp://' + re.escape(self.parts.hostname) + r'(?::' + str(self.parts.port or 554) + r')?(?=/)'
        return re.sub(origin, 'rtsp://' + self.local_authority, value, flags=re.IGNORECASE)

    def _response(self, message):
        if message.startswith(b'$'):
            return message
        header, body = message.split(b'\r\n\r\n', 1)
        lines = header.decode('latin1').split('\r\n')
        if any(line.lower().startswith('content-type: application/sdp') for line in lines):
            sdp = body.decode('ascii')
            targets = re.findall(r'(?im)^a=rtpmap:(\d+) (?:H265|HEVC)/90000[ \t]*\r?$', sdp)
            if len(targets) == 1:
                pt = targets[0]
                sdp = re.sub(rf'(?im)^a=rtpmap:{pt} (?:H265|HEVC)/90000[ \t]*\r?$', f'a=rtpmap:{pt} H264/90000\r', sdp)
                sdp = re.sub(rf'(?im)^a=fmtp:{pt}[^\r\n]*\r?\n', '', sdp)
                sdp += f'a=fmtp:{pt} packetization-mode=1\r\n'
                body = sdp.encode('ascii')
                self.corrected = True
            body = self._localize(body.decode('ascii')).encode('ascii')
        for i,line in enumerate(lines):
            if line.lower().startswith('content-length:'):
                lines[i] = f'Content-Length: {len(body)}'
            elif line.lower().startswith(('content-base:', 'content-location:')):
                lines[i] = self._localize(line)
        return ('\r\n'.join(lines) + '\r\n\r\n').encode('latin1') + body

    def _pump(self, source, target, transform):
        try:
            for message in _messages(source, self.stop):
                target.sendall(transform(message))
        except Exception:
            self.failed = True
        finally:
            self.stop.set()

    def _serve(self):
        try:
            while not self.stop.is_set():
                try:
                    client, _ = self.listener.accept()
                    break
                except socket.timeout:
                    continue
            else:
                return
            self.sockets.append(client)
            upstream = socket.create_connection((self.parts.hostname, self.parts.port or 554), timeout=10)
            self.sockets.append(upstream)
            client.settimeout(1)
            upstream.settimeout(1)
            response_thread = threading.Thread(target=self._pump, args=(upstream, client, self._response), daemon=True)
            response_thread.start()
            self._pump(client, upstream, self._request)
            response_thread.join(timeout=2)
        except Exception:
            self.failed = True
            self.stop.set()

    def __exit__(self, *args):
        self.stop.set()
        for sock in self.sockets:
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            sock.close()
        self.thread.join(timeout=3)
        for sock in self.sockets:
            sock.close()
