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

    def test_unbounded_or_foreign_host_never_runs_ffmpeg(self):
        with patch.object(common, "run_background") as runner:
            for uri in ["rtsp://192.168.1.3/live", self.uri.replace("192.168.1.3", "192.168.1.4")]:
                with self.assertRaises(RuntimeError):
                    self.hik.download_playback_stream(uri, pathlib.Path("unused"), 30)
            runner.assert_not_called()

if __name__ == "__main__":
    unittest.main()
