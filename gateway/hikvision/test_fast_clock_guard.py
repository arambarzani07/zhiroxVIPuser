import pathlib
import tempfile
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

import fast_clock_guard


class FastClockGuardTests(unittest.TestCase):
    start = datetime(2026, 10, 7, 6, 55, 19, tzinfo=timezone.utc)

    def _verify_with_texts(self, texts):
        with tempfile.TemporaryDirectory() as tmp:
            source = pathlib.Path(tmp) / 'clip.mp4'
            source.write_bytes(b'x')
            with patch.object(fast_clock_guard, '_extract_sample', return_value=True), patch.object(
                fast_clock_guard, '_quick_clock_text', side_effect=texts
            ):
                return fast_clock_guard.verify_transport_contradiction(
                    source, self.start, 30
                )

    def test_two_advancing_visible_clocks_match(self):
        result = self._verify_with_texts([
            '2026-10-07 09:55:19',
            '2026-10-07 09:55:26',
        ])
        self.assertEqual(result['status'], 'matched')
        self.assertEqual(result['offset_seconds'], 0)
        self.assertEqual(result['samples_read'], 2)

    def test_two_consistent_wrong_visible_clocks_veto(self):
        result = self._verify_with_texts([
            '2026-10-07 10:55:19',
            '2026-10-07 10:55:26',
        ])
        self.assertEqual(result['status'], 'mismatch')
        self.assertEqual(result['offset_seconds'], 3600)
        self.assertEqual(result['reason'], 'visible_clock_mismatch')

    def test_absent_osd_stays_unknown(self):
        result = self._verify_with_texts(['', ''])
        self.assertEqual(result['status'], 'unknown')
        self.assertEqual(result['reason'], 'insufficient_clock_readings')
        self.assertEqual(result['samples_read'], 0)

    def test_one_reading_never_guesses(self):
        result = self._verify_with_texts([
            '2026-10-07 09:55:19',
            '',
        ])
        self.assertEqual(result['status'], 'unknown')
        self.assertEqual(result['reason'], 'insufficient_clock_readings')
        self.assertEqual(result['samples_read'], 1)


if __name__ == '__main__':
    unittest.main()
