import unittest
from datetime import datetime, timedelta, timezone
from osd_time import dates_in_text, align_readings, compare_readings

class ShortYearClockTests(unittest.TestCase):
    tz = timezone(timedelta(hours=3))
    start = datetime(2026, 10, 6, 23, 14, 30, tzinfo=tz)

    def readings(self, date='10-06-26', hour='23'):
        return [(0, f'{date} Tue {hour}:14:30'), (3, f'{date} Tue {hour}:14:33'), (7, f'{date} Tue {hour}:14:37')]

    def test_short_year_month_first_matches_transaction(self):
        self.assertEqual(dates_in_text('10-06-26 Tue 23:14:30', self.tz, 'MDY')[0][1], self.start)
        self.assertEqual(align_readings(self.readings(), self.start, self.tz)['status'], 'aligned')
        self.assertEqual(compare_readings(self.readings(), self.start, self.tz, 'MDY')['status'], 'matched')

    def test_short_year_day_first_is_supported(self):
        self.assertEqual(dates_in_text('06/10/26 Tue 23:14:30', self.tz, 'DMY')[0][1], self.start)

    def test_four_hour_early_clip_still_reports_mismatch(self):
        result = compare_readings(self.readings(hour='19'), self.start, self.tz, 'MDY')
        self.assertEqual(result['status'], 'mismatch')
        self.assertEqual(result['offset_seconds'], -14400)

    def test_cached_three_day_old_thumbnail_cannot_align(self):
        self.assertEqual(align_readings(self.readings(date='10-03-26'), self.start, self.tz)['status'], 'unknown')

    def test_invalid_year_digits_and_frozen_clock_still_rejected(self):
        self.assertEqual(dates_in_text('10-06-2O 23:14:30', self.tz), [])
        frozen = [(0,'10-06-26 23:14:30'), (3,'10-06-26 23:14:30')]
        self.assertEqual(align_readings(frozen, self.start, self.tz)['status'], 'unknown')

if __name__ == '__main__':
    unittest.main()
