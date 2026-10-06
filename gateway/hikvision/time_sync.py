from __future__ import annotations

import argparse
import pathlib
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone

from common import GatewayConfig, HikvisionClient, local_name

BAGHDAD_TZ = timezone(timedelta(hours=3))
BAGHDAD_POSIX_TZ = "AST-3:00:00"


def _find(root: ET.Element, name: str) -> ET.Element | None:
    for node in root.iter():
        if local_name(node.tag) == name:
            return node
    return None


def _response_ok(response) -> bool:
    if response.status_code >= 300:
        return False
    try:
        root = ET.fromstring(response.content)
    except ET.ParseError:
        return True
    code = _find(root, "statusCode")
    text = (code.text or "").strip() if code is not None else ""
    return text in {"", "0", "1"}


def sync_nvr_clock(hik: HikvisionClient) -> dict:
    endpoint = f"{hik.host}/ISAPI/System/time"
    current = hik.session.get(endpoint, timeout=15)
    current.raise_for_status()
    root = ET.fromstring(current.content)

    mode = _find(root, "timeMode")
    local_time = _find(root, "localTime")
    zone = _find(root, "timeZone")
    ns = root.tag.split("}")[0].lstrip("{") if "}" in root.tag else None
    def q(tag: str) -> str:
        return f"{{{ns}}}{tag}" if ns else tag

    if mode is None:
        mode = ET.SubElement(root, q("timeMode"))
    if local_time is None:
        local_time = ET.SubElement(root, q("localTime"))
    if zone is None:
        zone = ET.SubElement(root, q("timeZone"))

    now = datetime.now(BAGHDAD_TZ).replace(microsecond=0)
    mode.text = "manual"
    local_time.text = now.isoformat()
    zone.text = BAGHDAD_POSIX_TZ

    payload = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    saved = hik.session.put(
        endpoint,
        data=payload,
        headers={"Content-Type": "application/xml"},
        timeout=20,
    )
    if not _response_ok(saved):
        raise RuntimeError(f"nvr_time_sync_http_{saved.status_code}")

    time.sleep(1)
    verify = hik.session.get(endpoint, timeout=15)
    verify.raise_for_status()
    verify_root = ET.fromstring(verify.content)
    actual_node = _find(verify_root, "localTime")
    actual_text = (actual_node.text or "").strip() if actual_node is not None else ""
    if not actual_text:
        raise RuntimeError("nvr_time_verify_missing")
    actual = datetime.fromisoformat(actual_text.replace("Z", "+00:00"))
    # Older Hikvision firmware can report a misleading offset while the wall clock is right.
    drift = abs((actual.replace(tzinfo=None) - datetime.now(BAGHDAD_TZ).replace(tzinfo=None)).total_seconds())
    if drift > 15:
        raise RuntimeError(f"nvr_time_verify_drift_{int(drift)}s")
    return {"status": "synced", "drift_seconds": round(drift, 1), "time_zone": BAGHDAD_POSIX_TZ}


def enable_ipc_time_sync(hik: HikvisionClient, channel: int) -> dict:
    endpoint = f"{hik.host}/ISAPI/ContentMgmt/InputProxy/channels/{channel}"
    response = hik.session.get(endpoint, timeout=20)
    response.raise_for_status()
    root = ET.fromstring(response.content)
    timing = _find(root, "enableTiming")
    if timing is None:
        return {"status": "unsupported"}

    was_enabled = (timing.text or "").strip().lower() == "true"
    timing.text = "true"
    payload = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    saved = hik.session.put(
        endpoint,
        data=payload,
        headers={"Content-Type": "application/xml"},
        timeout=30,
    )
    if not _response_ok(saved):
        raise RuntimeError(f"ipc_time_sync_http_{saved.status_code}")

    time.sleep(2)
    verify = hik.session.get(endpoint, timeout=20)
    verify.raise_for_status()
    verify_root = ET.fromstring(verify.content)
    verify_timing = _find(verify_root, "enableTiming")
    enabled = verify_timing is not None and (verify_timing.text or "").strip().lower() == "true"
    if not enabled:
        raise RuntimeError("ipc_time_sync_not_enabled")
    return {"status": "enabled", "was_enabled": was_enabled}


def verify_live_osd(hik: HikvisionClient, channel: int) -> dict:
    # Optional final visual-clock verification. Failure here does not undo a successful device sync.
    try:
        from osd_time import clock_context
        import tempfile
        with tempfile.TemporaryDirectory(prefix="zhirox-timesync-") as folder:
            offset, order = clock_context(hik, channel, pathlib.Path(folder))
            return {"status": "verified", "date_order": order, "utc_offset": str(offset)}
    except Exception:
        return {"status": "pending_or_unreadable"}


def run(channel: int) -> int:
    cfg = GatewayConfig.load()
    hik = HikvisionClient(cfg)
    hik.device_info()

    print("ZHIROX Hikvision Time Sync")
    print("1/3 Synchronizing NVR clock to Baghdad UTC+03:00...")
    nvr = sync_nvr_clock(hik)
    print(f"NVR clock: OK (drift {nvr['drift_seconds']}s)")

    print(f"2/3 Enabling NVR -> IP Camera time sync for channel {channel}...")
    ipc = enable_ipc_time_sync(hik, channel)
    if ipc["status"] == "unsupported":
        print("IPC time sync: not exposed by this firmware")
    else:
        print("IPC time sync: ON")

    print("3/3 Checking live camera OSD clock...")
    time.sleep(5)
    osd = verify_live_osd(hik, channel)
    if osd["status"] == "verified":
        print("Camera OSD clock: VERIFIED")
    else:
        print("Camera OSD clock: sync enabled; visual verification pending")

    print("Done. Future ZHIROX clips should show the correct camera time.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Synchronize Hikvision NVR and IP camera time for ZHIROX")
    parser.add_argument("--channel", type=int, default=10, help="NVR IP camera channel (default: 10)")
    args = parser.parse_args()
    if args.channel < 1 or args.channel > 64:
        raise SystemExit("invalid channel")
    try:
        return run(args.channel)
    except FileNotFoundError:
        print("Gateway configuration not found. Run the normal ZHIROX Hikvision setup first.")
        return 2
    except Exception as exc:
        # Do not print device responses because they can contain sensitive configuration.
        print(f"Time sync failed: {type(exc).__name__}: {str(exc)[:160]}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
