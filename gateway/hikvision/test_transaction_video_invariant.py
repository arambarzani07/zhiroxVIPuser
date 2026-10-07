from __future__ import annotations

import unittest

from transaction_video_invariant import validate_and_stamp


class TransactionVideoInvariantTests(unittest.TestCase):
    def setUp(self):
        self.job = {
            "transaction_at": "2026-10-07T09:27:59+00:00",
            "clip_start_at": "2026-10-07T09:27:44+00:00",
            "clip_end_at": "2026-10-07T09:28:14+00:00",
            "attempt_generation": 8,
        }
        self.metadata = {
            "gateway_version": "1.4.16+evergreen-16",
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
        metadata["requested_start"] = "2026-10-07T09:27:43+00:00"
        with self.assertRaisesRegex(RuntimeError, "requested_start_mismatch"):
            validate_and_stamp(self.job, metadata, self.facts)

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


if __name__ == "__main__":
    unittest.main()
