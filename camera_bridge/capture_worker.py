"""Continuous O-KAM ring buffer + Supabase transaction video worker."""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

from okam_native.p2p import P2PError
from okam_native.session import NativeStreamSession

from supabase_api import SupabaseAPI, SupabaseAPIError


SEGMENT_PATTERN = re.compile(r"^(\d{8}T\d{6})\.ts$")


def parse_iso(value: object) -> datetime:
    if not isinstance(value, str) or not value:
        raise ValueError("invalid_timestamp")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def segment_time(path: Path) -> datetime | None:
    match = SEGMENT_PATTERN.match(path.name)
    if match is None:
        return None
    try:
        return datetime.strptime(match.group(1), "%Y%m%dT%H%M%S").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def duration_from_ffmpeg(ffmpeg: str, path: Path) -> float:
    completed = subprocess.run(
        [ffmpeg, "-hide_banner", "-i", str(path), "-f", "null", "-"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        check=False,
        timeout=30,
    )
    text = completed.stderr.decode("utf-8", errors="ignore")
    match = re.search(r"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)", text)
    if match is None:
        raise RuntimeError("duration_probe_failed")
    hours = int(match.group(1))
    minutes = int(match.group(2))
    seconds = float(match.group(3))
    return hours * 3600 + minutes * 60 + seconds


@dataclass(frozen=True)
class CapturedClip:
    path: Path
    duration_seconds: int
    byte_size: int
    sha256: str
    ring_first_segment: str
    ring_last_segment: str


class RingBuffer:
    def __init__(
        self,
        *,
        session: NativeStreamSession,
        ffmpeg: str,
        directory: Path,
        segment_seconds: int = 2,
        retention_seconds: int = 240,
        state_callback: Callable[..., None] | None = None,
    ) -> None:
        self.session = session
        self.ffmpeg = ffmpeg
        self.directory = directory
        self.segment_seconds = segment_seconds
        self.retention_seconds = retention_seconds
        self.state_callback = state_callback or (lambda **_: None)
        self.stop_event = threading.Event()
        self.thread: threading.Thread | None = None
        self.started_at = 0.0
        self.last_segment_at = 0.0
        self.last_error: str | None = None

    def start(self) -> None:
        self.directory.mkdir(parents=True, exist_ok=True)
        for old in self.directory.glob("*.ts"):
            old.unlink(missing_ok=True)
        self.started_at = time.time()
        self.thread = threading.Thread(target=self._run_forever, name="okam-ring", daemon=True)
        self.thread.start()

    def stop(self) -> None:
        self.stop_event.set()
        if self.thread is not None:
            self.thread.join(timeout=10)

    def warmed_seconds(self) -> float:
        return max(0.0, time.time() - self.started_at)

    def _run_forever(self) -> None:
        while not self.stop_event.is_set():
            try:
                self._run_once()
            except Exception as error:
                self.last_error = type(error).__name__
                self.state_callback(ring_ready=False, ring_error=self.last_error)
                if self.stop_event.wait(5):
                    return

    def _run_once(self) -> None:
        subscription = self.session.acquire()
        segmenter: subprocess.Popen[bytes] | None = None
        writer: threading.Thread | None = None
        try:
            output_pattern = str(self.directory / "%Y%m%dT%H%M%S.ts")
            segmenter = subprocess.Popen(
                [
                    self.ffmpeg,
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-fflags",
                    "+genpts",
                    "-use_wallclock_as_timestamps",
                    "1",
                    "-f",
                    "h264",
                    "-i",
                    "pipe:0",
                    "-map",
                    "0:v:0",
                    "-c:v",
                    "copy",
                    "-f",
                    "segment",
                    "-segment_time",
                    str(self.segment_seconds),
                    "-reset_timestamps",
                    "1",
                    "-strftime",
                    "1",
                    output_pattern,
                ],
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                bufsize=0,
            )
            assert segmenter.stdin is not None

            def feed() -> None:
                try:
                    for chunk in subscription:
                        if self.stop_event.is_set():
                            break
                        segmenter.stdin.write(chunk)  # type: ignore[union-attr]
                        segmenter.stdin.flush()  # type: ignore[union-attr]
                except (BrokenPipeError, ConnectionError, OSError, ValueError):
                    pass
                finally:
                    try:
                        segmenter.stdin.close()  # type: ignore[union-attr]
                    except (OSError, ValueError):
                        pass

            writer = threading.Thread(target=feed, name="okam-ring-feed", daemon=True)
            writer.start()
            self.state_callback(ring_ready=True, ring_error=None)

            while not self.stop_event.wait(1):
                if segmenter.poll() is not None:
                    raise RuntimeError("ring_segmenter_exited")
                files = sorted(self.directory.glob("*.ts"))
                if files:
                    self.last_segment_at = time.time()
                    self.state_callback(
                        ring_ready=True,
                        ring_segments=len(files),
                        ring_warmed_seconds=int(self.warmed_seconds()),
                    )
                self._cleanup()
        finally:
            subscription.close()
            if segmenter is not None and segmenter.poll() is None:
                segmenter.terminate()
                try:
                    segmenter.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    segmenter.kill()
                    segmenter.wait(timeout=5)
            if writer is not None:
                writer.join(timeout=2)

    def _cleanup(self) -> None:
        cutoff = datetime.now(timezone.utc).timestamp() - self.retention_seconds
        files = sorted(self.directory.glob("*.ts"))
        # Keep the newest segment because ffmpeg may still be writing it.
        for path in files[:-1]:
            started = segment_time(path)
            if started is not None and started.timestamp() < cutoff:
                path.unlink(missing_ok=True)

    def capture(self, start_at: datetime, end_at: datetime, output: Path) -> CapturedClip:
        now = datetime.now(timezone.utc)
        if end_at > now:
            time.sleep(min(35.0, max(0.0, (end_at - now).total_seconds() + 1.5)))

        files: list[tuple[datetime, Path]] = []
        for path in sorted(self.directory.glob("*.ts")):
            started = segment_time(path)
            if started is not None:
                files.append((started, path))
        if len(files) < 2:
            raise RuntimeError("ring_buffer_not_ready")

        # Include one segment before the requested start and one after the end.
        selected: list[tuple[datetime, Path]] = []
        for index, item in enumerate(files):
            started, path = item
            next_start = files[index + 1][0] if index + 1 < len(files) else started.timestamp() + self.segment_seconds
            if isinstance(next_start, float):
                overlaps = started <= end_at and datetime.fromtimestamp(next_start, timezone.utc) >= start_at
            else:
                overlaps = started <= end_at and next_start >= start_at
            if overlaps:
                selected.append(item)
        if not selected:
            raise RuntimeError("ring_buffer_miss")

        first_index = files.index(selected[0])
        last_index = files.index(selected[-1])
        first_index = max(0, first_index - 1)
        last_index = min(len(files) - 1, last_index + 1)
        selected = files[first_index : last_index + 1]

        earliest = selected[0][0]
        latest = selected[-1][0]
        if earliest > start_at or latest + (end_at - start_at) < start_at:
            raise RuntimeError("ring_buffer_incomplete")

        duration = (end_at - start_at).total_seconds()
        if duration < 1 or duration > 120:
            raise RuntimeError("invalid_clip_duration")
        offset = max(0.0, (start_at - earliest).total_seconds())

        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".txt", delete=False) as concat:
            concat_path = Path(concat.name)
            for _started, path in selected:
                escaped = str(path.resolve()).replace("'", "'\\''")
                concat.write(f"file '{escaped}'\n")
        try:
            command = [
                self.ffmpeg,
                "-hide_banner",
                "-loglevel",
                "error",
                "-f",
                "concat",
                "-safe",
                "0",
                "-i",
                str(concat_path),
                "-ss",
                f"{offset:.3f}",
                "-t",
                f"{duration:.3f}",
                "-an",
                "-c:v",
                "libx264",
                "-preset",
                "veryfast",
                "-crf",
                "20",
                "-pix_fmt",
                "yuv420p",
                "-movflags",
                "+faststart",
                "-y",
                str(output),
            ]
            completed = subprocess.run(
                command,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                check=False,
                timeout=90,
            )
            if completed.returncode != 0 or not output.is_file():
                raise RuntimeError("clip_encode_failed")
        finally:
            concat_path.unlink(missing_ok=True)

        actual_duration = duration_from_ffmpeg(self.ffmpeg, output)
        size = output.stat().st_size
        if actual_duration < 28.0 or actual_duration > 32.0:
            raise RuntimeError("clip_quality_gate_failed_duration")
        if size < 20_000:
            raise RuntimeError("clip_quality_gate_failed_size")

        digest = hashlib.sha256()
        with output.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        return CapturedClip(
            path=output,
            duration_seconds=int(round(actual_duration)),
            byte_size=size,
            sha256=digest.hexdigest(),
            ring_first_segment=selected[0][1].name,
            ring_last_segment=selected[-1][1].name,
        )


