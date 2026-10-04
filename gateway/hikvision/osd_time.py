"""Read the recorder's displayed clock without changing recorder settings.

Windows uses built-in WinRT OCR. Missing OCR, hidden OSD, ambiguous dates or
inconsistent readings produce unknown, never a fabricated time correction.
"""
from __future__ import annotations
import base64
import json
import pathlib
import re
import subprocess
import sys
from datetime import datetime, timezone
from common import find_ffmpeg

_PS = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime] | Out-Null
[Windows.Storage.Streams.IRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.SoftwareBitmap,Windows.Graphics.Imaging,ContentType=WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrResult,Windows.Foundation,ContentType=WindowsRuntime] | Out-Null
[Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime] | Out-Null
$method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
function Await($operation, $type) {
  $task = $method.MakeGenericMethod($type).Invoke($null, @($operation))
  $task.GetAwaiter().GetResult()
}
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync('__PATH__')) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
try {
  $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new('en-US'))
  if ($null -eq $engine) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
  if ($null -eq $engine) { throw 'ocr_language_unavailable' }
  $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
  @{text=$result.Text} | ConvertTo-Json -Compress
} finally { $stream.Dispose() }
'''


def ocr_image(path: pathlib.Path) -> str:
    if sys.platform == 'win32':
        script = _PS.replace('__PATH__', str(path.resolve()).replace("'", "''"))
        command = ['powershell.exe', '-NoProfile', '-NonInteractive', '-EncodedCommand',
                   base64.b64encode(script.encode('utf-16-le')).decode('ascii')]
        result = subprocess.run(command, capture_output=True, timeout=25, creationflags=0x08000000)
        if result.returncode:
            raise RuntimeError('windows_ocr_unavailable')
        return str(json.loads(result.stdout.decode('utf-8-sig'))['text'])
    result = subprocess.run(['tesseract', str(path), 'stdout', '--psm', '6'], capture_output=True, timeout=25)
    if result.returncode:
        raise RuntimeError('ocr_unavailable')
    return result.stdout.decode('utf-8', errors='replace')


def dates_in_text(text: str, offset, order: str | None = None) -> list[tuple[str, datetime]]:
    # No substitution of letters for digits: a partial OCR result must not verify.
    text = ' '.join(text.split()).translate(str.maketrans({c:'-' for c in '‐‑‒–—−'})).replace('：', ':')
    matches = re.findall(r'(\d{2,4})\s*[-/]\s*(\d{1,2})\s*[-/]\s*(\d{2,4}).{0,24}?(\d{1,2})\s*:\s*(\d{2})\s*:\s*(\d{2})', text)
    results = []
    for a,b,c,h,m,s in matches:
        options = [('YMD', int(a),int(b),int(c))] if len(a)==4 else [('MDY',int(c),int(a),int(b)),('DMY',int(c),int(b),int(a))]
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
    for position in ['0', 'ih-oh']:
        target = workspace / ('osd-top.png' if position=='0' else 'osd-bottom.png')
        r = subprocess.run([find_ffmpeg(),'-nostdin','-loglevel','error','-y','-i',str(image),
            '-vf',f'crop=iw:ih*0.22:0:{position},scale=2400:-1,negate','-frames:v','1',str(target)],capture_output=True,timeout=20)
        if r.returncode == 0:
            parts.append(ocr_image(target))
    return ' '.join(parts)


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
    deltas=[(stamp-start).total_seconds()-seconds for seconds,stamp in parsed]
    # Both the rendered date and time must advance with video playback.
    if max(deltas)-min(deltas)>2 or parsed[-1][0]-parsed[0][0]<1:
        return {**base,'reason':'inconsistent_clock_readings'}
    delta=round(sum(deltas)/len(deltas),1)
    return {**base,'status':'matched' if abs(delta)<=5 else 'mismatch',
            'offset_seconds':delta,'first_displayed_at':parsed[0][1].isoformat(),
            'expected_first_at':start.isoformat()}


def verify_clip_time(hik, channel: int, path: pathlib.Path, start: datetime, duration: float) -> dict:
    import tempfile
    try:
        with tempfile.TemporaryDirectory(prefix='zhirox-osd-',dir=str(path.parent)) as folder:
            workspace=pathlib.Path(folder)
            offset,order=clock_context(hik,channel,workspace)
            readings=[]
            for second in [0.0, min(3.0,duration/3), min(7.0,duration*2/3)]:
                image=workspace/'sample.png'
                r=subprocess.run([find_ffmpeg(),'-nostdin','-loglevel','error','-y','-ss',str(second),'-i',str(path),'-frames:v','1',str(image)],capture_output=True,timeout=20)
                if r.returncode==0:
                    readings.append((second,read_image_clock(image,workspace)))
            return compare_readings(readings,start,offset,order)
    except Exception:
        # Clock OCR must never prevent an otherwise valid clip upload.
        return {'status':'unknown','method':'osd_ocr','reason':'clock_reading_unavailable'}
