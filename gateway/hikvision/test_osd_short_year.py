import unittest
import pathlib
import shutil
import subprocess
import tempfile
from unittest.mock import patch
from datetime import datetime, timedelta, timezone
from osd_time import dates_in_text, align_readings, compare_readings, read_image_clock, ocr_image

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

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('tesseract'), 'native FFmpeg/Tesseract fixture')
    def test_native_small_clock_on_busy_video_background(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = pathlib.Path(tmp)
            readings = []
            for second in (0, 3, 7):
                clock = workspace / 'clock.txt'
                clock.write_text(f'10-06-26 Tue 23:14:{30+second:02d}', encoding='utf-8')
                image = workspace / f'frame-{second}.png'
                # textfile avoids shell/filter interpolation of clock punctuation.
                filter_path = str(clock).replace('\\', '/').replace(':', '\\:')
                filters = f"drawtext=textfile='{filter_path}':fontsize=18:fontcolor=white:borderw=1:bordercolor=black:x=28:y=22"
                subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-y',
                    '-f', 'lavfi', '-i', 'testsrc2=size=1920x1080:rate=1',
                    '-vf', filters, '-frames:v', '1', str(image)], check=True, capture_output=True, timeout=20)
                # Simulate unreadable full-width OCR, then exercise the actual
                # native corner crop and sparse-text OCR recovery end to end.
                def sparse_only(path, psm=6):
                    return '' if psm == 6 else ocr_image(path, psm)
                with patch('osd_time.ocr_image', side_effect=sparse_only):
                    readings.append((second, read_image_clock(image, workspace)))
            result = align_readings(readings, self.start, self.tz)
            self.assertEqual(result['status'], 'aligned', str(readings))
            self.assertEqual(result['offset_seconds'], 0)

if __name__ == '__main__':
    unittest.main()
