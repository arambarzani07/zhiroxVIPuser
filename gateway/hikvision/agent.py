from __future__ import annotations

import os
import pathlib
import time
from datetime import datetime, timezone

from common import (
    CONFIG_PATH,
    TEMP_DIR,
    CloudClient,
    GatewayConfig,
    HikvisionClient,
    log,
    maybe_trim_with_ffmpeg,
    parse_iso,
    sha256_file,
)

POLL_SECONDS = 5


def process_job(cloud: CloudClient, hik: HikvisionClient, job: dict) -> None:
    job_id = str(job["job_id"])
    transaction_at = parse_iso(str(job["transaction_at"]))
    clip_start = parse_iso(str(job["clip_start_at"]))
    clip_end = parse_iso(str(job["clip_end_at"]))
    channel_id = int(job["channel_id"])

    # Allow the recorder a small amount of time to finalize the post-transaction recording.
    wait_seconds = (clip_end.astimezone(timezone.utc) - datetime.now(timezone.utc)).total_seconds() + 3
    if wait_seconds > 0:
        time.sleep(min(wait_seconds, 90))

    TEMP_DIR.mkdir(parents=True, exist_ok=True)
    raw_path = TEMP_DIR / f"{job_id}.raw.mp4"
    exact_path = TEMP_DIR / f"{job_id}.mp4"

    try:
        search = hik.search_recording(channel_id, clip_start, clip_end, transaction_at)
        if not search.get("found"):
            age = (datetime.now(timezone.utc) - transaction_at.astimezone(timezone.utc)).total_seconds()
            cloud.call(
                "fail",
                job_id=job_id,
                error="recording_not_found",
                missing=age > 300,
            )
            log(f"job={job_id} recording not found age={int(age)}s")
            return

        playback_uri = str(search["playback_uri"])
        hik.download_recording(playback_uri, raw_path)
        if not raw_path.exists() or raw_path.stat().st_size <= 0:
            raise RuntimeError("empty_download")

        requested_duration = max(1, int((clip_end - clip_start).total_seconds()))
        trimmed = maybe_trim_with_ffmpeg(
            raw_path,
            exact_path,
            clip_start,
            search.get("segment_start"),
            requested_duration,
        )
        upload_path = exact_path if trimmed else raw_path

        prepared = cloud.call("prepare_upload", job_id=job_id)
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
            duration_seconds=requested_duration if trimmed else None,
            playback_metadata={
                "provider": "hikvision_isapi",
                "track_id": search.get("track_id"),
                "segment_start": search.get("segment_start"),
                "segment_end": search.get("segment_end"),
                "matches": search.get("matches", 0),
                "exact_trim": trimmed,
                "requested_start": clip_start.astimezone(timezone.utc).isoformat(),
                "requested_end": clip_end.astimezone(timezone.utc).isoformat(),
            },
        )
        log(f"job={job_id} ready channel={channel_id} bytes={size} exact_trim={trimmed}")
    except Exception as exc:
        message = f"{type(exc).__name__}:{exc}"[:900]
        try:
            cloud.call("fail", job_id=job_id, error=message, missing=False)
        except Exception as cloud_exc:
            log(f"job={job_id} fail-report-error={type(cloud_exc).__name__}")
        log(f"job={job_id} error={message}")
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
    hik = HikvisionClient(cfg)

    # Fail fast on a bad local password/IP while never logging credentials.
    hik.device_info()
    cloud.call("ping")
    log("gateway started; NVR and cloud authentication healthy")

    while True:
        try:
            response = cloud.call("claim")
            job = response.get("job")
            if not job:
                time.sleep(POLL_SECONDS)
                continue
            process_job(cloud, hik, job)
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
