"""Read and align the recorder's displayed clock without changing media content.

Windows bundles Tesseract OCR. Missing OCR, hidden OSD, ambiguous dates or
inconsistent readings produce unknown, never a fabricated time correction.
"""
from __future__ import annotations
import pathlib
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from common import find_ffmpeg, run_background

BAGHDAD_OFFSET = timezone(timedelta(hours=3))


def ocr_image(path: pathlib.Path, psm: int = 6) -> str:
    root = pathlib.Path(getattr(sys, '_MEIPASS', pathlib.Path(__file__).resolve().parent))
    bundled = root / 'ocr' / 'tesseract.exe'
    command = [str(bundled) if bundled.exists() else 'tesseract', str(path), 'stdout', '--psm', str(psm), '-l', 'eng']
    if bundled.exists():
        command += ['--tessdata-dir', str(root / 'ocr' / 'tessdata')]
    result = run_background(command, capture_output=True, timeout=25,
                            creationflags=0x08000000 if sys.platform == 'win32' else 0)
    if result.returncode:
        raise RuntimeError('ocr_unavailable')
    return result.stdout.decode('utf-8', errors='replace')


def dates_in_text(text: str, offset, order: str | None = None) -> list[tuple[str, datetime]]:
    # No substitution of letters for digits: a partial OCR result must not verify.
    text = ' '.join(text.split()).translate(str.maketrans({c:'-' for c in '‐‑‒–—−'})).replace('：', ':')
    matches = re.findall(r'(\d{2,4})\s*[-/]\s*(\d{1,2})\s*[-/]\s*(\d{2,4}).{0,24}?(\d{1,2})\s*:\s*(\d{2})\s*:\s*(\d{2})', text)
    results = []
    for a,b,c,h,m,s in matches:
        # Hikvision's MM-DD-YY / DD-MM-YY overlays use a two-digit year.
        # Our supported footage is 2020-2100, so YY means 20YY; never use a
        # moving-century pivot or infer missing/illegible digits.
        last_year = int(c) + (2000 if len(c) == 2 else 0)
        options = [('YMD', int(a),int(b),int(c))] if len(a)==4 else [('MDY',last_year,int(a),int(b)),('DMY',last_year,int(b),int(a))]
        for fmt,y,month,day in options:
            if order and fmt != order:
                continue
            try:
                stamp = datetime(y,month,day,int(h),int(m),int(s),tzinfo=offset)
                if 2020 <= y <= 2100:
                    results.append((fmt,stamp))
            except ValueError:
                pass
    return results


def read_image_clock(image: pathlib.Path, workspace: pathlib.Path) -> str:
    parts = []
    # Read both common Hikvision OSD locations. The top crop covers the clock in
    # Kani Chnar Camera 10 while the bottom crop keeps this generic for other IPCs.
    for position in ['0', 'ih-oh']:
        target = workspace / ('osd-top.png' if position=='0' else 'osd-bottom.png')
        r = run_background([find_ffmpeg(),'-nostdin','-loglevel','error','-y','-i',str(image),
            '-vf',f'crop=iw:ih*0.22:0:{position},scale=2400:-1','-frames:v','1',str(target)],capture_output=True,timeout=20)
        if r.returncode == 0:
            parts.append(ocr_image(target))
    if dates_in_text(' '.join(parts), BAGHDAD_OFFSET):
        return ' '.join(parts)
    # A full-width crop can shrink small OSD letters and includes shelf labels.
    # Retry the clock corner at higher resolution using sparse-text segmentation.
    # Inversion helps white overlay text; both variants retain the original pixels.
    for inverted in (False, True):
        target = workspace / ('osd-corner-inverted.png' if inverted else 'osd-corner.png')
        filters = 'crop=iw*0.60:ih*0.18:0:0,scale=3200:-1,format=gray'
        if inverted:
            filters += ',negate'
        r = run_background([find_ffmpeg(), '-nostdin', '-loglevel', 'error', '-y',
            '-i', str(image), '-vf', filters, '-frames:v', '1', str(target)],
            capture_output=True, timeout=20)
        if r.returncode == 0:
            try:
                text = ocr_image(target, psm=11)
                parts.append(text)
                if dates_in_text(text, BAGHDAD_OFFSET):
                    break
            except Exception:
                pass
    return ' '.join(parts)


