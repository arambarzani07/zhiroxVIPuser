import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, patch
from urllib.parse import parse_qs, urlsplit
import common
import agent


class TimeWindowTest(unittest.TestCase):
    def setUp(self):
        self.start = datetime.fromisoformat('2026-10-04T09:37:45+03:00')
        self.end = self.start + timedelta(seconds=30)
        self.uri = ('rtsp://192.168.1.3/Streaming/tracks/1001/'
                    '?starttime=20261004T023800Z&amp;endtime=20261004T070000Z'
                    '&amp;name=earlier-file&amp;size=123456')

    def test_request_uses_transaction_utc_window_not_file_start(self):
        uri = common.bounded_playback_uri(self.uri, self.start, self.end, 1001)
        q = parse_qs(urlsplit(uri).query)
        self.assertEqual(q, {'starttime': ['20261004T063745Z'], 'endtime': ['20261004T063815Z']})
        self.assertNotIn('earlier-file', uri)

    def test_invalid_windows_and_channel_are_rejected(self):
        for start, end, track in [(self.start, self.start, 1001),
                                  (self.start.replace(tzinfo=None), self.end, 1001),
                                  (self.start, self.end, 101)]:
            with self.assertRaises(ValueError):
                common.bounded_playback_uri(self.uri, start, end, track)

    def test_download_uses_post_body_and_query_fallback_only_if_unsupported(self):
        hik = common.HikvisionClient(common.GatewayConfig('192.168.1.3', 'admin', 'secret', ''))
        hik.session = Mock()
        response = Mock(status_code=200, headers={'content-type': 'video/mp4'})
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        response.iter_content.return_value = [b'video']
        hik.session.post.return_value = response
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp)/'clip.mp4'
            hik.download_recording(self.uri, path)
            self.assertEqual(path.read_bytes(), b'video')
            self.assertIn(b'<playbackURI>', hik.session.post.call_args.kwargs['data'])
            hik.session.get.assert_not_called()
            unsupported = Mock(status_code=405)
            hik.session.post.return_value = unsupported
            hik.session.get.return_value = response
            hik.download_recording(self.uri, path)
            self.assertEqual(hik.session.get.call_args.kwargs['data'], hik.session.post.call_args.kwargs['data'])
            self.assertNotIn('params', hik.session.get.call_args.kwargs)

    def test_post_400_retries_get_with_same_bounded_xml(self):
        hik = common.HikvisionClient(common.GatewayConfig('192.168.1.3', 'admin', 'secret', ''))
        hik.session = Mock()
        hik.session.post.return_value = Mock(status_code=400)
        response = Mock(status_code=200, headers={'content-type': 'video/mp4'})
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        response.iter_content.return_value = [b'video']
        hik.session.get.return_value = response
        uri = common.bounded_playback_uri(self.uri, self.start, self.end, 1001)
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp)/'clip.mp4'
            hik.download_recording(uri, path)
            self.assertEqual(path.read_bytes(), b'video')
        body = hik.session.get.call_args.kwargs['data']
        self.assertEqual(body, hik.session.post.call_args.kwargs['data'])
        self.assertIn(b'20261004T063745Z', body)
        self.assertNotIn(b'earlier-file', body)
        hik.session.post.return_value.close.assert_called_once()

    def test_device_rejection_records_status_without_writing_video(self):
        hik = common.HikvisionClient(common.GatewayConfig('192.168.1.3', 'admin', 'secret', ''))
        hik.session = Mock()
        response = Mock(status_code=400, headers={'content-type': 'application/xml'})
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        response.iter_content.return_value = [b'<ResponseStatus><statusCode>6</statusCode><subStatusCode>badXmlContent</subStatusCode><requestURL>secret</requestURL></ResponseStatus>']
        hik.session.post.return_value = Mock(status_code=400)
        hik.session.get.return_value = response
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp)/'clip.mp4'
            with self.assertRaisesRegex(RuntimeError, 'statusCode=6;subStatusCode=badXmlContent') as result:
                hik.download_recording(common.bounded_playback_uri(self.uri, self.start, self.end, 1001), path)
            self.assertNotIn('secret', str(result.exception))
            self.assertFalse(path.exists())

    def test_query_export_preserves_window_and_escapes_nested_query(self):
        hik = common.HikvisionClient(common.GatewayConfig('192.168.1.3', 'admin', 'secret', ''))
        hik.session = Mock()
        rejected = Mock(status_code=400, headers={'content-type': 'application/xml'})
        ok = Mock(status_code=200, headers={'content-type': 'video/mp4'})
        ok.__enter__ = Mock(return_value=ok)
        ok.__exit__ = Mock(return_value=False)
        ok.iter_content.return_value = [b'video']
        hik.session.post.return_value = rejected
        hik.session.get.side_effect = [rejected, rejected, rejected, ok]
        uri = common.bounded_playback_uri(self.uri, self.start, self.end, 1001)
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp)/'clip.mp4'
            self.assertEqual(hik.download_recording(uri, path), 'http_query_time')
            self.assertEqual(path.read_bytes(), b'video')
        kwargs = hik.session.get.call_args.kwargs
        self.assertEqual(kwargs['params'], {'playbackURI': uri})
        self.assertNotIn('data', kwargs)
        self.assertNotIn('secret', uri)
        self.assertNotIn('earlier-file', uri)

    def test_rtsp_fallback_transcodes_to_browser_h264(self):
        hik = common.HikvisionClient(common.GatewayConfig('192.168.1.3', 'admin', 'secret', ''))
        uri = common.bounded_playback_uri(self.uri, self.start, self.end, 1001)
        with tempfile.TemporaryDirectory() as tmp, patch.object(common, 'find_ffmpeg', return_value='ffmpeg'), patch.object(common, 'run_background') as run:
            path = pathlib.Path(tmp)/'raw.mp4'
            def successful_run(*args, **kwargs):
                path.write_bytes(b'video')
                return Mock(returncode=0, stderr=b'')
            run.side_effect = successful_run
            hik.download_playback_stream(uri, path, 30)
            args = run.call_args.args[0]
            self.assertIn('libx264', args)
            self.assertIn('aac', args)
            self.assertIn('ignore_err', args)
            self.assertIn('+discardcorrupt+genpts', args)
            self.assertEqual(args[args.index('-t')+1], '30')

    def test_rtsp_reason_is_allowlisted_without_credentials(self):
        hik = common.HikvisionClient(common.GatewayConfig('192.168.1.3', 'admin', 'secret', ''))
        uri = common.bounded_playback_uri(self.uri, self.start, self.end, 1001)
        with tempfile.TemporaryDirectory() as tmp, patch.object(common, 'find_ffmpeg', return_value='ffmpeg'), patch.object(common, 'run_background', return_value=Mock(returncode=1, stderr=b'rtsp://admin:secret@host Unsupported (HEVC) NAL type (62)')):
            with self.assertRaisesRegex(RuntimeError, '^rtsp_playback_failed:unsupported_hevc_payload:.*"nal":\\[62\\]') as caught:
                hik.download_playback_stream(uri, pathlib.Path(tmp)/'raw.mp4', 30)
            self.assertNotIn('secret', str(caught.exception))

    def test_agent_uses_bounded_start_even_if_file_started_four_hours_earlier(self):
        now = datetime.now(timezone.utc) - timedelta(minutes=10)
        hik, cloud = Mock(), Mock()
        hik.search_recording.return_value = {'found': True, 'playback_uri': self.uri,
            'segment_start': (now-timedelta(hours=4)).isoformat(), 'segment_end': (now+timedelta(hours=1)).isoformat()}
        def bounded_download(uri, path):
            path.write_bytes(b'raw')
            return 'time'
        hik.download_recording.side_effect = bounded_download
        cloud.call.return_value = {'signed_upload_url': 'private', 'object_path': 'clip'}
        def prepare(source, target, start, download_start, duration):
            self.assertEqual(common.parse_iso(download_start), start.replace(microsecond=0))
            target.write_bytes(b'h264')
            return {'duration_seconds': duration, 'exact_trim': True}
        job = {'job_id': 'bounded', 'transaction_at': now.isoformat(), 'clip_start_at': now.isoformat(),
               'clip_end_at': (now+timedelta(seconds=30)).isoformat(), 'channel_id': 10}
        with tempfile.TemporaryDirectory() as tmp, patch.object(agent, 'TEMP_DIR', pathlib.Path(tmp)), patch.object(agent, 'log'), patch.object(agent, 'prepare_browser_clip', side_effect=prepare), patch.object(agent, 'verify_clip_time', return_value={'status': 'unknown'}):
            agent.process_job(cloud, Mock(), hik, job)
            cloud.upload.assert_called_once()
            complete = next(c for c in cloud.call.call_args_list if c.args[0] == 'complete')
            self.assertFalse(complete.kwargs['playback_metadata']['media_time_verified'])
            self.assertTrue(complete.kwargs['playback_metadata']['bounded_window_verified'])
            self.assertEqual(complete.kwargs['playback_metadata']['gateway_build'], 'bounded-fallback-1')

    def test_namespace_retry_preserves_bounded_uri(self):
        hik = common.HikvisionClient(common.GatewayConfig('192.168.1.3', 'admin', 'secret', ''))
        hik.session = Mock()
        rejected = Mock(status_code=400)
        ok = Mock(status_code=200, headers={'content-type': 'video/mp4'})
        ok.__enter__ = Mock(return_value=ok)
        ok.__exit__ = Mock(return_value=False)
        ok.iter_content.return_value = [b'video']
        hik.session.post.side_effect = [rejected, ok]
        hik.session.get.return_value = rejected
        uri = common.bounded_playback_uri(self.uri, self.start, self.end, 1001)
        with tempfile.TemporaryDirectory() as tmp:
            hik.download_recording(uri, pathlib.Path(tmp)/'clip.mp4')
        bodies = [c.kwargs['data'] for c in hik.session.post.call_args_list]
        self.assertIn(b'www.hikvision.com', bodies[1])
        for body in bodies:
            self.assertIn(b'20261004T063745Z', body)
            self.assertNotIn(b'earlier-file', body)

    def test_rtsp_fallback_is_historical_and_redacts_failures(self):
        hik = common.HikvisionClient(common.GatewayConfig('192.168.1.3', 'admin', 'p@ss:word', ''))
        uri = common.bounded_playback_uri(self.uri, self.start, self.end, 1001)
        with tempfile.TemporaryDirectory() as tmp, patch.object(common, 'find_ffmpeg', return_value='ffmpeg'), patch.object(common.subprocess, 'run', side_effect=RuntimeError('p@ss:word')) as run:
            path = pathlib.Path(tmp)/'raw.mp4'
            with self.assertRaisesRegex(RuntimeError, '^rtsp_playback_failed$'):
                hik.download_playback_stream(uri, path, 30)
            args = run.call_args.args[0]
            rtsp = args[args.index('-i')+1]
            self.assertIn('p%40ss%3Aword', rtsp)
            self.assertIn('20261004T063745Z', rtsp)
            self.assertNotIn('earlier-file', rtsp)
            self.assertEqual(args[args.index('-t')+1], '30')
            self.assertFalse(path.exists())

    def test_rtsp_clock_mismatch_does_not_upload(self):
        now = datetime.now(timezone.utc) - timedelta(minutes=10)
        hik, cloud = Mock(), Mock()
        hik.search_recording.return_value = {'found': True, 'playback_uri': self.uri}
        hik.download_recording.side_effect = RuntimeError('download_rejected:http=400')
        hik.download_playback_stream.side_effect = lambda uri, path, duration: path.write_bytes(b'raw')
        def prepare(source, target, *args):
            target.write_bytes(b'h264')
            return {'duration_seconds': 30, 'exact_trim': True}
        job = {'job_id': 'clock', 'transaction_at': now.isoformat(), 'clip_start_at': now.isoformat(),
               'clip_end_at': (now+timedelta(seconds=30)).isoformat(), 'channel_id': 10}
        with tempfile.TemporaryDirectory() as tmp, patch.object(agent, 'TEMP_DIR', pathlib.Path(tmp)), patch.object(agent, 'log'), patch.object(agent, 'prepare_browser_clip', side_effect=prepare), patch.object(agent, 'verify_clip_time', return_value={'status': 'mismatch'}):
            agent.process_job(cloud, Mock(), hik, job)
        cloud.upload.assert_not_called()
        self.assertFalse(any(c.args[0] == 'complete' for c in cloud.call.call_args_list))
        failure = next(c for c in cloud.call.call_args_list if c.args[0] == 'fail')
        self.assertIn('clip_clock_mismatch', failure.kwargs['error'])

    def test_rtsp_unknown_clock_uploads_only_bounded_window(self):
        now = datetime.now(timezone.utc) - timedelta(minutes=10)
        hik, cloud = Mock(), Mock()
        hik.search_recording.return_value = {'found': True, 'playback_uri': self.uri}
        hik.download_recording.side_effect = RuntimeError('download_rejected:http=400')
        hik.download_playback_stream.side_effect = lambda uri, path, duration: path.write_bytes(b'raw')
        cloud.call.return_value = {'signed_upload_url': 'private', 'object_path': 'clip'}
        def prepare(source, target, start, download_start, duration):
            self.assertEqual(common.parse_iso(download_start), start.replace(microsecond=0))
            target.write_bytes(b'h264')
            return {'duration_seconds': 30, 'exact_trim': True}
        job = {'job_id': 'clock-unknown', 'transaction_at': now.isoformat(), 'clip_start_at': now.isoformat(),
               'clip_end_at': (now+timedelta(seconds=30)).isoformat(), 'channel_id': 10}
        with tempfile.TemporaryDirectory() as tmp, patch.object(agent, 'TEMP_DIR', pathlib.Path(tmp)), patch.object(agent, 'log'), patch.object(agent, 'prepare_browser_clip', side_effect=prepare), patch.object(agent, 'verify_clip_time', return_value={'status': 'unknown'}):
            agent.process_job(cloud, Mock(), hik, job)
        cloud.upload.assert_called_once()
        complete = next(c for c in cloud.call.call_args_list if c.args[0] == 'complete')
        metadata = complete.kwargs['playback_metadata']
        self.assertEqual(metadata['download_mode'], 'rtsp_time')
        self.assertTrue(metadata['bounded_window_verified'])
        self.assertFalse(metadata['media_time_verified'])

    def test_query_export_with_unknown_clock_uploads_bounded_window(self):
        now = datetime.now(timezone.utc) - timedelta(minutes=10)
        hik, cloud = Mock(), Mock()
        hik.search_recording.return_value = {'found': True, 'playback_uri': self.uri}
        def download(uri, path):
            path.write_bytes(b'raw')
            return 'http_query_time'
        hik.download_recording.side_effect = download
        cloud.call.return_value = {'signed_upload_url': 'private', 'object_path': 'clip'}
        def prepare(source, target, start, download_start, duration):
            self.assertEqual(common.parse_iso(download_start), start.replace(microsecond=0))
            target.write_bytes(b'h264')
            return {'duration_seconds': 30, 'exact_trim': True}
        job = {'job_id': 'query-clock', 'transaction_at': now.isoformat(), 'clip_start_at': now.isoformat(),
               'clip_end_at': (now+timedelta(seconds=30)).isoformat(), 'channel_id': 10}
        with tempfile.TemporaryDirectory() as tmp, patch.object(agent, 'TEMP_DIR', pathlib.Path(tmp)), patch.object(agent, 'log'), patch.object(agent, 'prepare_browser_clip', side_effect=prepare), patch.object(agent, 'verify_clip_time', return_value={'status': 'unknown'}):
            agent.process_job(cloud, Mock(), hik, job)
        cloud.upload.assert_called_once()
        complete = next(c for c in cloud.call.call_args_list if c.args[0] == 'complete')
        metadata = complete.kwargs['playback_metadata']
        self.assertEqual(metadata['download_mode'], 'http_query_time')
        self.assertTrue(metadata['bounded_window_verified'])
        self.assertFalse(metadata['media_time_verified'])

    def test_unreadable_file_osd_retries_bounded_rtsp_before_upload(self):
        now = datetime.now(timezone.utc) - timedelta(minutes=10)
        hik, cloud = Mock(), Mock()
        hik.search_recording.return_value = {
            'found': True,
            'playback_uri': self.uri,
            'segment_start': (now - timedelta(hours=4)).isoformat(),
            'segment_end': (now + timedelta(hours=1)).isoformat(),
        }
        calls = {'n': 0}
        def download(uri, path):
            calls['n'] += 1
            if calls['n'] == 1:
                raise RuntimeError('download_rejected:http=400')
            path.write_bytes(b'file-export')
            return 'time'
        hik.download_recording.side_effect = download
        hik.download_playback_stream.side_effect = lambda uri, path, duration: path.write_bytes(b'bounded-rtsp')
        cloud.call.return_value = {'signed_upload_url': 'private', 'object_path': 'clip'}
        def prepare(source, target, start, download_start, duration):
            self.assertEqual(source.read_bytes(), b'bounded-rtsp')
            self.assertEqual(common.parse_iso(download_start), start.replace(microsecond=0))
            target.write_bytes(b'h264')
            return {'duration_seconds': 30, 'exact_trim': True}
        job = {'job_id': 'file-osd-fallback', 'transaction_at': now.isoformat(), 'clip_start_at': now.isoformat(),
               'clip_end_at': (now+timedelta(seconds=30)).isoformat(), 'channel_id': 10}
        with tempfile.TemporaryDirectory() as tmp, patch.object(agent, 'TEMP_DIR', pathlib.Path(tmp)), patch.object(agent, 'log'), patch.object(agent, 'infer_media_start_from_osd', return_value={'status': 'unknown', 'reason': 'clock_reading_unavailable'}), patch.object(agent, 'prepare_browser_clip', side_effect=prepare), patch.object(agent, 'verify_clip_time', return_value={'status': 'unknown'}):
            agent.process_job(cloud, Mock(), hik, job)
        hik.download_playback_stream.assert_called_once()
        cloud.upload.assert_called_once()
        complete = next(c for c in cloud.call.call_args_list if c.args[0] == 'complete')
        metadata = complete.kwargs['playback_metadata']
        self.assertEqual(metadata['download_mode'], 'rtsp_time')
        self.assertTrue(metadata['bounded_window_verified'])
        self.assertEqual(metadata['source_clock_alignment']['fallback'], 'bounded_rtsp')

    def test_nearby_search_result_is_not_accepted(self):
        hik = common.HikvisionClient(common.GatewayConfig('192.168.1.3', 'admin', 'secret', ''))
        hik.session = Mock()
        hik.session.post.return_value.status_code = 200
        hik.session.post.return_value.content = b'<CMSearchResult><searchMatchItem><startTime>2026-10-04T02:38:00Z</startTime><endTime>2026-10-04T02:39:00Z</endTime><playbackURI>rtsp://192.168.1.3/Streaming/tracks/1001</playbackURI></searchMatchItem></CMSearchResult>'
        with self.assertRaises(RuntimeError):
            hik.search_recording(10, self.start, self.end, self.start+timedelta(seconds=15))

if __name__ == '__main__':
    unittest.main()
