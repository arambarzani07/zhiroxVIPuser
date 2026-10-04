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
            self.assertEqual(hik.session.get.call_args.kwargs['params'], {'playbackURI': self.uri})
            self.assertNotIn('data', hik.session.get.call_args.kwargs)

    def test_agent_uses_bounded_start_even_if_file_started_four_hours_earlier(self):
        now = datetime.now(timezone.utc) - timedelta(minutes=10)
        hik, cloud = Mock(), Mock()
        hik.search_recording.return_value = {'found': True, 'playback_uri': self.uri,
            'segment_start': (now-timedelta(hours=4)).isoformat(), 'segment_end': (now+timedelta(hours=1)).isoformat()}
        hik.download_recording.side_effect = lambda uri, path: path.write_bytes(b'raw')
        cloud.call.return_value = {'signed_upload_url': 'private', 'object_path': 'clip'}
        def prepare(source, target, start, download_start, duration):
            self.assertEqual(common.parse_iso(download_start), start.replace(microsecond=0))
            target.write_bytes(b'h264')
            return {'duration_seconds': duration, 'exact_trim': True}
        job = {'job_id': 'bounded', 'transaction_at': now.isoformat(), 'clip_start_at': now.isoformat(),
               'clip_end_at': (now+timedelta(seconds=30)).isoformat(), 'channel_id': 10}
        with tempfile.TemporaryDirectory() as tmp, patch.object(agent, 'TEMP_DIR', pathlib.Path(tmp)), patch.object(agent, 'log'), patch.object(agent, 'prepare_browser_clip', side_effect=prepare):
            agent.process_job(cloud, Mock(), hik, job)
            cloud.upload.assert_called_once()
            complete = next(c for c in cloud.call.call_args_list if c.args[0] == 'complete')
            self.assertFalse(complete.kwargs['playback_metadata']['media_time_verified'])
            self.assertEqual(complete.kwargs['playback_metadata']['gateway_build'], 'time-window-3')

    def test_nearby_search_result_is_not_accepted(self):
        hik = common.HikvisionClient(common.GatewayConfig('192.168.1.3', 'admin', 'secret', ''))
        hik.session = Mock()
        hik.session.post.return_value.status_code = 200
        hik.session.post.return_value.content = b'<CMSearchResult><searchMatchItem><startTime>2026-10-04T02:38:00Z</startTime><endTime>2026-10-04T02:39:00Z</endTime><playbackURI>rtsp://192.168.1.3/Streaming/tracks/1001</playbackURI></searchMatchItem></CMSearchResult>'
        with self.assertRaises(RuntimeError):
            hik.search_recording(10, self.start, self.end, self.start+timedelta(seconds=15))

if __name__ == '__main__':
    unittest.main()
