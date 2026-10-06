import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import common

class PlaybackTransportTest(unittest.TestCase):
    def setUp(self):
        self.hik = common.HikvisionClient(common.GatewayConfig("192.168.1.3", "admin", "secret", "token"))
        self.uri = "rtsp://192.168.1.3/Streaming/tracks/1001?starttime=20261006T200000Z&endtime=20261006T200030Z"

    def test_hevc_tcp_failure_retries_same_window_over_udp(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = pathlib.Path(tmp) / "clip.mp4"
            commands = []
            def run(cmd, **kw):
                commands.append(cmd)
                self.assertEqual(kw["timeout"], 120)
                if len(commands) == 1:
                    output.write_bytes(b"partial")
                    return subprocess.CompletedProcess(cmd, 1, b"", b"Unsupported (HEVC) NAL type (60)")
                self.assertFalse(output.exists())
                output.write_bytes(b"valid")
                return subprocess.CompletedProcess(cmd, 0, b"", b"")
            with patch.object(common, "find_ffmpeg", return_value="ffmpeg"), patch.object(common, "run_background", side_effect=run), patch.object(common, "log"):
                self.hik.download_playback_stream(self.uri, output, 30)
            self.assertEqual([c[c.index("-rtsp_transport")+1] for c in commands], ["tcp", "udp"])
            self.assertEqual(commands[0][commands[0].index("-i")+1], commands[1][commands[1].index("-i")+1])
            self.assertEqual(output.read_bytes(), b"valid")

    def test_failed_udp_removes_partial_and_redacts_credentials(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = pathlib.Path(tmp) / "clip.mp4"
            def run(cmd, **kw):
                output.write_bytes(b"partial")
                return subprocess.CompletedProcess(cmd, 1, b"", b"Unsupported (HEVC) NAL type secret rtsp://admin:secret@host")
            with patch.object(common, "find_ffmpeg", return_value="ffmpeg"), patch.object(common, "run_background", side_effect=run) as runner, patch.object(common, "log"):
                with self.assertRaisesRegex(RuntimeError, "^rtsp_playback_failed:unsupported_hevc_payload$"):
                    self.hik.download_playback_stream(self.uri, output, 30)
                self.assertEqual(runner.call_count, 2)
                self.assertFalse(output.exists())

    def test_authentication_failure_does_not_retry_udp(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = pathlib.Path(tmp) / "clip.mp4"
            with patch.object(common, "find_ffmpeg", return_value="ffmpeg"), patch.object(common, "run_background", return_value=subprocess.CompletedProcess([], 1, b"", b"401 Unauthorized")) as runner:
                with self.assertRaisesRegex(RuntimeError, "authentication"):
                    self.hik.download_playback_stream(self.uri, output, 30)
                self.assertEqual(runner.call_count, 1)

    def test_failure_reports_only_allowlisted_codec_and_nal(self):
        with tempfile.TemporaryDirectory() as tmp:
            stderr = b"Video: hevc Unsupported (HEVC) NAL type (62) rtsp://admin:secret@host"
            with patch.object(common, "find_ffmpeg", return_value="ffmpeg"), patch.object(common, "log"), patch.object(common, "run_background", return_value=subprocess.CompletedProcess([], 1, b"", stderr)):
                with self.assertRaises(RuntimeError) as caught:
                    self.hik.download_playback_stream(self.uri, pathlib.Path(tmp) / "clip.mp4", 30)
                self.assertIn('"nal":[62]', str(caught.exception))
                self.assertIn('"input_codec":["hevc"]', str(caught.exception))
                self.assertNotIn("secret", str(caught.exception))

    def test_codec_relay_requires_authenticated_h264_and_nal_62(self):
        from types import SimpleNamespace
        from unittest.mock import MagicMock
        for codec in ('H.264', 'H.265'):
            with self.subTest(codec=codec), tempfile.TemporaryDirectory() as tmp:
                output = pathlib.Path(tmp) / 'clip.mp4'
                commands = []
                def run(cmd, **kwargs):
                    commands.append(cmd)
                    if len(commands) < 3:
                        return subprocess.CompletedProcess(cmd, 1, b'', b'Unsupported (HEVC) NAL type (62)')
                    output.write_bytes(b'valid')
                    return subprocess.CompletedProcess(cmd, 0, b'', b'')
                relay = MagicMock()
                relay.__enter__.return_value = SimpleNamespace(uri='rtsp://127.0.0.1:12345/Streaming/tracks/1001?starttime=20261006T200000Z&endtime=20261006T200030Z', corrected=True)
                with patch.object(common, 'find_ffmpeg', return_value='ffmpeg'), patch.object(common, 'run_background', side_effect=run), patch.object(common, 'log'), patch.object(self.hik, 'playback_diagnostics', return_value={'configured_codecs':[codec]}), patch('rtsp_codec_relay.SdpCodecRelay', return_value=relay) as factory:
                    if codec == 'H.264':
                        self.hik.download_playback_stream(self.uri, output, 30)
                        self.assertTrue(self.hik._playback_codec_relay_used)
                        self.assertEqual(len(commands),3)
                        self.assertEqual(factory.call_args.args[0], self.uri)
                    else:
                        with self.assertRaises(RuntimeError):
                            self.hik.download_playback_stream(self.uri, output, 30)
                        self.assertFalse(self.hik._playback_codec_relay_used)
                        self.assertEqual(len(commands),2)
                        factory.assert_not_called()

    def test_read_only_diagnostics_do_not_export_xml_secrets(self):
        from types import SimpleNamespace
        responses = [SimpleNamespace(status_code=200, text='<StreamingChannel><Video><videoCodecType>H.264</videoCodecType><password>secret</password></Video></StreamingChannel>'),
                     SimpleNamespace(status_code=200, text='<DeviceInfo><firmwareVersion>V4.30.085</firmwareVersion><serialNumber>private</serialNumber></DeviceInfo>')]
        with patch.object(self.hik.session, "get", side_effect=responses) as get:
            facts = self.hik.playback_diagnostics(10)
        self.assertEqual(facts["host"], "192.168.1.3")
        self.assertEqual(facts["configured_codecs"], ["H.264"])
        self.assertEqual(facts["firmware"], "V4.30.085")
        self.assertTrue(get.call_args_list[0].args[0].endswith("/1001"))
        self.assertNotIn("secret", str(facts))
        self.assertNotIn("private", str(facts))

    def test_diagnostics_http_failure_is_nonfatal_and_redacted(self):
        with patch.object(self.hik.session, "get", side_effect=RuntimeError("secret")):
            facts = self.hik.playback_diagnostics(10)
        self.assertEqual(facts["stream_read"], "unavailable")
        self.assertNotIn("secret", str(facts))

    def test_unbounded_or_foreign_host_never_runs_ffmpeg(self):
        with patch.object(common, "run_background") as runner:
            for uri in ["rtsp://192.168.1.3/live", self.uri.replace("192.168.1.3", "192.168.1.4")]:
                with self.assertRaises(RuntimeError):
                    self.hik.download_playback_stream(uri, pathlib.Path("unused"), 30)
            runner.assert_not_called()

if __name__ == "__main__":
    unittest.main()
