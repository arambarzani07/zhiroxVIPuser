import pathlib
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, patch

import agent
import common

class RecorderLocalClockTests(unittest.TestCase):
    def exercise(self, status='matched', observed=-11416, preferred=0):
        start = datetime.now(timezone.utc) - timedelta(minutes=20)
        job = {'job_id':'clock-test','channel_id':10,'transaction_at':(start+timedelta(seconds=15)).isoformat(),
               'clip_start_at':start.isoformat(),'clip_end_at':(start+timedelta(seconds=30)).isoformat()}
        hik, cloud = Mock(), Mock()
        hik._verified_playback_clock_offset = preferred
        def search(channel, begin, end, transaction):
            return {'found':True, 'playback_uri':f'rtsp://192.168.1.3/Streaming/tracks/1001?name=file&size=100&starttime={begin.strftime("%Y%m%dT%H%M%SZ")}&endtime={end.strftime("%Y%m%dT%H%M%SZ")}',
                    'segment_start':begin.isoformat(),'track_id':1001}
        hik.search_recording.side_effect = search
        calls = 0
        def download(uri, path):
            nonlocal calls
            calls += 1
            if calls == 1 and preferred == 0:
                raise RuntimeError('download_rejected:http=400')
            path.write_bytes(b'recorder-file')
            return 'time'
        hik.download_recording.side_effect = download
        hik.download_playback_stream.side_effect = RuntimeError('rtsp_playback_failed:unsupported_hevc_payload')
        cloud.call.return_value = {'signed_upload_url':'https://example.test/upload','object_path':'market/clip.mp4'}
        alignment = {'status':'unknown','samples_read':1,'reason':'insufficient_clock_readings',
                     'first_sample_offset_seconds':observed}
        def prepare(source, target, *_):
            target.write_bytes(b'validated-clip')
            return {'duration_seconds':30,'exact_trim':True,'decode_verified':True}
        with tempfile.TemporaryDirectory() as tmp, patch.object(agent,'TEMP_DIR',pathlib.Path(tmp)), patch.object(agent,'log'), \
             patch.object(agent,'infer_media_start_from_osd',return_value=alignment), \
             patch.object(agent,'prepare_browser_clip',side_effect=prepare), \
             patch.object(agent,'verify_clip_time',return_value={'status':status}):
            agent.process_job(cloud, Mock(), hik, job)
            self.assertEqual(list(pathlib.Path(tmp).iterdir()), [])
        return start, cloud, hik

    def test_observed_three_hour_shift_retries_same_channel_duration_and_original_clock(self):
        start, cloud, hik = self.exercise()
        searches = hik.search_recording.call_args_list
        self.assertEqual(len(searches), 2)
        self.assertEqual(searches[0].args[1], start)
        self.assertEqual(searches[1].args[1], start+timedelta(hours=3))
        self.assertEqual(searches[1].args[2]-searches[1].args[1], timedelta(seconds=30))
        self.assertEqual(searches[1].args[0], 10)
        complete = next(c for c in cloud.call.call_args_list if c.args[0]=='complete')
        metadata = complete.kwargs['playback_metadata']
        self.assertEqual(metadata['requested_start'], start.isoformat())
        self.assertEqual(metadata['query_clock_offset_seconds'], 10800)
        self.assertTrue(metadata['media_time_verified'])
        self.assertFalse(metadata['bounded_window_verified'])
        self.assertEqual(hik._verified_playback_clock_offset, 10800)
        cloud.upload.assert_called_once()

    def test_unknown_or_mismatched_alternate_clock_never_uploads(self):
        for status in ('unknown','mismatch'):
            with self.subTest(status=status):
                _, cloud, hik = self.exercise(status=status)
                cloud.upload.assert_not_called()
                self.assertFalse(any(c.args[0]=='complete' for c in cloud.call.call_args_list))
                self.assertEqual(hik._verified_playback_clock_offset, 0)

    def test_absent_clock_evidence_does_not_guess_local_time(self):
        _, cloud, hik = self.exercise(observed=None)
        self.assertEqual(hik.search_recording.call_count, 1)
        cloud.upload.assert_not_called()

    def test_successful_convention_is_used_for_subsequent_jobs(self):
        start, cloud, hik = self.exercise(preferred=10800)
        self.assertEqual(hik.search_recording.call_count, 1)
        self.assertEqual(hik.search_recording.call_args.args[1], start+timedelta(hours=3))
        cloud.upload.assert_called_once()

    def test_wrong_failure_or_bad_observation_never_changes_query(self):
        for reason, delta, samples in [('authentication',-10800,2),('clip_decode_validation_failed',0,2),
                                      ('clip_conversion_failed',-10800,0),('clip_conversion_failed',True,2)]:
            self.assertFalse(agent._retry_recorder_local_clock(RuntimeError(reason),
                {'first_sample_offset_seconds':delta,'samples_read':samples}))
        self.assertTrue(agent._retry_recorder_local_clock(RuntimeError('clip_clock_mismatch'),
            {'offset_seconds':10800,'samples_read':2}, 10800))

if __name__=='__main__':
    unittest.main()
