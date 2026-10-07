import unittest
from unittest.mock import Mock
from datetime import timezone

import recording_recovery


class LegacyRecorderClockPriorityTests(unittest.TestCase):
    def _job(self):
        return {
            'channel_id': 10,
            'clip_start_at': '2026-10-07T09:27:44+00:00',
            'clip_end_at': '2026-10-07T09:28:14+00:00',
            'transaction_at': '2026-10-07T09:27:59+00:00',
        }

    def _hik(self, firmware='V3.4.107', shifted_found=True, utc_found=True):
        hik = Mock()
        hik._verified_playback_clock_offset = 0
        hik.playback_diagnostics.return_value = {
            'firmware': firmware,
            'nvr_time': '2026-10-07T12:27:59+03:00',
        }

        def search(channel, start, end, transaction):
            hour = start.astimezone(timezone.utc).hour
            if hour == 9:
                return {'found': utc_found}
            if hour == 12:
                return {'found': shifted_found}
            return {'found': False}

        hik.search_recording.side_effect = search
        return hik

    def test_legacy_firmware_prefers_recorder_local_even_if_utc_can_match(self):
        hik = self._hik(shifted_found=True, utc_found=True)
        log = Mock()
        recording_recovery._prefer_working_clock_convention(hik, self._job(), log)
        self.assertEqual(hik._verified_playback_clock_offset, 10800)
        self.assertTrue(any('legacy_local_clock_priority=true' in str(call) for call in log.call_args_list))
        first_start = hik.search_recording.call_args_list[0].args[1]
        self.assertEqual(first_start.astimezone(timezone.utc).hour, 12)

    def test_legacy_firmware_keeps_utc_first_when_shifted_window_missing(self):
        hik = self._hik(shifted_found=False, utc_found=True)
        recording_recovery._prefer_working_clock_convention(hik, self._job(), Mock())
        self.assertEqual(hik._verified_playback_clock_offset, 0)

    def test_newer_firmware_preserves_existing_utc_first_policy(self):
        hik = self._hik(firmware='V4.0.0', shifted_found=True, utc_found=True)
        recording_recovery._prefer_working_clock_convention(hik, self._job(), Mock())
        self.assertEqual(hik._verified_playback_clock_offset, 0)
        first_start = hik.search_recording.call_args_list[0].args[1]
        self.assertEqual(first_start.astimezone(timezone.utc).hour, 9)


if __name__ == '__main__':
    unittest.main()
