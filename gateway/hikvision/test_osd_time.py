import pathlib
import subprocess
import sys
import tempfile
from osd_time import ocr_image
import unittest
from datetime import datetime, timezone, timedelta
from unittest.mock import patch
from osd_time import align_readings, compare_readings, dates_in_text, verify_clip_time, read_image_clock
from types import SimpleNamespace

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
    def test_source_alignment_recovers_real_file_start_when_isapi_metadata_is_hours_late(self):
        requested=datetime(2026,10,6,9,39,9,tzinfo=self.offset)
        reads=[
            (0,'10-06-2026 Tue 06:26:25'),
            (3,'10-06-2026 Tue 06:26:28'),
            (7,'10-06-2026 Tue 06:26:32'),
        ]
        aligned=align_readings(reads,requested,self.offset)
        self.assertEqual(aligned['status'],'aligned')
        self.assertEqual(aligned['date_order'],'MDY')
        self.assertEqual(aligned['offset_seconds'],-11564.0)
        self.assertTrue(aligned['media_start_at'].startswith('2026-10-06T03:26:25'))
    def test_ambiguous_or_frozen_source_clock_does_not_align(self):
        requested=datetime(2026,10,6,9,39,9,tzinfo=self.offset)
        frozen=[(0,'10-06-2026 Tue 06:26:25'),(3,'10-06-2026 Tue 06:26:25')]
        self.assertEqual(align_readings(frozen,requested,self.offset)['status'],'unknown')
    def test_unavailable_ocr_does_not_stop_generic_verifier(self):
        with patch('osd_time.infer_media_start_from_osd',return_value={'status':'unknown','reason':'no OCR'}):
            self.assertEqual(verify_clip_time(None,10,pathlib.Path(__file__),self.start,30)['status'],'unknown')
    def test_unknown_verifier_preserves_diagnostics_without_verifying(self):
        diagnostic={
            'status':'unknown',
            'reason':'insufficient_clock_readings',
            'samples_read':1,
            'first_displayed_at':'2026-10-04T09:38:00+03:00',
            'first_sample_offset_seconds':0.0,
            'clock_candidates':['2026-10-04T09:38:00+03:00'],
            'frames_extracted':5,
            'source_bytes':12345,
            'source_codecs':['h264'],
            'source_probe_ok':True,
        }
        with patch('osd_time.infer_media_start_from_osd',return_value=diagnostic):
            result=verify_clip_time(None,10,pathlib.Path(__file__),self.start,30)
        self.assertEqual(result['status'],'unknown')
        self.assertEqual(result['samples_read'],1)
        self.assertEqual(result['first_sample_offset_seconds'],0.0)
        self.assertEqual(result['frames_extracted'],5)
        self.assertEqual(result['source_codecs'],['h264'])

class OcrRecipeTests(unittest.TestCase):
    def test_cached_crop_reads_each_new_frame_and_saves_search_work(self):
        cache = {}
        clock = '10-04-2026 09:38:00'
        with tempfile.TemporaryDirectory() as tmp:
            workspace = pathlib.Path(tmp)
            with patch('osd_time.find_ffmpeg', return_value='ffmpeg'), patch(
                'osd_time.run_background', return_value=SimpleNamespace(returncode=0)
            ) as run, patch('osd_time.ocr_image') as ocr:
                # Discover a corner after both normal bands and the first corner.
                ocr.side_effect = ['', '', '', '', '', clock]
                self.assertIn(clock, read_image_clock(workspace/'first.png', workspace, cache))
                first_calls = run.call_count
                self.assertGreater(first_calls, 1)
                run.reset_mock()
                ocr.side_effect = ['10-04-2026 09:38:03']
                text = read_image_clock(workspace/'second.png', workspace, cache)
                self.assertIn('09:38:03', text)
                self.assertNotIn('09:38:00', text)
                self.assertEqual(run.call_count, 1)
                self.assertIn(str(workspace/'second.png'), run.call_args.args[0])

    def test_failed_cached_crop_falls_back_and_refreshes_settings(self):
        cache = {'recipe': ('old-crop', 11)}
        with tempfile.TemporaryDirectory() as tmp:
            workspace = pathlib.Path(tmp)
            with patch('osd_time.find_ffmpeg', return_value='ffmpeg'), patch(
                'osd_time.run_background', return_value=SimpleNamespace(returncode=0)
            ), patch('osd_time.ocr_image', side_effect=['unreadable', '', '10-04-2026 09:38:07']):
                text = read_image_clock(workspace/'frame.png', workspace, cache)
            self.assertIn('09:38:07', text)
            self.assertNotEqual(cache['recipe'], ('old-crop', 11))

    def test_cached_crop_never_fabricates_a_missing_clock(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = pathlib.Path(tmp)
            with patch('osd_time.find_ffmpeg', return_value='ffmpeg'), patch(
                'osd_time.run_background', return_value=SimpleNamespace(returncode=0)
            ), patch('osd_time.ocr_image', return_value='unreadable'):
                text = read_image_clock(workspace/'frame.png', workspace, {'recipe': ('crop', 6)})
            self.assertEqual(dates_in_text(text, ClockTests.offset), [])

    def test_native_full_frame_clock_is_read_before_destructive_cropping(self):
        cache = {}
        with tempfile.TemporaryDirectory() as tmp:
            workspace = pathlib.Path(tmp)
            with patch('osd_time.run_background') as run, patch(
                'osd_time.ocr_image', return_value='10-08-2026 Thu 01:05:14'
            ) as ocr:
                text = read_image_clock(workspace/'frame.png', workspace, cache)
            self.assertIn('01:05:14', text)
            ocr.assert_called_once_with(workspace/'frame.png', psm=6)
            run.assert_not_called()
            self.assertEqual(cache['recipe'], ('null', 6))


class WindowsOcrSmoke(unittest.TestCase):
    @unittest.skipUnless(sys.platform=='win32','Windows packaged OCR integration')
    def test_packaged_ocr_recognizes_rendered_clock(self):
        with tempfile.TemporaryDirectory() as directory:
            image=pathlib.Path(directory)/'clock.png'
            script="Add-Type -AssemblyName System.Drawing; $b=[System.Drawing.Bitmap]::new(700,100); $g=[System.Drawing.Graphics]::FromImage($b); $g.Clear([System.Drawing.Color]::Black); $f=[System.Drawing.Font]::new('Consolas',48,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Pixel); $g.DrawString('2026-10-04 Sun 09:38:00',$f,[System.Drawing.Brushes]::White,10,20); $b.Save('"+str(image).replace("'","''")+"'); $g.Dispose(); $b.Dispose()"
            subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-Command',script],check=True,capture_output=True,timeout=20)
            import shutil
            shutil.copyfile(image,pathlib.Path.cwd()/"native-ocr-fixture.png")
            text=ocr_image(image)
            self.assertTrue(dates_in_text(text,ClockTests.offset,'YMD'),f'Packaged OCR output: {text!r}')

if __name__=='__main__': unittest.main()
