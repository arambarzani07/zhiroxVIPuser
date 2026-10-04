"""Read-only NVR preflight; optional recording download stays on this PC."""
from __future__ import annotations

import argparse
import json
import pathlib
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone

import requests

from common import GatewayConfig, HikvisionClient, local_name, parse_iso, sha256_file
from setup import ask_secret


def diagnose(hik: HikvisionClient, channel: int, at: datetime,
             output: pathlib.Path | None = None) -> dict:
    if channel < 1 or channel > 256:
        raise ValueError("channel_out_of_range")
    if at.tzinfo is None:
        raise ValueError("timestamp_requires_timezone")
    root = ET.fromstring(hik.device_info())
    fields = {local_name(node.tag): (node.text or '').strip() for node in root.iter()}
    if not fields.get('model'):
        raise ValueError("invalid_device_info")
    report = {'model': fields['model'], 'channel': channel,
              'transaction_at': at.isoformat(), 'nvr_access': 'ok'}
    # Clock inspection is GET-only. A bad clock is reported, never adjusted here.
    try:
        response = hik.session.get(f'{hik.host}/ISAPI/System/time', timeout=15)
        response.raise_for_status()
        clock = ET.fromstring(response.content)
        values = {local_name(n.tag): (n.text or '').strip() for n in clock.iter()}
        stamp = values.get('localTime') or values.get('time')
        device_time = datetime.fromisoformat((stamp or '').replace('Z', '+00:00'))
        if device_time.tzinfo is None:
            raise ValueError('clock_timezone_unknown')
        skew = round((device_time - datetime.now(timezone.utc)).total_seconds())
        report['clock_skew_seconds'] = skew
        report['clock_status'] = 'ok' if abs(skew) <= 60 else 'check_nvr_clock'
    except (requests.RequestException, ValueError, ET.ParseError):
        report['clock_status'] = 'could_not_verify'

    match = hik.search_recording(channel, at - timedelta(seconds=15),
                                 at + timedelta(seconds=30), at)
    if not match.get('found'):
        report['recording_status'] = 'not_found'
        return report
    # A nearby recording alone does not prove footage exists at the chosen time.
    try:
        start = parse_iso(match['segment_start'])
        end = parse_iso(match['segment_end'])
        covers = start <= at <= end
    except (KeyError, TypeError, ValueError):
        covers = False
    report['recording_status'] = 'found_at_requested_time' if covers else 'time_not_verified'
    report['segment_start'] = match.get('segment_start')
    report['segment_end'] = match.get('segment_end')
    report['requested_window_covered'] = covers and (
        start <= at - timedelta(seconds=15) and end >= at + timedelta(seconds=30))
    if output is not None and covers:
        output = output.expanduser().resolve()
        if output.exists():
            raise FileExistsError('output_already_exists')
        output.parent.mkdir(parents=True, exist_ok=True)
        # Reserve exclusively; keep incomplete downloads away from final filenames.
        partial = output.with_name(output.name + '.part')
        with partial.open('xb'):
            pass
        try:
            hik.download_recording(match['playback_uri'], partial)
            if partial.stat().st_size == 0:
                raise ValueError('download_empty')
            report['download_bytes'] = partial.stat().st_size
            report['sha256'] = sha256_file(partial)
            # Hard-link publication never overwrites a file created concurrently.
            output.hardlink_to(partial)
            report['download_status'] = 'saved_locally'
            report['download_path'] = str(output)
            report['download_kind'] = 'nvr_segment_not_exact_trim'
        finally:
            partial.unlink(missing_ok=True)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='192.168.1.2')
    parser.add_argument('--username', default='admin')
    parser.add_argument('--channel', type=int, default=1)
    parser.add_argument('--at', help='Recorded timestamp with offset, e.g. 2026-10-03T17:00:00+03:00')
    parser.add_argument('--download', type=pathlib.Path, help='Save matching NVR segment locally; never uploads')
    args = parser.parse_args()
    if not 1 <= args.channel <= 256:
        parser.error('channel must be between 1 and 256')
    at = datetime.fromisoformat(args.at.replace('Z', '+00:00')) if args.at else datetime.now(timezone.utc) - timedelta(minutes=2)
    if at.tzinfo is None:
        parser.error('--at must include timezone (+03:00 for Baghdad)')
    password = ask_secret('NVR password (typing shows *, local only): ')
    if not password:
        parser.error('NVR password is required')
    hik = HikvisionClient(GatewayConfig(args.host, args.username, password, ''))
    try:
        report = diagnose(hik, args.channel, at, args.download)
    except requests.HTTPError as error:
        status = error.response.status_code if error.response is not None else 0
        print(json.dumps({'status': 'failed', 'error': f'nvr_http_{status}'}))
        return 1
    except Exception as error:
        # Exception strings can contain recorder URLs; never print them.
        print(json.dumps({'status': 'failed', 'error_type': type(error).__name__}))
        return 1
    print(json.dumps(report, indent=2))
    return 0 if report['recording_status'] == 'found_at_requested_time' else 2


if __name__ == '__main__':
    try:
        result = main()
        input('Press Enter to close...')
        raise SystemExit(result)
    except KeyboardInterrupt:
        raise SystemExit(130)
