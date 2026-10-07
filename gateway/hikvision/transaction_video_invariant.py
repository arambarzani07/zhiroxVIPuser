from __future__ import annotations

import threading
from datetime import datetime, timezone
from typing import Any, Callable

INVARIANT_VERSION = 1
LEGACY_RECORDER_LOCAL_FIRMWARES = {"V3.4.107"}
TIMESTAMP_TOLERANCE_SECONDS = 1.0
EXPECTED_PRE_ROLL_SECONDS = 15.0
EXPECTED_POST_ROLL_SECONDS = 15.0
EXPECTED_DURATION_SECONDS = 30.0
_STATE = threading.local()


def _parse_iso(value: Any) -> datetime:
    text = str(value or "").strip()
    if not text:
        raise ValueError("timestamp_missing")
    parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _delta_seconds(left: datetime, right: datetime) -> float:
    return abs((left - right).total_seconds())


def _require_timestamp_match(label: str, actual: datetime, expected: datetime) -> None:
    if _delta_seconds(actual, expected) > TIMESTAMP_TOLERANCE_SECONDS:
        raise RuntimeError(f"transaction_video_invariant:{label}_mismatch")


def _require_true(metadata: dict[str, Any], key: str) -> None:
    if metadata.get(key) is not True:
        raise RuntimeError(f"transaction_video_invariant:{key}_required")


def validate_and_stamp(
    job: dict[str, Any],
    metadata: dict[str, Any],
    recorder_facts: dict[str, Any] | None,
) -> dict[str, Any]:
    """Fail closed unless the completed clip is provably the transaction window."""
    stamped = dict(metadata)
    facts = recorder_facts if isinstance(recorder_facts, dict) else {}

    transaction_at = _parse_iso(job.get("transaction_at"))
    canonical_start = _parse_iso(job.get("clip_start_at"))
    canonical_end = _parse_iso(job.get("clip_end_at"))
    requested_start = _parse_iso(stamped.get("requested_start"))
    requested_end = _parse_iso(stamped.get("requested_end"))

    _require_timestamp_match("requested_start", requested_start, canonical_start)
    _require_timestamp_match("requested_end", requested_end, canonical_end)

    expected_start = transaction_at.timestamp() - EXPECTED_PRE_ROLL_SECONDS
    expected_end = transaction_at.timestamp() + EXPECTED_POST_ROLL_SECONDS
    if abs(canonical_start.timestamp() - expected_start) > TIMESTAMP_TOLERANCE_SECONDS:
        raise RuntimeError("transaction_video_invariant:transaction_preroll_mismatch")
    if abs(canonical_end.timestamp() - expected_end) > TIMESTAMP_TOLERANCE_SECONDS:
        raise RuntimeError("transaction_video_invariant:transaction_postroll_mismatch")

    duration = (canonical_end - canonical_start).total_seconds()
    if abs(duration - EXPECTED_DURATION_SECONDS) > 0.1:
        raise RuntimeError("transaction_video_invariant:canonical_duration_mismatch")
    try:
        media_duration = float(stamped.get("duration_seconds"))
    except (TypeError, ValueError):
        raise RuntimeError("transaction_video_invariant:media_duration_missing") from None
    if abs(media_duration - EXPECTED_DURATION_SECONDS) > 0.1:
        raise RuntimeError("transaction_video_invariant:media_duration_mismatch")

    _require_true(stamped, "exact_trim")
    _require_true(stamped, "decode_verified")

    try:
        query_shift = int(stamped.get("query_clock_offset_seconds"))
    except (TypeError, ValueError):
        raise RuntimeError("transaction_video_invariant:query_clock_offset_required") from None

    recorder_offset_raw = stamped.get("recorder_utc_offset_seconds")
    try:
        recorder_offset = int(recorder_offset_raw)
    except (TypeError, ValueError):
        recorder_offset = None

    firmware = str(facts.get("firmware") or stamped.get("recorder_firmware") or "").strip()
    if firmware in LEGACY_RECORDER_LOCAL_FIRMWARES:
        if recorder_offset is None or recorder_offset == 0:
            raise RuntimeError("transaction_video_invariant:legacy_recorder_offset_required")
        if query_shift != recorder_offset:
            raise RuntimeError("transaction_video_invariant:legacy_clock_domain_mismatch")
        if not str(stamped.get("download_mode") or "").startswith("recorder_local_"):
            raise RuntimeError("transaction_video_invariant:legacy_local_mode_required")

    clock_check = stamped.get("clock_check")
    clock_matched = isinstance(clock_check, dict) and clock_check.get("status") == "matched"
    # Requested download bounds cannot override missing or contradictory
    # evidence about the time of the actual recorded scene.
    if not clock_matched:
        raise RuntimeError("transaction_video_invariant:clock_match_required")
    if stamped.get("media_time_verified") is not True:
        raise RuntimeError("transaction_video_invariant:media_time_verified_required")

    segment_start = _parse_iso(stamped.get("segment_start"))
    segment_end = _parse_iso(stamped.get("segment_end"))
    expected_segment_start = datetime.fromtimestamp(
        canonical_start.timestamp() + query_shift, tz=timezone.utc
    )
    expected_segment_end = datetime.fromtimestamp(
        canonical_end.timestamp() + query_shift, tz=timezone.utc
    )
    if segment_start > expected_segment_start or segment_end < expected_segment_end:
        raise RuntimeError("transaction_video_invariant:recording_window_not_covered")

    attempt_generation = int(job.get("attempt_generation") or 0)
    metadata_generation = int(stamped.get("attempt_generation") or 0)
    if attempt_generation != metadata_generation:
        raise RuntimeError("transaction_video_invariant:attempt_generation_mismatch")

    stamped["recorder_firmware"] = firmware or None
    stamped["transaction_video_invariant_version"] = INVARIANT_VERSION
    stamped["transaction_video_invariant_verified"] = True
    stamped["transaction_video_transaction_at"] = transaction_at.isoformat()
    stamped["transaction_video_clock_domain_seconds"] = query_shift
    stamped["transaction_video_time_proof"] = "clock_matched"
    return stamped


