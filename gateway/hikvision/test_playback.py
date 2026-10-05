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


class DiagnosticRegressionTest(unittest.TestCase):
    def test_timeout_preserves_hevc_reason_and_removes_partial_file(self):
        hik = common.HikvisionClient(common.GatewayConfig('192.168.1.2', 'admin', 'secret', ''))
        uri = 'rtsp://192.168.1.2/Streaming/tracks/1001?starttime=20261005T160939Z&endtime=20261005T161009Z'
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp)/'raw.mp4'
            path.write_bytes(b'partial')
            error = subprocess.TimeoutExpired(['ffmpeg', 'secret'], 120,
                stderr=b'rtsp://admin:secret@192.168.1.2 Unsupported (HEVC) NAL type (62)')
            with patch.object(common, 'find_ffmpeg', return_value='ffmpeg'), patch.object(common, 'run_background', side_effect=error):
                with self.assertRaisesRegex(RuntimeError, '^rtsp_playback_failed:unsupported_hevc_payload$'):
                    hik.download_playback_stream(uri, path, 30)
            self.assertFalse(path.exists())

    def test_timeout_without_stderr_has_specific_deadline_reason(self):
        hik = common.HikvisionClient(common.GatewayConfig('192.168.1.2', 'admin', 'secret', ''))
        uri = 'rtsp://192.168.1.2/Streaming/tracks/1001?starttime=20261005T160939Z&endtime=20261005T161009Z'
        with tempfile.TemporaryDirectory() as tmp, patch.object(common, 'find_ffmpeg', return_value='ffmpeg'), patch.object(common, 'run_background', side_effect=subprocess.TimeoutExpired('secret', 120)):
            with self.assertRaisesRegex(RuntimeError, '^rtsp_playback_failed:deadline_exceeded$'):
                hik.download_playback_stream(uri, pathlib.Path(tmp)/'raw.mp4', 30)

    def test_session_limit_requires_an_rtsp_status(self):
        for text in ['method PLAY failed: 453 Not Enough Bandwidth', 'RTSP/1.0 453']:
            self.assertEqual(common.playback_failure_reason(text), 'recorder_session_limit')
        self.assertEqual(common.playback_failure_reason('frame=453 bitrate=1453'), 'unknown')

    def test_upload_errors_never_expose_signed_url(self):
        client = common.CloudClient(common.GatewayConfig('192.168.1.2', 'admin', 'secret', ''))
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp)/'clip.mp4'
            path.write_bytes(b'video')
            for exception, reason in [(common.requests.Timeout('url?token=secret'), 'upload_timeout'),
                                      (common.requests.ConnectionError('url?token=secret'), 'upload_network_error')]:
                with patch.object(common.requests, 'put', side_effect=exception):
                    with self.assertRaisesRegex(RuntimeError, '^' + reason + '$'):
                        client.upload('https://storage.example/upload?token=secret', path)

    def test_upload_closes_response_and_rejects_redirect(self):
        client = common.CloudClient(common.GatewayConfig('192.168.1.2', 'admin', 'secret', ''))
        response = Mock(status_code=302)
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp)/'clip.mp4'
            path.write_bytes(b'video')
            with patch.object(common.requests, 'put', return_value=response) as put:
                with self.assertRaisesRegex(RuntimeError, '^upload_http_302$'):
                    client.upload('https://storage.example/upload?token=secret', path)
                self.assertFalse(put.call_args.kwargs['allow_redirects'])
        response.close.assert_called_once()

    def test_uncovered_window_keeps_semantic_error_without_namespace_retry(self):
        hik = common.HikvisionClient(common.GatewayConfig('192.168.1.2', 'admin', 'secret', ''))
        response = Mock(status_code=200, content=b'<CMSearchResult><searchMatchItem><startTime>2026-10-05T16:00:00Z</startTime><endTime>2026-10-05T16:01:00Z</endTime><playbackURI>rtsp://192.168.1.2/Streaming/tracks/1001</playbackURI></searchMatchItem></CMSearchResult>')
        start = common.parse_iso('2026-10-05T16:09:39Z')
        with patch.object(hik.session, 'post', return_value=response) as post:
            with self.assertRaisesRegex(RuntimeError, '^recording_window_not_covered$'):
                hik.search_recording(10, start, start + timedelta(seconds=30), start + timedelta(seconds=15))
        post.assert_called_once()


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


@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'FFmpeg integration tools required')
class PlaybackIntegrationTest(unittest.TestCase):
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
