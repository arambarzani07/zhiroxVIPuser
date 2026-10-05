#!/usr/bin/env python3
"""ZHIROX Camera Bridge for O-KAM/A11 cameras.

Runs an authenticated HTTP bridge in the cloud and opens the camera through
O-KAM's native P2P transport. The camera can therefore feed ZHIROX without a
local PC or Hikvision NVR.
"""

from __future__ import annotations

import asyncio
import os
import signal
import subprocess
import threading
import time
from pathlib import Path

import imageio_ffmpeg
from okam_native.bridge import CameraBridge, QuietThreadingHTTPServer, make_handler
from okam_native.p2p import (
    P2PError,
    get_service_parameter,
    open_stream_process,
    resolve_client_id,
    run_stream_probe,
)
from okam_native.session import NativeStreamSession
from okam_native.wakeup import WakeError, load_wake_credentials, wake_camera

ROOT = Path(__file__).resolve().parent
HELPER = ROOT / "okam-amd64-connect"
WAKE_SOURCE = ROOT / "vendor" / "device_wakeup_server.dart"
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()

CAMERA_UID = os.environ.get("OKAM_CAMERA_UID", "").strip()
CAMERA_PASSWORD = os.environ.get("OKAM_CAMERA_PASSWORD", "888888")
CAMERA_ID = os.environ.get("OKAM_CAMERA_ID", "a11-cashier").strip() or "a11-cashier"
CAMERA_NAME = os.environ.get("OKAM_CAMERA_NAME", "A11 Cashier Camera").strip() or "A11 Cashier Camera"
API_TOKEN = os.environ.get("BRIDGE_API_TOKEN", "")
IDLE_TIMEOUT = int(os.environ.get("IDLE_TIMEOUT_SECONDS", "300"))
PORT = int(os.environ.get("PORT", "8099"))
PROBE_ON_START = os.environ.get("PROBE_ON_START", "true").lower() in {"1", "true", "yes", "on"}

STATE_LOCK = threading.Lock()
STATE: dict[str, object] = {
    "service": "zhirox-camera-bridge",
    "loader_ready": False,
    "configuration_required": True,
    "camera_ready": False,
    "p2p_ready": False,
    "h264_ready": False,
    "probe_status": "not_started",
    "phase": "starting",
}
BRIDGE: CameraBridge | None = None
SESSION: NativeStreamSession | None = None
CLIENT_ID = ""
SERVICE_PARAMETER = ""
WAKE_CREDENTIALS = None


def set_state(**values: object) -> None:
    with STATE_LOCK:
        STATE.update(values)


def status_provider() -> dict[str, object]:
    with STATE_LOCK:
        payload = dict(STATE)
    session = SESSION
    if session is not None:
        s = session.status()
        payload.update(
            stream_running=s.running,
            stream_viewers=s.viewers,
            stream_media_ready=s.media_ready,
            stream_error=s.last_error,
            clean_disconnect=s.clean_disconnect,
            idle_timeout_seconds=int(session.idle_timeout),
        )
    return payload


def bridge_provider() -> CameraBridge | None:
    return BRIDGE


def _wake() -> None:
    if WAKE_CREDENTIALS is None:
        return
    try:
        result = asyncio.run(wake_camera(CAMERA_UID, WAKE_CREDENTIALS, timeout=12.0))
        set_state(
            wake_requested=result.requested,
            wake_responsive_servers=result.responsive_servers,
        )
    except WakeError:
        set_state(wake_requested=False)


def start_stream() -> subprocess.Popen[bytes]:
    set_state(phase="waking_camera")
    _wake()
    set_state(phase="starting_p2p_stream")
    return open_stream_process(
        str(HELPER),
        "/dev/null",
        CLIENT_ID,
        SERVICE_PARAMETER,
        CAMERA_PASSWORD,
        environment=os.environ.copy(),
    )


def probe_camera() -> None:
    """Verify that the cloud host can authenticate and receive native H.264."""
    set_state(probe_status="running", phase="probing_camera")
    last_error = ""
    for attempt in range(1, 4):
        try:
            _wake()
            result = run_stream_probe(
                str(HELPER),
                "/dev/null",
                CLIENT_ID,
                SERVICE_PARAMETER,
                CAMERA_PASSWORD,
                environment=os.environ.copy(),
                timeout=90.0,
            )
            set_state(
                probe_attempt=attempt,
                connect_state=result.connect_state,
                camera_authenticated=result.authenticated,
                login_result=result.login_result,
                h264_frames=result.h264_frames,
                h264_bytes=result.h264_bytes,
                h265_frames=result.h265_frames,
                keyframe_seen=result.keyframe_seen,
            )
            if result.connected and result.authenticated and result.h264_received:
                set_state(
                    p2p_ready=True,
                    h264_ready=True,
                    probe_status="ok",
                    phase="bridge_ready",
                )
                print(
                    "camera_probe_ok=true "
                    f"attempt={attempt} frames={result.h264_frames} bytes={result.h264_bytes}",
                    flush=True,
                )
                return
            last_error = "camera_probe_no_h264"
        except P2PError as error:
            last_error = type(error).__name__
        except Exception as error:  # startup diagnostics only; never log secrets
            last_error = type(error).__name__
        if attempt < 3:
            time.sleep(5)
    set_state(
        probe_status="failed",
        probe_error=last_error or "camera_probe_failed",
        phase="bridge_ready_probe_failed",
    )
    print(f"camera_probe_ok=false error={last_error or 'camera_probe_failed'}", flush=True)


def configure() -> None:
    global BRIDGE, SESSION, CLIENT_ID, SERVICE_PARAMETER, WAKE_CREDENTIALS

    if not CAMERA_UID:
        raise RuntimeError("OKAM_CAMERA_UID is required")
    if not API_TOKEN or len(API_TOKEN) < 16:
        raise RuntimeError("BRIDGE_API_TOKEN must contain at least 16 characters")
    if not HELPER.is_file():
        raise RuntimeError("O-KAM amd64 helper is missing")

    set_state(phase="resolving_camera")
    CLIENT_ID = resolve_client_id(CAMERA_UID)
    SERVICE_PARAMETER = get_service_parameter(CLIENT_ID)
    if WAKE_SOURCE.is_file():
        WAKE_CREDENTIALS = load_wake_credentials(WAKE_SOURCE)

    SESSION = NativeStreamSession(start_stream, idle_timeout=float(IDLE_TIMEOUT))
    BRIDGE = CameraBridge(
        camera_id=CAMERA_ID,
        camera_name=CAMERA_NAME,
        api_token=API_TOKEN,
        session=SESSION,
        ffmpeg=FFMPEG,
    )
    set_state(
        loader_ready=True,
        configuration_required=False,
        camera_ready=True,
        phase="bridge_ready",
        camera_id=CAMERA_ID,
    )
    print("bridge_ready=true camera_count=1", flush=True)


def main() -> int:
    server = QuietThreadingHTTPServer(("0.0.0.0", PORT), make_handler(status_provider, bridge_provider))
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    print(f"http_listening=true port={PORT}", flush=True)

    try:
        configure()
    except Exception as error:
        set_state(
            phase="startup_error",
            startup_error=type(error).__name__,
            configuration_required=True,
        )
        print(f"bridge_ready=false error={type(error).__name__}", flush=True)

    if PROBE_ON_START and BRIDGE is not None:
        threading.Thread(target=probe_camera, daemon=True).start()

    stop = threading.Event()

    def request_stop(_signum: int, _frame: object) -> None:
        stop.set()

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    stop.wait()

    if SESSION is not None:
        SESSION.close()
    server.shutdown()
    server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
