from __future__ import annotations

import pathlib
import threading
import time
from datetime import datetime, timezone

import common as gateway_common
from common import (
    CONFIG_PATH,
    bounded_playback_uri,
    TEMP_DIR,
    CloudClient,
    GatewayConfig,
    HikvisionClient,
    log,
    prepare_browser_clip,
    parse_iso,
    sha256_file,
)

# Protocol 1.1 enables DB-backed per-attempt fencing while the shared setup
# helpers remain compatible with already-installed 1.0 gateway packages.
gateway_common.GATEWAY_VERSION = "1.1.0"

POLL_SECONDS = 5
HEARTBEAT_SECONDS = 30


class JobLease:
    def __init__(self, cloud: CloudClient, job_id: str, attempt_token: str):
        self.cloud = cloud
        self.job_id = job_id
        self.attempt_token = attempt_token
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def __enter__(self) -> "JobLease":
        if not self.attempt_token:
            return self
        # Refresh immediately, then continuously while NVR download/trim/upload runs.
        self._heartbeat()
        self._thread = threading.Thread(
            target=self._run,
            name=f"zhirox-hikvision-lease-{self.job_id[:8]}",
            daemon=True,
        )
        self._thread.start()
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=2)

    def _heartbeat(self) -> None:
        try:
            self.cloud.call(
                "heartbeat_job",
                job_id=self.job_id,
                attempt_token=self.attempt_token,
            )
        except Exception as exc:
            # A temporary cloud failure must not kill local capture. If the lease
            # actually became stale/reclaimed, the fenced completion will be rejected.
            log(
                f"job={self.job_id} heartbeat_error="
                f"{type(exc).__name__}:{str(exc)[:240]}"
            )

    def _run(self) -> None:
        while not self._stop.wait(HEARTBEAT_SECONDS):
            self._heartbeat()


def _attempt_args(attempt_token: str) -> dict[str, str]:
    return {"attempt_token": attempt_token} if attempt_token else {}


