import pathlib
import subprocess
import sys
import tempfile
from osd_time import ocr_image
import unittest
from datetime import datetime, timezone, timedelta
from unittest.mock import patch
from osd_time import compare_readings, dates_in_text, verify_clip_time

class ClockTests(unittest.TestCase):
    offset=timezone(timedelta(hours=3))
    start=datetime(2026,10,4,9,38,0,tzinfo=offset)
    def readings(self,hour):
        return [(0,f'10-04-2026 Sun {hour}:38:00'),(3,f'10-04-2026 Sun {hour}:38:03'),(7,f'10-04-2026 Sun {hour}:38:07')]
    def test_matching_and_four_hour_early_footage(self):
        self.assertEqual(compare_readings(self.readings('09'),self.start,self.offset,'MDY')['status'],'matched')
        early=compare_readings(self.readings('05'),self.start,self.offset,'MDY')
        self.assertEqual(early['status'],'mismatch')
        self.assertEqual(early['offset_seconds'],-14400)
    def test_utc_request_compared_with_recorder_offset(self):
        self.assertEqual(compare_readings(self.readings('09'),self.start.astimezone(timezone.utc),self.offset,'MDY')['status'],'matched')
    def test_invalid_frozen_missing_or_inconsistent_clocks_never_verify(self):
        for reads in [[],[(0,'10-04-2026 09:38:00')],[(0,'10-04-2026 09:38:00'),(7,'10-04-2026 09:38:00')],[(0,'10-04-2026 09:38:00'),(3,'10-04-2026 09:38:30')],[(0,'10-04-2026 09:38:OO'),(3,'10-04-2026 09:38:O3')]]:
            self.assertEqual(compare_readings(reads,self.start,self.offset,'MDY')['status'],'unknown')
    def test_date_format_is_explicit_and_year_first_supported(self):
        self.assertEqual(dates_in_text('2026-10-04 Sun 09:38:00',self.offset,'YMD')[0][1],self.start)
        self.assertEqual(dates_in_text('04/10/2026 09:38:00',self.offset,'DMY')[0][1],self.start)
    def test_unavailable_ocr_does_not_stop_upload(self):
        with patch('osd_time.clock_context',side_effect=RuntimeError('no OCR')):
            self.assertEqual(verify_clip_time(None,10,pathlib.Path(__file__),self.start,30)['status'],'unknown')

class WindowsOcrSmoke(unittest.TestCase):
    @unittest.skipUnless(sys.platform=='win32','Windows native OCR integration')
    def test_native_ocr_recognizes_rendered_clock(self):
        with tempfile.TemporaryDirectory() as directory:
            image=pathlib.Path(directory)/'clock.png'
            script="Add-Type -AssemblyName System.Drawing; $b=[System.Drawing.Bitmap]::new(700,100); $g=[System.Drawing.Graphics]::FromImage($b); $g.Clear([System.Drawing.Color]::White); $f=[System.Drawing.Font]::new('Consolas',48,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Pixel); $g.DrawString('2026-10-04 Sun 09:38:00',$f,[System.Drawing.Brushes]::Black,10,20); $b.Save('"+str(image).replace("'","''")+"'); $g.Dispose(); $b.Dispose()"
            subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-Command',script],check=True,capture_output=True,timeout=20)
            import shutil
            shutil.copyfile(image,pathlib.Path.cwd()/"native-ocr-fixture.png")
            text=ocr_image(image)
            self.assertTrue(dates_in_text(text,ClockTests.offset,'YMD'),f'Native OCR output: {text!r}')

if __name__=='__main__': unittest.main()
