import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, patch

import common
import agent
import recording_recovery


class PlaybackFailureTest(unittest.TestCase):
    def test_missing_ffmpeg_is_failure(self):
        with patch.object(common.subprocess, 'run', side_effect=OSError), patch.object(common.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(RuntimeError, 'ffmpeg_required'):
                common.find_ffmpeg()

    def test_failed_preparation_never_uploads_raw_or_completes(self):
        now = datetime.now(timezone.utc) - timedelta(minutes=5)
        cloud, hik = Mock(), Mock()
        hik.search_recording.return_value = {'found': True, 'playback_uri': 'rtsp://192.168.1.3/Streaming/tracks/1001?name=old&size=123', 'segment_start': now.isoformat()}
        hik.download_recording.side_effect = lambda uri, path: path.write_bytes(b'raw-hevc')
        job = {'job_id': 'test', 'transaction_at': now.isoformat(), 'clip_start_at': now.isoformat(),
               'clip_end_at': (now + timedelta(seconds=30)).isoformat(), 'channel_id': 10}
        with tempfile.TemporaryDirectory() as tmp, patch.object(agent, 'TEMP_DIR', pathlib.Path(tmp)), patch.object(agent, 'log'), patch.object(agent, 'prepare_browser_clip', side_effect=RuntimeError('clip_conversion_failed')):
            agent.process_job(cloud, Mock(), hik, job)
            cloud.upload.assert_not_called()
            self.assertEqual([c.args[0] for c in cloud.call.call_args_list], ['fail'])
            self.assertEqual(list(pathlib.Path(tmp).iterdir()), [])

    def test_missing_recording_preflight_prefers_advertised_local_clock(self):
        start = datetime(2026, 10, 3, 7, 20, 24, tzinfo=timezone.utc)
        job = {
            'job_id': 'missing-local-clock',
            'transaction_at': (start + timedelta(seconds=15)).isoformat(),
            'clip_start_at': start.isoformat(),
            'clip_end_at': (start + timedelta(seconds=30)).isoformat(),
            'channel_id': 10,
        }
        hik = Mock()
        hik._verified_playback_clock_offset = 0
        hik.playback_diagnostics.return_value = {'nvr_time': '2026-10-07T10:20:00+03:00'}
        hik.search_recording.side_effect = [
            {'found': False},
            {'found': True, 'playback_uri': 'rtsp://192.168.1.3/Streaming/tracks/1001'},
        ]
        recording_recovery._prefer_working_clock_convention(hik, job, Mock())
        self.assertEqual(hik._verified_playback_clock_offset, 3 * 3600)
        self.assertEqual(hik.search_recording.call_count, 2)
        shifted = hik.search_recording.call_args_list[1].args
        self.assertEqual(shifted[1], start + timedelta(hours=3))
        self.assertEqual(shifted[2], start + timedelta(hours=3, seconds=30))

    def test_missing_recording_preflight_never_guesses_without_shifted_match(self):
        start = datetime(2026, 10, 3, 7, 20, 24, tzinfo=timezone.utc)
        job = {
            'job_id': 'missing-no-guess',
            'transaction_at': (start + timedelta(seconds=15)).isoformat(),
            'clip_start_at': start.isoformat(),
            'clip_end_at': (start + timedelta(seconds=30)).isoformat(),
            'channel_id': 10,
        }
        hik = Mock()
        hik._verified_playback_clock_offset = 0
        hik.playback_diagnostics.return_value = {'nvr_time': '2026-10-07T10:20:00+03:00'}
        hik.search_recording.side_effect = [{'found': False}, {'found': False}]
        recording_recovery._prefer_working_clock_convention(hik, job, Mock())
        self.assertEqual(hik._verified_playback_clock_offset, 0)


@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'FFmpeg integration tools required')
class PlaybackIntegrationTest(unittest.TestCase):
    def test_indexless_recording_can_be_sampled_and_trimmed(self):
        from osd_time import _video_clock_readings
        with tempfile.TemporaryDirectory() as tmp:
            folder = pathlib.Path(tmp)
            source, output = folder/'record.h264', folder/'web.mp4'
            subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-f', 'lavfi',
                '-i', 'testsrc2=size=640x360:rate=5', '-t', '9', '-c:v', 'libx264',
                '-preset', 'ultrafast', '-g', '45', '-f', 'h264', str(source)],
                check=True, capture_output=True, timeout=30)
            with patch('osd_time.read_image_clock', return_value='clock'):
                readings = _video_clock_readings(source, folder, 9)
            positions = [position for position, _ in readings]
            self.assertEqual(positions, sorted(positions))
            self.assertEqual(positions[0], 0.0)
            self.assertEqual(positions[-1], 6.0)
            self.assertIn(3.0, positions)
            self.assertGreaterEqual(len(positions), 5)
            now = datetime.now(timezone.utc)
            with patch.object(common, 'log'):
                media = common.prepare_browser_clip(source, output, now+timedelta(seconds=1), now.isoformat(), 7)
            self.assertTrue(media['decode_verified'])
            self.assertTrue(media['exact_trim'])
            self.assertEqual(media['duration_seconds'], 7)

    def test_hevc_converts_with_seek_audio_and_faststart(self):
        with tempfile.TemporaryDirectory() as tmp:
            source, output = pathlib.Path(tmp)/'hevc.mp4', pathlib.Path(tmp)/'web.mp4'
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=320x240:rate=25',
                            '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '3',
                            '-c:v', 'libx265', '-x265-params', 'pools=1:frame-threads=1:log-level=error',
                            '-tag:v', 'hev1', '-c:a', 'aac', str(source)], check=True, capture_output=True)
            now = datetime.now(timezone.utc)
            media = common.prepare_browser_clip(source, output, now + timedelta(seconds=1), now.isoformat(), 1)
            probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(output)]))
            video = next(s for s in probe['streams'] if s['codec_type'] == 'video')
            audio = next(s for s in probe['streams'] if s['codec_type'] == 'audio')
            self.assertEqual((video['codec_name'], video['codec_tag_string'], video['pix_fmt']), ('h264', 'avc1', 'yuv420p'))
            self.assertEqual(audio['codec_name'], 'aac')
            self.assertAlmostEqual(float(probe['format']['duration']), 1, delta=0.1)
            self.assertTrue(media['decode_verified'])
            self.assertTrue(media['exact_trim'])
            data = output.read_bytes()
            self.assertLess(data.index(b'moov'), data.index(b'mdat'))

    def test_corrupt_input_is_rejected_and_partial_output_removed(self):
        with tempfile.TemporaryDirectory() as tmp:
            source, output = pathlib.Path(tmp)/'broken.mp4', pathlib.Path(tmp)/'web.mp4'
            source.write_bytes(b'not a video')
            now = datetime.now(timezone.utc)
            with self.assertRaisesRegex(RuntimeError, 'clip_conversion_failed'):
                common.prepare_browser_clip(source, output, now, now.isoformat(), 1)
            self.assertFalse(output.exists())

if __name__ == '__main__':
    unittest.main()