def process_job(
    cloud: CloudClient,
    heartbeat_cloud: CloudClient,
    hik: HikvisionClient,
    job: dict,
) -> None:
    job_id = str(job["job_id"])
    attempt_token = str(job.get("attempt_token") or "").strip()
    attempt_generation = int(job.get("attempt_generation") or 0)
    transaction_at = parse_iso(str(job["transaction_at"]))
    clip_start = parse_iso(str(job["clip_start_at"]))
    clip_end = parse_iso(str(job["clip_end_at"]))
    channel_id = int(job["channel_id"])
    attempt_args = _attempt_args(attempt_token)

    TEMP_DIR.mkdir(parents=True, exist_ok=True)
    raw_path = TEMP_DIR / f"{job_id}.raw.mp4"
    exact_path = TEMP_DIR / f"{job_id}.mp4"

    with JobLease(heartbeat_cloud, job_id, attempt_token):
        try:
            # v2 claims only after clip_end+3s, but keep this guard for clock skew and
            # legacy jobs. The heartbeat remains active for the entire wait.
            wait_seconds = (
                clip_end.astimezone(timezone.utc) - datetime.now(timezone.utc)
            ).total_seconds() + 3
            if wait_seconds > 0:
                time.sleep(wait_seconds)

            search = hik.search_recording(channel_id, clip_start, clip_end, transaction_at)
            if not search.get("found"):
                age = (
                    datetime.now(timezone.utc) - transaction_at.astimezone(timezone.utc)
                ).total_seconds()
                cloud.call(
                    "fail",
                    job_id=job_id,
                    error="recording_not_found",
                    missing=age > 300,
                    **attempt_args,
                )
                log(
                    f"job={job_id} attempt={attempt_generation} "
                    f"recording not found age={int(age)}s"
                )
                return

            playback_uri = bounded_playback_uri(str(search["playback_uri"]),
                                                clip_start, clip_end, channel_id * 100 + 1)
            log(f"job={job_id} build=time-window-3 download_mode=time "
                f"requested_start={clip_start.isoformat()} requested_end={clip_end.isoformat()}")
            hik.download_recording(playback_uri, raw_path)
            if not raw_path.exists() or raw_path.stat().st_size <= 0:
                raise RuntimeError("empty_download")

            requested_duration = max(1, int((clip_end - clip_start).total_seconds()))
            media = prepare_browser_clip(
                raw_path,
                exact_path,
                clip_start,
                clip_start.replace(microsecond=0).isoformat(),
                requested_duration,
            )
            upload_path = exact_path

            prepared = cloud.call("prepare_upload", job_id=job_id, **attempt_args)
            signed_url = str(prepared.get("signed_upload_url") or "")
            object_path = str(prepared.get("object_path") or "")
            if not signed_url or not object_path:
                raise RuntimeError("missing_signed_upload")

            cloud.upload(signed_url, upload_path)
            digest = sha256_file(upload_path)
            size = upload_path.stat().st_size

            cloud.call(
                "complete",
                job_id=job_id,
                object_path=object_path,
                content_sha256=digest,
                byte_size=size,
                duration_seconds=media["duration_seconds"],
                playback_metadata={
                    "provider": "hikvision_isapi",
                    "gateway_build": "time-window-3",
                    "download_mode": "time",
                    "download_start": clip_start.replace(microsecond=0).isoformat(),
                    "media_time_verified": False,
                    "track_id": search.get("track_id"),
                    "segment_start": search.get("segment_start"),
                    "segment_end": search.get("segment_end"),
                    "matches": search.get("matches", 0),
                    **media,
                    "attempt_generation": attempt_generation,
                    "attempt_fenced": bool(attempt_token),
                    "requested_start": clip_start.astimezone(timezone.utc).isoformat(),
                    "requested_end": clip_end.astimezone(timezone.utc).isoformat(),
                },
                **attempt_args,
            )
            log(
                f"job={job_id} attempt={attempt_generation} ready "
                f"channel={channel_id} bytes={size} codec=h264 decode_verified=True"
            )
        except Exception as exc:
            message = f"{type(exc).__name__}:{exc}"[:900]
            try:
                cloud.call(
                    "fail",
                    job_id=job_id,
                    error=message,
                    missing=False,
                    **attempt_args,
                )
            except Exception as cloud_exc:
                log(
                    f"job={job_id} attempt={attempt_generation} "
                    f"fail-report-error={type(cloud_exc).__name__}"
                )
            log(f"job={job_id} attempt={attempt_generation} error={message}")
        finally:
            for path in (raw_path, exact_path):
                try:
                    if path.exists():
                        path.unlink()
                except Exception:
                    pass


def run() -> None:
    if not CONFIG_PATH.exists():
        log("configuration missing; run zhirox-hikvision-setup.exe")
        time.sleep(30)
        return

    cfg = GatewayConfig.load()
    cloud = CloudClient(cfg)
    # Keep job-heartbeat traffic isolated from the foreground request session.
    heartbeat_cloud = CloudClient(cfg)
    hik = HikvisionClient(cfg)

    # Fail fast on a bad local password/IP while never logging credentials.
    hik.device_info()
    ping = cloud.call("ping")
    log(
        "gateway started; NVR and cloud authentication healthy "
        f"attempt_fencing={bool((ping.get('capabilities') or {}).get('attempt_fencing'))}"
    )

    while True:
        try:
            response = cloud.call("claim")
            job = response.get("job")
            if not job:
                time.sleep(POLL_SECONDS)
                continue
            process_job(cloud, heartbeat_cloud, hik, job)
        except Exception as exc:
            log(f"loop_error={type(exc).__name__}:{str(exc)[:500]}")
            time.sleep(15)


def main() -> None:
    while True:
        try:
            run()
        except Exception as exc:
            log(f"startup_error={type(exc).__name__}:{str(exc)[:500]}")
            time.sleep(30)


if __name__ == "__main__":
    main()