def _pick_clock(text: str, expected: datetime, offset, order: str | None = None):
    """Pick an unambiguous OSD timestamp closest to the expected wall-clock time."""
    candidates = dates_in_text(text, offset, order)
    if not candidates:
        return None
    expected_local = expected.astimezone(offset)
    unique: dict[tuple[str, datetime], float] = {}
    for fmt, stamp in candidates:
        unique[(fmt, stamp)] = abs((stamp - expected_local).total_seconds())
    ranked = sorted(unique.items(), key=lambda item: item[1])
    if not ranked or ranked[0][1] > 36 * 3600:
        return None
    # If two interpretations are practically equally close, do not guess.
    if len(ranked) > 1 and abs(ranked[1][1] - ranked[0][1]) < 120:
        first = ranked[0][0]
        second = ranked[1][0]
        if first[1] != second[1]:
            return None
    (fmt, stamp), _ = ranked[0]
    return fmt, stamp


def align_readings(readings: list[tuple[float,str]], start: datetime, offset=BAGHDAD_OFFSET) -> dict:
    """Infer the real first-frame wall clock from OSD samples.

    This deliberately does not trust ISAPI segment start metadata. Old Hikvision
    firmware can return a file whose actual first frame is hours earlier than the
    metadata attached to its playbackURI.
    """
    parsed = []
    for seconds, text in readings:
        picked = _pick_clock(text, start + timedelta(seconds=seconds), offset)
        if picked is not None:
            parsed.append((float(seconds), picked[0], picked[1]))
    base = {'status':'unknown','method':'osd_ocr_alignment','samples_read':len(parsed),'tolerance_seconds':5}
    if parsed:
        base['first_displayed_at'] = parsed[0][2].isoformat()
        base['first_sample_offset_seconds'] = round((parsed[0][2] - start.astimezone(offset)).total_seconds() - parsed[0][0], 1)
    if len(parsed) < 2:
        return {**base,'reason':'insufficient_clock_readings'}
    orders = {fmt for _,fmt,_ in parsed}
    if len(orders) != 1:
        return {**base,'reason':'ambiguous_date_order'}
    bases = [stamp - timedelta(seconds=seconds) for seconds,_,stamp in parsed]
    spread = (max(bases) - min(bases)).total_seconds()
    if spread > 2.0 or parsed[-1][0] - parsed[0][0] < 1:
        return {**base,'reason':'inconsistent_clock_readings'}
    epoch = sum(stamp.timestamp() for stamp in bases) / len(bases)
    media_start = datetime.fromtimestamp(epoch, tz=offset)
    expected_local = start.astimezone(offset)
    delta = round((media_start - expected_local).total_seconds(), 1)
    return {
        **base,
        'status':'aligned',
        'date_order':next(iter(orders)),
        'media_start_at':media_start.astimezone(timezone.utc).isoformat(),
        'first_displayed_at':media_start.isoformat(),
        'expected_first_at':expected_local.isoformat(),
        'offset_seconds':delta,
        'spread_seconds':round(spread,1),
    }


def _video_clock_readings(path: pathlib.Path, workspace: pathlib.Path, duration: float) -> list[tuple[float,str]]:
    readings=[]
    positions = [0.0, min(3.0, max(0.0, duration/3)), min(7.0, max(0.0, duration*2/3))]
    for index, second in enumerate(dict.fromkeys(round(x,3) for x in positions)):
        image=workspace/f'sample-{index}.png'
        # Decode from the beginning before discarding up to the sample time.
        # Input seeking on indexless recorder exports can return success with
        # no image, even for -ss 0, or lose the first decoder parameter sets.
        r=run_background([find_ffmpeg(),'-nostdin','-loglevel','error','-y','-i',str(path),'-ss',str(second),'-frames:v','1',str(image)],capture_output=True,timeout=30)
        if r.returncode==0 and image.exists():
            readings.append((float(second),read_image_clock(image,workspace)))
    return readings


