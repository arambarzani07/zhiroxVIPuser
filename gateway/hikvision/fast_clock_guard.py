from __future__ import annotations

import pathlib
import sys
import tempfile
from datetime import datetime

from common import find_ffmpeg, run_background
from osd_time import BAGHDAD_OFFSET, align_readings, dates_in_text


FAST_OCR_TIMEOUT_SECONDS = 6
FAST_SAMPLE_DECODE_TIMEOUT_SECONDS = 20
FAST_MOSAIC_WIDTH = 3600


def _ocr_fast(path: pathlib.Path, psm: int) -> str:
    """Run bounded OCR for the transport-clock contradiction guard.

    This deliberately has a much smaller timeout than the exhaustive OSD
    verifier. It is never sufficient by itself to approve a clip: approval on
    this path also requires the independently verified RTSP absolute clock
    attestation captured from the NVR's successful PLAY response.
    """
    root = pathlib.Path(getattr(sys, '_MEIPASS', pathlib.Path(__file__).resolve().parent))
    bundled = root / 'ocr' / 'tesseract.exe'
    command = [
        str(bundled) if bundled.exists() else 'tesseract',
        str(path),
        'stdout',
        '--psm',
        str(psm),
        '-l',
        'eng',
    ]
    if bundled.exists():
        command += ['--tessdata-dir', str(root / 'ocr' / 'tessdata')]
    try:
        result = run_background(
            command,
            capture_output=True,
            timeout=FAST_OCR_TIMEOUT_SECONDS,
            creationflags=0x08000000 if sys.platform == 'win32' else 0,
        )
    except Exception:
        return ''
    if result.returncode:
        return ''
    return result.stdout.decode('utf-8', errors='replace')


def _extract_sample(source: pathlib.Path, image: pathlib.Path, second: float) -> bool:
    """Decode from the beginning, then discard to the sample time.

    Indexless Hikvision exports can lose decoder parameter sets when input-side
    seeking is used, so keep the same safe decode order as the exhaustive path.
    """
    try:
        result = run_background(
            [
                find_ffmpeg(),
                '-nostdin',
                '-loglevel',
                'error',
                '-y',
                '-i',
                str(source),
                '-ss',
                str(second),
                '-frames:v',
                '1',
                str(image),
            ],
            capture_output=True,
            timeout=FAST_SAMPLE_DECODE_TIMEOUT_SECONDS,
        )
    except Exception:
        return False
    return result.returncode == 0 and image.exists()


def _quick_clock_text(image: pathlib.Path, workspace: pathlib.Path, label: str) -> str:
    """Read top and bottom OSD bands with a bounded number of OCR passes.

    The two bands include all four common Hikvision clock corners. They are
    stacked and enlarged as one image so a single OCR pass sees both sides. A
    normal and inverted variant are tried with two segmentation modes: at most
    four OCR calls per video sample instead of the exhaustive corner scanner.
    """
    normal = workspace / f'{label}-bands.png'
    inverted = workspace / f'{label}-bands-inverted.png'
    filters = (
        '[0:v]split=2[top_src][bottom_src];'
        '[top_src]crop=iw:ih*0.28:0:0,'
        f'scale={FAST_MOSAIC_WIDTH}:-1[top];'
        '[bottom_src]crop=iw:ih*0.28:0:ih-ih*0.28,'
        f'scale={FAST_MOSAIC_WIDTH}:-1[bottom];'
        '[top][bottom]vstack=inputs=2,format=gray[out]'
    )
    try:
        result = run_background(
            [
                find_ffmpeg(),
                '-nostdin',
                '-loglevel',
                'error',
                '-y',
                '-i',
                str(image),
                '-filter_complex',
                filters,
                '-map',
                '[out]',
                '-frames:v',
                '1',
                str(normal),
            ],
            capture_output=True,
            timeout=20,
        )
    except Exception:
        return ''
    if result.returncode != 0 or not normal.exists():
        return ''

    try:
        invert_result = run_background(
            [
                find_ffmpeg(),
                '-nostdin',
                '-loglevel',
                'error',
                '-y',
                '-i',
                str(normal),
                '-vf',
                'negate',
                '-frames:v',
                '1',
                str(inverted),
            ],
            capture_output=True,
            timeout=15,
        )
        if invert_result.returncode != 0:
            inverted = pathlib.Path('__missing__')
    except Exception:
        inverted = pathlib.Path('__missing__')

    parts: list[str] = []
    for candidate in (normal, inverted):
        if not candidate.exists():
            continue
        for psm in (11, 6):
            text = _ocr_fast(candidate, psm)
            if not text:
                continue
            parts.append(text)
            if dates_in_text(text, BAGHDAD_OFFSET):
                return ' '.join(parts)
    return ' '.join(parts)


def verify_transport_contradiction(
    path: pathlib.Path,
    start: datetime,
    duration_seconds: float,
) -> dict:
    """Bounded two-frame OSD guard used only with strict RTSP clock proof.

    A consistent visible clock mismatch vetoes transport approval. A matching
    OSD is additional confirmation. If the OSD is absent or unreadable the
    result stays ``unknown``; the caller may approve only when its independent
    RTSP PLAY absolute-clock attestation is already fully verified.
    """
    base = {
        'status': 'unknown',
        'method': 'osd_ocr_fast_guard',
        'reason': 'clock_reading_unavailable',
        'samples_read': 0,
        'tolerance_seconds': 5,
    }
    try:
        duration = max(1.0, float(duration_seconds))
        second_sample = min(7.0, max(3.0, duration / 4.0))
        if second_sample >= duration:
            second_sample = max(1.0, duration - 1.0)
        positions = list(dict.fromkeys((0.0, round(second_sample, 3))))
        readings: list[tuple[float, str]] = []
        with tempfile.TemporaryDirectory(prefix='zhirox-fast-clock-', dir=str(path.parent)) as folder:
            workspace = pathlib.Path(folder)
            for index, second in enumerate(positions):
                image = workspace / f'sample-{index}.png'
                if _extract_sample(path, image, second):
                    readings.append(
                        (float(second), _quick_clock_text(image, workspace, f'sample-{index}'))
                    )

        alignment = align_readings(readings, start, BAGHDAD_OFFSET)
        if alignment.get('status') != 'aligned':
            return {
                **base,
                'reason': alignment.get('reason', 'clock_reading_unavailable'),
                'samples_read': alignment.get('samples_read', 0),
                'first_displayed_at': alignment.get('first_displayed_at'),
                'first_sample_offset_seconds': alignment.get('first_sample_offset_seconds'),
                'frames_sampled': len(readings),
            }

        delta = float(alignment.get('offset_seconds') or 0.0)
        return {
            'status': 'matched' if abs(delta) <= 5 else 'mismatch',
            'method': 'osd_ocr_fast_guard',
            'reason': 'visible_clock_matches' if abs(delta) <= 5 else 'visible_clock_mismatch',
            'samples_read': alignment.get('samples_read', 0),
            'tolerance_seconds': 5,
            'offset_seconds': delta,
            'first_displayed_at': alignment.get('first_displayed_at'),
            'expected_first_at': alignment.get('expected_first_at'),
            'frames_sampled': len(readings),
        }
    except Exception:
        return base
