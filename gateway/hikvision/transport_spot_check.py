from __future__ import annotations

import pathlib
import tempfile
from datetime import datetime, timedelta

from common import find_ffmpeg, run_background
from osd_time import BAGHDAD_OFFSET, _pick_clock, read_image_clock


def _extract_frame(path: pathlib.Path, workspace: pathlib.Path, second: float, index: int) -> pathlib.Path | None:
    image = workspace / f'transport-spot-{index}.png'
    result = run_background(
        [
            find_ffmpeg(), '-nostdin', '-loglevel', 'error', '-y', '-i', str(path),
            '-ss', str(round(max(0.0, float(second)), 3)), '-frames:v', '1', str(image),
        ],
        capture_output=True,
        timeout=30,
    )
    if result.returncode != 0 or not image.exists():
        return None
    return image


def _sample(path: pathlib.Path, workspace: pathlib.Path, start: datetime, second: float, index: int) -> dict:
    image = _extract_frame(path, workspace, second, index)
    if image is None:
        return {'status': 'unknown', 'reason': 'frame_unavailable', 'sample_second': float(second)}
    try:
        text = read_image_clock(image, workspace)
    except Exception:
        return {'status': 'unknown', 'reason': 'ocr_unavailable', 'sample_second': float(second)}
    picked = _pick_clock(text, start + timedelta(seconds=float(second)), BAGHDAD_OFFSET)
    if picked is None:
        return {'status': 'unknown', 'reason': 'clock_not_readable', 'sample_second': float(second)}
    _, stamp = picked
    delta = round(
        (stamp - start.astimezone(BAGHDAD_OFFSET)).total_seconds() - float(second),
        1,
    )
    return {
        'status': 'matched' if abs(delta) <= 5 else 'mismatch',
        'reason': 'spot_clock_match' if abs(delta) <= 5 else 'spot_clock_mismatch_candidate',
        'sample_second': float(second),
        'displayed_at': stamp.isoformat(),
        'offset_seconds': delta,
    }


def verify_transport_spot_check(path: pathlib.Path, start: datetime, duration: float) -> dict:
    """Cheap fail-safe contradiction check for independently transport-verified clips.

    The RTSP PLAY absolute-clock attestation is the primary independent proof. This
    OSD pass is defense in depth: a readable matching first-frame clock agrees
    immediately; a mismatch is rejected only after a second independently decoded
    frame shows the same advancing offset. Missing/hidden OSD stays unknown and can
    never fabricate a time correction.
    """
    try:
        with tempfile.TemporaryDirectory(prefix='zhirox-transport-spot-', dir=str(path.parent)) as folder:
            workspace = pathlib.Path(folder)
            first = _sample(path, workspace, start, 0.0, 0)
            if first.get('status') != 'mismatch':
                return {
                    **first,
                    'method': 'osd_transport_spot_check',
                    'samples_read': 1 if first.get('status') == 'matched' else 0,
                }

            second_at = max(1.0, min(7.0, max(1.0, float(duration) - 3.0)))
            second = _sample(path, workspace, start, second_at, 1)
            if second.get('status') != 'mismatch':
                return {
                    'status': 'unknown',
                    'method': 'osd_transport_spot_check',
                    'reason': 'mismatch_not_confirmed',
                    'samples_read': 1,
                    'first': first,
                    'second': second,
                }

            first_delta = float(first.get('offset_seconds') or 0.0)
            second_delta = float(second.get('offset_seconds') or 0.0)
            if abs(first_delta - second_delta) > 2.0:
                return {
                    'status': 'unknown',
                    'method': 'osd_transport_spot_check',
                    'reason': 'mismatch_inconsistent',
                    'samples_read': 2,
                    'first': first,
                    'second': second,
                }

            return {
                'status': 'mismatch',
                'method': 'osd_transport_spot_check',
                'reason': 'confirmed_osd_clock_mismatch',
                'samples_read': 2,
                'offset_seconds': round((first_delta + second_delta) / 2.0, 1),
                'first': first,
                'second': second,
            }
    except Exception:
        return {
            'status': 'unknown',
            'method': 'osd_transport_spot_check',
            'reason': 'spot_check_unavailable',
            'samples_read': 0,
        }