def infer_media_start_from_osd(path: pathlib.Path, expected_start: datetime, duration_hint: float = 30.0) -> dict:
    import tempfile
    try:
        with tempfile.TemporaryDirectory(prefix='zhirox-source-osd-',dir=str(path.parent)) as folder:
            workspace=pathlib.Path(folder)
            readings=_video_clock_readings(path,workspace,max(8.0,float(duration_hint)))
            result = align_readings(readings, expected_start, BAGHDAD_OFFSET)
            # Parsed dates are diagnostic clues only. They never bypass the
            # age, ambiguity, advancing-clock or transaction alignment guards.
            observed = []
            for _,text in readings:
                candidates = dates_in_text(text, BAGHDAD_OFFSET)
                if candidates:
                    closest = min((stamp for _,stamp in candidates), key=lambda stamp: abs((stamp - expected_start.astimezone(BAGHDAD_OFFSET)).total_seconds()))
                    observed.append(closest.isoformat())
            result['clock_candidates'] = list(dict.fromkeys(observed))[:3]
            result['frames_extracted'] = sum(1 for _ in workspace.glob('sample-*.png'))
            result['source_bytes'] = path.stat().st_size
            try:
                probe = run_background([find_ffmpeg(), '-nostdin', '-hide_banner', '-loglevel', 'info', '-i', str(path), '-frames:v', '1', '-an', '-f', 'null', '-'], capture_output=True, timeout=15)
                text = (probe.stderr or b'').decode('utf-8', errors='replace')
                result['source_codecs'] = sorted(set(re.findall(r'Video: (h264|hevc|mpeg4)\b', text)))
                result['source_probe_ok'] = probe.returncode == 0
            except Exception:
                result['source_probe_ok'] = False
            return result
    except Exception:
        return {'status':'unknown','method':'osd_ocr_alignment','reason':'clock_reading_unavailable'}


def clock_context(hik, channel: int, workspace: pathlib.Path):
    import xml.etree.ElementTree as ET
    response = hik.session.get(f'{hik.host}/ISAPI/System/time', timeout=15)
    response.raise_for_status()
    root = ET.fromstring(response.text)
    values = {n.tag.split('}')[-1]:n.text for n in root.iter()}
    now = datetime.fromisoformat(str(values.get('localTime') or '').replace('Z','+00:00'))
    if now.tzinfo is None:
        raise RuntimeError('recorder_timezone_unknown')
    picture = hik.session.get(f'{hik.host}/ISAPI/Streaming/channels/{channel*100+1}/picture',timeout=15)
    picture.raise_for_status()
    if len(picture.content) > 10*1024*1024:
        raise RuntimeError('snapshot_too_large')
    path = workspace/'live-clock.jpg'
    path.write_bytes(picture.content)
    reads = dates_in_text(read_image_clock(path,workspace),now.tzinfo)
    orders = {order for order,stamp in reads if abs((stamp-now).total_seconds()) <= 60}
    if len(orders) != 1:
        raise RuntimeError('recorder_date_format_unverified')
    return now.tzinfo, orders.pop()


def compare_readings(readings: list[tuple[float,str]], start: datetime, offset, order: str) -> dict:
    parsed=[]
    for seconds,text in readings:
        candidates = dates_in_text(text,offset,order)
        stamps={stamp for _,stamp in candidates}
        if len(stamps)==1:
            parsed.append((seconds,stamps.pop()))
    base={'status':'unknown','method':'osd_ocr','date_order':order,'samples_read':len(parsed),'tolerance_seconds':5}
    if len(parsed)<2:
        return {**base,'reason':'insufficient_clock_readings'}
    deltas=[(stamp-start.astimezone(offset)).total_seconds()-seconds for seconds,stamp in parsed]
    if max(deltas)-min(deltas)>2 or parsed[-1][0]-parsed[0][0]<1:
        return {**base,'reason':'inconsistent_clock_readings'}
    delta=round(sum(deltas)/len(deltas),1)
    return {**base,'status':'matched' if abs(delta)<=5 else 'mismatch',
            'offset_seconds':delta,'first_displayed_at':parsed[0][1].isoformat(),
            'expected_first_at':start.astimezone(offset).isoformat()}


def verify_clip_time(hik, channel: int, path: pathlib.Path, start: datetime, duration: float) -> dict:
    # Verify directly against the requested transaction window. This avoids relying
    # on the recorder's own segment metadata or live clock context, both of which can
    # be wrong on older firmware.
    alignment = infer_media_start_from_osd(path, start, duration)
    if alignment.get('status') != 'aligned':
        return {'status':'unknown','method':'osd_ocr','reason':alignment.get('reason','clock_reading_unavailable')}
    delta = float(alignment.get('offset_seconds') or 0.0)
    return {
        'status':'matched' if abs(delta)<=5 else 'mismatch',
        'method':'osd_ocr',
        'date_order':alignment.get('date_order'),
        'samples_read':alignment.get('samples_read',0),
        'tolerance_seconds':5,
        'offset_seconds':delta,
        'first_displayed_at':alignment.get('first_displayed_at'),
        'expected_first_at':alignment.get('expected_first_at'),
    }