def install(agent_module: Any, log: Callable[[str], None]) -> None:
    """Install a fail-closed completion gate around each production job."""
    current_process = agent_module.process_job
    if getattr(current_process, "_zhirox_transaction_video_invariant", False):
        return

    original_context = agent_module._recorder_clock_context

    def context_with_facts(hik, channel_id):
        facts, offset = original_context(hik, channel_id)
        _STATE.recorder_facts = facts if isinstance(facts, dict) else {}
        return facts, offset

    def process_with_context(cloud, heartbeat_cloud, hik, job):
        _STATE.job = job
        _STATE.recorder_facts = {}
        original_instance_call = cloud.call

        def call_with_invariant(action: str, **body: Any):
            if action == "complete":
                current_job = getattr(_STATE, "job", None)
                if not isinstance(current_job, dict):
                    raise RuntimeError("transaction_video_invariant:job_context_required")
                if str(body.get("job_id") or "") != str(current_job.get("job_id") or ""):
                    raise RuntimeError("transaction_video_invariant:job_id_mismatch")
                metadata = body.get("playback_metadata")
                if not isinstance(metadata, dict):
                    raise RuntimeError("transaction_video_invariant:metadata_required")
                body["playback_metadata"] = validate_and_stamp(
                    current_job,
                    metadata,
                    getattr(_STATE, "recorder_facts", {}),
                )
                log(
                    "transaction_video_invariant=verified "
                    f"job={str(current_job.get('job_id') or '')[:36]} "
                    f"version={INVARIANT_VERSION}"
                )
            return original_instance_call(action, **body)

        cloud.call = call_with_invariant
        try:
            return current_process(cloud, heartbeat_cloud, hik, job)
        finally:
            cloud.call = original_instance_call
            _STATE.job = None
            _STATE.recorder_facts = {}

    context_with_facts._zhirox_transaction_video_invariant = True
    process_with_context._zhirox_transaction_video_invariant = True
    agent_module._recorder_clock_context = context_with_facts
    agent_module.process_job = process_with_context
