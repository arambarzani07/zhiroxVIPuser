import pathlib
import tempfile
import unittest
from unittest.mock import Mock, patch

import bootstrap


class OversizedBoundedExportGuardTest(unittest.TestCase):
    def test_oversized_bounded_success_is_rejected_and_removed(self):
        uri = (
            "rtsp://192.168.1.3/Streaming/tracks/1001/"
            "?starttime=20261007T050000Z&endtime=20261007T050030Z"
        )

        def fake_download(_client, _uri, path):
            path.write_bytes(b"x" * 32)
            return "time"

        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "clip.mp4"
            with patch.object(bootstrap, "_original_download_recording", side_effect=fake_download), \
                    patch.object(bootstrap, "MAX_BOUNDED_EXPORT_BYTES", 16), \
                    patch.object(bootstrap, "log"):
                with self.assertRaisesRegex(
                    RuntimeError, "^download_rejected:oversized_bounded_export$"
                ):
                    bootstrap._guarded_download_recording(Mock(), uri, path)
            self.assertFalse(path.exists())

    def test_original_file_export_is_not_reclassified(self):
        uri = (
            "rtsp://192.168.1.3/Streaming/tracks/1001/"
            "?starttime=20261007T000000Z&endtime=20261007T060000Z"
            "&name=recording.mp4&size=999999999"
        )

        def fake_download(_client, _uri, path):
            path.write_bytes(b"x" * 32)
            return "time"

        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "recording.mp4"
            with patch.object(bootstrap, "_original_download_recording", side_effect=fake_download), \
                    patch.object(bootstrap, "MAX_BOUNDED_EXPORT_BYTES", 16):
                mode = bootstrap._guarded_download_recording(Mock(), uri, path)
            self.assertEqual(mode, "time")
            self.assertTrue(path.exists())


if __name__ == "__main__":
    unittest.main()
