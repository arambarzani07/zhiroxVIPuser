import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock

from diagnose import diagnose


class DiagnosticsTest(unittest.TestCase):
    def setUp(self):
        self.at = datetime.now(timezone.utc) - timedelta(minutes=2)
        self.hik = Mock()
        self.hik.host = 'http://192.168.1.2'
        self.hik.device_info.return_value = '<DeviceInfo><model>DS-7616NI-K2/16P</model></DeviceInfo>'
        self.hik.session.get.return_value.content = (
            '<Time><localTime>' + datetime.now(timezone.utc).isoformat() + '</localTime></Time>'
        ).encode()
        self.hik.search_recording.return_value = {
            'found': True, 'segment_start': (self.at-timedelta(minutes=1)).isoformat(),
            'segment_end': (self.at+timedelta(minutes=1)).isoformat(),
            'playback_uri': 'private-recorder-uri',
        }

    def test_read_only_without_download(self):
        report = diagnose(self.hik, 1, self.at)
        self.assertEqual(report['recording_status'], 'found_at_requested_time')
        self.assertTrue(report['requested_window_covered'])
        self.hik.download_recording.assert_not_called()
        self.hik.session.post.assert_not_called()
        self.assertNotIn('private-recorder-uri', str(report))

    def test_missing_recording_is_not_success(self):
        self.hik.search_recording.return_value = {'found': False}
        self.assertEqual(diagnose(self.hik, 1, self.at)['recording_status'], 'not_found')

    def test_nearby_recording_is_not_evidence(self):
        self.hik.search_recording.return_value['segment_start'] = (self.at+timedelta(seconds=1)).isoformat()
        with tempfile.TemporaryDirectory() as temp:
            target = pathlib.Path(temp)/'test.mp4'
            report = diagnose(self.hik, 1, self.at, target)
            self.assertEqual(report['recording_status'], 'time_not_verified')
            self.assertFalse(target.exists())
            self.hik.download_recording.assert_not_called()

    def test_download_published_and_hashed(self):
        self.hik.download_recording.side_effect = lambda uri, path: path.write_bytes(b'video-content')
        with tempfile.TemporaryDirectory() as temp:
            target = pathlib.Path(temp)/'test.mp4'
            report = diagnose(self.hik, 1, self.at, target)
            self.assertEqual(target.read_bytes(), b'video-content')
            self.assertEqual(report['download_status'], 'saved_locally')
            self.assertEqual(len(report['sha256']), 64)
            self.assertFalse(target.with_name('test.mp4.part').exists())

    def test_failed_download_removes_partial(self):
        self.hik.download_recording.side_effect = RuntimeError('failed')
        with tempfile.TemporaryDirectory() as temp:
            target = pathlib.Path(temp)/'test.mp4'
            with self.assertRaises(RuntimeError):
                diagnose(self.hik, 1, self.at, target)
            self.assertEqual(list(pathlib.Path(temp).iterdir()), [])

    def test_existing_file_is_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            target = pathlib.Path(temp)/'test.mp4'
            target.write_bytes(b'existing')
            with self.assertRaises(FileExistsError):
                diagnose(self.hik, 1, self.at, target)
            self.assertEqual(target.read_bytes(), b'existing')

    def test_invalid_channel_and_naive_time_rejected(self):
        with self.assertRaises(ValueError):
            diagnose(self.hik, 0, self.at)
        with self.assertRaises(ValueError):
            diagnose(self.hik, 1, datetime(2026, 10, 3))
        self.hik.device_info.assert_not_called()

    def test_unavailable_clock_does_not_fake_verification(self):
        self.hik.session.get.return_value.content = b'<Time><localTime>invalid</localTime></Time>'
        self.assertEqual(diagnose(self.hik, 1, self.at)['clock_status'], 'could_not_verify')


if __name__ == '__main__':
    unittest.main()
