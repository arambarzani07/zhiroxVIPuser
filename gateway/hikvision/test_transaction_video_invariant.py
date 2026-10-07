from __future__ import annotations

import types
import unittest
import importlib.util
import pathlib
import tempfile
from unittest.mock import Mock, patch

import transaction_video_invariant
from transaction_video_invariant import validate_and_stamp


class TransactionVideoInvariantTests(unittest.TestCase):
    def setUp(self):
        self.job = {
            "job_id": "job-123",
            "transaction_at": "2026-10-07T09:27:59+00:00",
            "clip_start_at": "2026-10-07T09:27:44+00:00",
            "clip_end_at": "2026-10-07T09:28:14+00:00",
            "attempt_generation": 8,
        }
        self.metadata = {
            "gateway_version": "1.4.16+evergreen-17",
            "query_clock_offset_seconds": 10800,
            "recorder_utc_offset_seconds": 10800,
            "download_mode": "recorder_local_rtsp_h264_sdp",
            "requested_start": "2026-10-07T09:27:44+00:00",
            "requested_end": "2026-10-07T09:28:14+00:00",
            "segment_start": "2026-10-07T12:27:44Z",
            "segment_end": "2026-10-07T12:28:14Z",
            "duration_seconds": 30.0,
            "exact_trim": True,
            "decode_verified": True,
            "media_time_verified": True,
            "clock_check": {
                "status": "matched",
                "method": "rtsp_play_absolute_clock",
            },
            "attempt_generation": 8,
        }
        self.facts = {"firmware": "V3.4.107"}

    def test_legacy_local_clock_clip_is_stamped(self):
        result = validate_and_stamp(self.job, self.metadata, self.facts)
        self.assertTrue(result["transaction_video_invariant_verified"])
        self.assertEqual(result["transaction_video_invariant_version"], 1)
        self.assertEqual(result["transaction_video_clock_domain_seconds"], 10800)
        self.assertEqual(result["recorder_firmware"], "V3.4.107")

    def test_exact_regression_utc_candidate_is_rejected_on_legacy_firmware(self):
        metadata = dict(self.metadata)
        metadata.update(
            query_clock_offset_seconds=0,
            download_mode="rtsp_h264_sdp",
            segment_start="2026-10-07T09:27:44Z",
            segment_end="2026-10-07T09:28:14Z",
        )
        with self.assertRaisesRegex(RuntimeError, "legacy_clock_domain_mismatch"):
            validate_and_stamp(self.job, metadata, self.facts)

    def test_wrong_transaction_window_is_rejected(self):
        metadata = dict(self.metadata)
        metadata["requested_start"] = "2026-10-07T09:27:42+00:00"
        with self.assertRaisesRegex(RuntimeError, "requested_start_mismatch"):
            validate_and_stamp(self.job, metadata, self.facts)

    def test_one_second_alignment_tolerance_is_allowed(self):
        metadata = dict(self.metadata)
        metadata["requested_start"] = "2026-10-07T09:27:43+00:00"
        result = validate_and_stamp(self.job, metadata, self.facts)
        self.assertTrue(result["transaction_video_invariant_verified"])

    def test_transaction_must_be_centered_in_thirty_second_clip(self):
        job = dict(self.job)
        job["transaction_at"] = "2026-10-07T09:28:02+00:00"
        with self.assertRaisesRegex(RuntimeError, "transaction_preroll_mismatch"):
            validate_and_stamp(job, self.metadata, self.facts)

    def test_clock_mismatch_or_unknown_is_rejected(self):
        for status in ("unknown", "mismatch", None):
            with self.subTest(status=status):
                metadata = dict(self.metadata)
                metadata["clock_check"] = {"status": status}
                with self.assertRaisesRegex(RuntimeError, "clock_match_required"):
                    validate_and_stamp(self.job, metadata, self.facts)

    def test_media_integrity_proofs_are_mandatory(self):
        for key in ("exact_trim", "decode_verified", "media_time_verified"):
            with self.subTest(key=key):
                metadata = dict(self.metadata)
                metadata[key] = False
                with self.assertRaisesRegex(RuntimeError, f"{key}_required"):
                    validate_and_stamp(self.job, metadata, self.facts)

    def test_legacy_bounded_window_cannot_override_unverified_scene_clock(self):
        for status in ("unknown", "mismatch", None):
            with self.subTest(status=status):
                metadata = dict(self.metadata)
                metadata["bounded_window_verified"] = True
                metadata["media_time_verified"] = False
                metadata["clock_check"] = {"status": status, "offset_seconds": 3600}
                with self.assertRaisesRegex(RuntimeError, "clock_match_required"):
                    validate_and_stamp(self.job, metadata, self.facts)

    def test_legacy_bounded_window_cannot_override_missing_media_time_proof(self):
        metadata = dict(self.metadata)
        metadata["bounded_window_verified"] = True
        metadata["media_time_verified"] = False
        with self.assertRaisesRegex(RuntimeError, "media_time_verified_required"):
            validate_and_stamp(self.job, metadata, self.facts)

    def test_legacy_bounded_window_with_verified_scene_is_accepted(self):
        metadata = dict(self.metadata)
        metadata["bounded_window_verified"] = True
        result = validate_and_stamp(self.job, metadata, self.facts)
        self.assertEqual(result["transaction_video_time_proof"], "clock_matched")

    def test_recording_segment_must_cover_shifted_transaction_window(self):
        metadata = dict(self.metadata)
        metadata["segment_start"] = "2026-10-07T12:27:45Z"
        with self.assertRaisesRegex(RuntimeError, "recording_window_not_covered"):
            validate_and_stamp(self.job, metadata, self.facts)

    def test_attempt_generation_is_fenced(self):
        metadata = dict(self.metadata)
        metadata["attempt_generation"] = 7
        with self.assertRaisesRegex(RuntimeError, "attempt_generation_mismatch"):
            validate_and_stamp(self.job, metadata, self.facts)

    def test_future_firmware_is_not_forced_to_legacy_offset(self):
        metadata = dict(self.metadata)
        metadata.update(
            query_clock_offset_seconds=0,
            recorder_utc_offset_seconds=10800,
            download_mode="rtsp_h264_sdp",
            segment_start="2026-10-07T09:27:44Z",
            segment_end="2026-10-07T09:28:14Z",
        )
        result = validate_and_stamp(self.job, metadata, {"firmware": "V4.0.0"})
        self.assertTrue(result["transaction_video_invariant_verified"])
        self.assertEqual(result["transaction_video_clock_domain_seconds"], 0)

    def _fake_agent(self, metadata):
        calls = []

        class CloudClient:
            def call(self, action, **body):
                calls.append((action, body))
                return {"ok": True}

        def recorder_context(hik, channel_id):
            return dict(self.facts), 10800

        def process_job(cloud, heartbeat_cloud, hik, job):
            agent._recorder_clock_context(hik, 10)
            return cloud.call(
                "complete",
                job_id=job["job_id"],
                playback_metadata=dict(metadata),
            )

        agent = types.SimpleNamespace(
            CloudClient=CloudClient,
            _recorder_clock_context=recorder_context,
            process_job=process_job,
        )
        return agent, CloudClient, calls

    def test_installed_gate_stamps_metadata_before_complete(self):
        agent, CloudClient, calls = self._fake_agent(self.metadata)
        transaction_video_invariant.install(agent, lambda _: None)
        cloud = CloudClient()
        agent.process_job(cloud, cloud, object(), dict(self.job))
        self.assertEqual(len(calls), 1)
        action, body = calls[0]
        self.assertEqual(action, "complete")
        self.assertTrue(body["playback_metadata"]["transaction_video_invariant_verified"])
        self.assertEqual(
            body["playback_metadata"]["transaction_video_clock_domain_seconds"],
            10800,
        )

    def test_installed_gate_blocks_wrong_video_before_complete(self):
        metadata = dict(self.metadata)
        metadata.update(
            query_clock_offset_seconds=0,
            download_mode="rtsp_h264_sdp",
            segment_start="2026-10-07T09:27:44Z",
            segment_end="2026-10-07T09:28:14Z",
        )
        agent, CloudClient, calls = self._fake_agent(metadata)
        transaction_video_invariant.install(agent, lambda _: None)
        cloud = CloudClient()
        with self.assertRaisesRegex(RuntimeError, "legacy_clock_domain_mismatch"):
            agent.process_job(cloud, cloud, object(), dict(self.job))
        self.assertEqual(calls, [])

    def test_installed_gate_blocks_legacy_clock_mismatch_before_complete(self):
        metadata = dict(self.metadata)
        metadata.update(
            bounded_window_verified=True,
            media_time_verified=False,
            clock_check={"status": "mismatch", "offset_seconds": 3600},
        )
        agent, CloudClient, calls = self._fake_agent(metadata)
        transaction_video_invariant.install(agent, lambda _: None)
        cloud = CloudClient()
        original_call = cloud.call
        with self.assertRaisesRegex(RuntimeError, "clock_match_required"):
            agent.process_job(cloud, cloud, object(), dict(self.job))
        self.assertEqual(calls, [])
        self.assertEqual(cloud.call, original_call)

    def test_production_preflight_rejects_unknown_clock_before_storage(self):
        cloud = self._exercise_production_preflight('unknown')
        cloud.upload.assert_not_called()
        actions = [call.args[0] for call in cloud.call.call_args_list]
        self.assertNotIn('prepare_upload', actions)
        self.assertNotIn('complete', actions)
        failure = next(call for call in cloud.call.call_args_list if call.args[0] == 'fail')
        self.assertIn('clock_match_required', str(failure))

    def test_production_preflight_accepts_verified_clip_and_keeps_completion_gate(self):
        cloud = self._exercise_production_preflight('matched')
        cloud.upload.assert_called_once()
        completion = next(call for call in cloud.call.call_args_list if call.args[0] == 'complete')
        self.assertTrue(completion.kwargs['playback_metadata']['transaction_video_invariant_verified'])

    def _exercise_production_preflight(self, status):
        # Load a fresh production module so installed wrappers cannot leak to
        # other tests that exercise the base agent without bootstrap.
        spec = importlib.util.spec_from_file_location('preflight_test_agent', pathlib.Path(__file__).with_name('agent.py'))
        agent = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(agent)
        agent._recorder_clock_context = Mock(return_value=(dict(self.facts), 10800))
        transaction_video_invariant.install(agent, lambda _: None)
        hik, cloud = Mock(), Mock()
        hik._verified_playback_clock_offset = 10800
        hik._playback_codec_relay_used = False
        hik.search_recording.return_value = {
            'found': True,
            'playback_uri': 'rtsp://192.168.1.3/Streaming/tracks/1001?starttime=20261007T122744Z&endtime=20261007T122814Z',
            'segment_start': self.metadata['segment_start'],
            'segment_end': self.metadata['segment_end'],
        }
        def download(uri, path):
            path.write_bytes(b'raw')
            return 'time'
        def prepare(source, target, *args):
            target.write_bytes(b'verified-media')
            return {'duration_seconds': 30, 'exact_trim': True, 'decode_verified': True}
        hik.download_recording.side_effect = download
        cloud.call.return_value = {'signed_upload_url': 'private', 'object_path': 'clip'}
        job = dict(self.job, channel_id=10)
        with tempfile.TemporaryDirectory() as tmp, patch.object(agent, 'TEMP_DIR', pathlib.Path(tmp)), patch.object(agent, 'log'), patch.object(agent, 'prepare_browser_clip', side_effect=prepare), patch.object(agent, 'verify_clip_time', return_value={'status': status}):
            agent.process_job(cloud, Mock(), hik, job)
        return cloud


if __name__ == "__main__":
    unittest.main()
