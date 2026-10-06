from __future__ import annotations

import pathlib
import json
import threading
import time
from datetime import datetime, timezone

from osd_time import infer_media_start_from_osd, verify_clip_time
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
gateway_common.GATEWAY_VERSION = "1.3.3+bounded-fallback-1"

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

            original_playback_uri = str(search["playback_uri"])
            playback_uri = bounded_playback_uri(
                original_playback_uri,
                clip_start,
                clip_end,
                channel_id * 100 + 1,
            )
            log(
                f"job={job_id} build=bounded-fallback-1 download_mode=time "
                f"requested_start={clip_start.isoformat()} requested_end={clip_end.isoformat()}"
            )
            download_mode = "time"
            requested_duration = max(1, int((clip_end - clip_start).total_seconds()))
            download_segment_start = clip_start
            source_clock_alignment: dict = {}

            try:
                download_mode = hik.download_recording(playback_uri, raw_path) or "time"
            except RuntimeError as exc:
                if not str(exc).startswith("download_rejected:"):
                    raise

                log(
                    f"job={job_id} bounded HTTP export rejected; "
                    "trying original ISAPI file export"
                )
                raw_path.unlink(missing_ok=True)
                try:
                    file_mode = hik.download_recording(original_playback_uri, raw_path) or "time"
                    download_mode = "http_file"
                    if file_mode not in {"time", "http_query_time"}:
                        download_mode = f"http_file_{file_mode}"
                    segment_start = str(search.get("segment_start") or "").strip()
                    if not segment_start:
                        raise RuntimeError("recording_start_required")
                    download_segment_start = parse_iso(segment_start)
                except RuntimeError as file_exc:
                    raw_path.unlink(missing_ok=True)
                    file_error = str(file_exc)
                    if not (
                        file_error.startswith("download_rejected:")
                        or file_error.startswith("invalid_http_playback_window")
                    ):
                        raise
                    log(
                        f"job={job_id} original ISAPI file export rejected; "
                        "trying bounded RTSP playback"
                    )
                    download_mode = "rtsp_time"
                    download_segment_start = clip_start
                    hik.download_playback_stream(playback_uri, raw_path, requested_duration)

            if not raw_path.exists() or raw_path.stat().st_size <= 0:
                raise RuntimeError("empty_download")

            # Old DS-7616 firmware can return a valid historical file while its
            # ContentMgmt segment_start metadata points to the wrong place. Prefer
            # OSD alignment for file exports. If the OSD is unreadable, do not trust
            # the file metadata: retry the same exact historical window over bounded
            # RTSP instead. This preserves the duplicate-content guard and avoids
            # accepting a stale 30-second clip merely because OCR was unavailable.
            if download_mode.startswith("http_file"):
                source_clock_alignment = infer_media_start_from_osd(
                    raw_path,
                    clip_start,
                    requested_duration,
                )
                if source_clock_alignment.get("status") == "aligned":
                    download_segment_start = parse_iso(
                        str(source_clock_alignment["media_start_at"])
                    )
                    log(
                        f"job={job_id} osd_source_offset_seconds="
                        f"{source_clock_alignment.get('offset_seconds')}"
                    )
                else:
                    reason = str(
                        source_clock_alignment.get("reason")
                        or "clock_reading_unavailable"
                    )[:120]
                    log(
                        f"job={job_id} file_osd_alignment={reason}; "
                        "retrying bounded RTSP playback"
                    )
                    raw_path.unlink(missing_ok=True)
                    download_mode = "rtsp_time"
                    download_segment_start = clip_start
                    hik.download_playback_stream(
                        playback_uri,
                        raw_path,
                        requested_duration,
                    )
                    if not raw_path.exists() or raw_path.stat().st_size <= 0:
                        raise RuntimeError("empty_download")
                    source_clock_alignment = {
                        **source_clock_alignment,
                        "fallback": "bounded_rtsp",
                        "bounded_window_verified": True,
                    }

            media = prepare_browser_clip(
                raw_path,
                exact_path,
                clip_start,
                download_segment_start.replace(microsecond=0).isoformat(),
                requested_duration,
            )
            clock_check = verify_clip_time(
                hik,
                channel_id,
                exact_path,
                clip_start,
                media["duration_seconds"],
            )
            log(f"job={job_id} clock_status={clock_check['status']}")
            if not media["exact_trim"]:
                raise RuntimeError("clip_duration_mismatch")
            if clock_check["status"] == "mismatch":
                raise RuntimeError("clip_clock_mismatch")

            bounded_window_verified = (
                download_mode in {"time", "http_query_time", "rtsp_time"}
                and abs(
                    (
                        download_segment_start.astimezone(timezone.utc)
                        - clip_start.astimezone(timezone.utc)
                    ).total_seconds()
                ) <= 0.05
            )
            if (
                clock_check["status"] != "matched"
                and not bounded_window_verified
            ):
                raise RuntimeError("playback_clip_clock_unverified")

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
                    "gateway_build": "bounded-fallback-1",
                    "download_mode": download_mode,
                    "download_start": download_segment_start.replace(microsecond=0).isoformat(),
                    "source_clock_alignment": source_clock_alignment,
                    "media_time_verified": clock_check["status"] == "matched",
                    "bounded_window_verified": bounded_window_verified,
                    "clock_check": clock_check,
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
            if "rtsp_playback_failed:unsupported_hevc_payload" in message:
                try:
                    diagnostics = hik.playback_diagnostics(channel_id)
                    if source_clock_alignment:
                        diagnostics["file_clock_status"] = source_clock_alignment.get("status")
                        diagnostics["file_clock_reason"] = source_clock_alignment.get("reason")
                        diagnostics["file_clock_samples"] = source_clock_alignment.get("samples_read", 0)
                    message = message[:450] + ":diag=" + json.dumps(diagnostics, separators=(",", ":"))
                except Exception:
                    pass
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
    heartbeat_cloud = CloudClient(cfg)
    hik = HikvisionClient(cfg)

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
    import sys
    if len(sys.argv) == 3 and sys.argv[1] == '--verify-ocr-fixture':
        from osd_time import ocr_image, dates_in_text
        result = dates_in_text(ocr_image(pathlib.Path(sys.argv[2])), timezone.utc, 'YMD')
        sys.exit(0 if result else 1)
    main()