class CaptureWorker:
    def __init__(
        self,
        *,
        session: NativeStreamSession,
        ffmpeg: str,
        state_callback: Callable[..., None] | None = None,
    ) -> None:
        self.state_callback = state_callback or (lambda **_: None)
        self.gateway_id = os.environ.get("ZHIROX_GATEWAY_ID", "").strip()
        self.supabase_url = os.environ.get("SUPABASE_URL", "").strip()
        self.supabase_secret = os.environ.get("SUPABASE_SECRET_KEY", "").strip()
        self.bucket = os.environ.get("VIDEO_BUCKET", "transaction-camera-clips").strip()
        self.poll_seconds = max(1.0, float(os.environ.get("JOB_POLL_SECONDS", "2")))
        self.ring = RingBuffer(
            session=session,
            ffmpeg=ffmpeg,
            directory=Path(os.environ.get("RING_DIRECTORY", "/tmp/zhirox-ring")),
            segment_seconds=max(1, int(os.environ.get("RING_SEGMENT_SECONDS", "2"))),
            retention_seconds=max(90, int(os.environ.get("RING_RETENTION_SECONDS", "240"))),
            state_callback=self.state_callback,
        )
        self.api: SupabaseAPI | None = None
        self.stop_event = threading.Event()
        self.thread: threading.Thread | None = None

    def configured(self) -> bool:
        return bool(self.gateway_id and self.supabase_url and self.supabase_secret)

    def start(self) -> None:
        if not self.configured():
            self.state_callback(capture_worker="disabled_missing_config")
            return
        self.api = SupabaseAPI(self.supabase_url, self.supabase_secret)
        self.ring.start()
        self.thread = threading.Thread(target=self._run, name="zhirox-capture-worker", daemon=True)
        self.thread.start()
        self.state_callback(capture_worker="starting")

    def stop(self) -> None:
        self.stop_event.set()
        if self.thread is not None:
            self.thread.join(timeout=10)
        self.ring.stop()

    def _run(self) -> None:
        assert self.api is not None
        # We need a complete pre-event buffer before we are allowed to claim
        # jobs. This guarantees the 15-second pre-roll contract.
        while not self.stop_event.is_set() and self.ring.warmed_seconds() < 20:
            self.state_callback(
                capture_worker="warming",
                ring_warmed_seconds=int(self.ring.warmed_seconds()),
            )
            self.stop_event.wait(1)
        self.state_callback(capture_worker="ready")

        while not self.stop_event.is_set():
            try:
                job = self.api.claim_job(self.gateway_id)
            except SupabaseAPIError as error:
                self.state_callback(capture_worker="supabase_error", worker_error=str(error))
                self.stop_event.wait(5)
                continue
            if job is None:
                self.stop_event.wait(self.poll_seconds)
                continue
            self._process_job(job)

    def _process_job(self, job: dict[str, object]) -> None:
        assert self.api is not None
        job_id = str(job.get("job_id") or "")
        market_id = str(job.get("market_id") or "")
        source_type = str(job.get("source_type") or "")
        source_id = str(job.get("source_id") or "")
        attempt_token = str(job.get("attempt_token") or "")
        attempt_count = int(job.get("attempt_count") or 0)
        attempt_generation = int(job.get("attempt_generation") or 0)
        if not all((job_id, market_id, source_type, source_id, attempt_token)):
            self.state_callback(capture_worker="invalid_job")
            return

        try:
            start_at = parse_iso(job.get("clip_start_at"))
            end_at = parse_iso(job.get("clip_end_at"))
            tx_at = parse_iso(job.get("transaction_at"))
            with tempfile.TemporaryDirectory(prefix="zhirox-clip-") as tmp:
                output = Path(tmp) / "clip.mp4"
                clip = self.ring.capture(start_at, end_at, output)
                object_path = (
                    f"{market_id}/{tx_at:%Y/%m/%d}/{source_type}/"
                    f"{source_id}-{job_id}-a{attempt_count}.mp4"
                )
                self.api.upload_clip(self.bucket, object_path, clip.path)
                metadata: dict[str, object] = {
                    "provider": "okam_p2p",
                    "camera_id": os.environ.get("OKAM_CAMERA_ID", "a11-cashier"),
                    "exact_trim": True,
                    "requested_start": start_at.isoformat(),
                    "requested_end": end_at.isoformat(),
                    "segment_start": start_at.isoformat(),
                    "segment_end": end_at.isoformat(),
                    "attempt_fenced": True,
                    "attempt_generation": attempt_generation,
                    "ring_first_segment": clip.ring_first_segment,
                    "ring_last_segment": clip.ring_last_segment,
                }
                completed = self.api.complete_job(
                    gateway_id=self.gateway_id,
                    job_id=job_id,
                    attempt_token=attempt_token,
                    object_path=object_path,
                    content_sha256=clip.sha256,
                    byte_size=clip.byte_size,
                    duration_seconds=clip.duration_seconds,
                    playback_metadata=metadata,
                )
                if not completed:
                    raise RuntimeError("complete_rejected")
                self.state_callback(
                    capture_worker="ready",
                    last_job_status="ready",
                    last_job_id=job_id,
                    last_job_attempt=attempt_count,
                    last_object_path=object_path,
                )
                print(
                    f"video_job_ready=true attempt={attempt_count} bytes={clip.byte_size}",
                    flush=True,
                )
        except Exception as error:
            code = type(error).__name__
            message = str(error)
            safe = re.sub(r"[^A-Za-z0-9_.:-]", "_", message)[:180]
            reason = f"okam_bridge:{code}:{safe}"
            try:
                self.api.fail_job(
                    gateway_id=self.gateway_id,
                    job_id=job_id,
                    attempt_token=attempt_token,
                    error=reason,
                    missing=False,
                )
            except SupabaseAPIError:
                pass
            self.state_callback(
                capture_worker="job_failed",
                last_job_status="retrying",
                last_job_id=job_id,
                last_job_attempt=attempt_count,
                worker_error=reason,
            )
            print(f"video_job_ready=false error={code} attempt={attempt_count}", flush=True)
