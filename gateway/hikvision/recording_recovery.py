from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Callable

import common


def _advertised_recorder_offset(hik: Any, channel_id: int) -> int | None:
    """Read the recorder-advertised UTC offset without changing recorder state."""
    try:
        facts = hik.playback_diagnostics(channel_id)
        raw = str(facts.get("nvr_time") or "").strip()
        if not raw:
            return None
        value = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        offset = value.utcoffset()
        if offset is None:
            return None
        seconds = int(offset.total_seconds())
        if seconds == 0 or abs(seconds) > 14 * 3600:
            return None
        return seconds
    except Exception:
        return None


def _prefer_working_clock_convention(hik: Any, job: dict, log: Callable[[str], None]) -> None:
    """Probe both UTC and recorder-local indexes before a job can become missing.

    Old Hikvision firmware can index playback search by the recorder wall clock
    even while the cloud transaction timestamps are UTC. The production agent
    already supports both query conventions, but a zero-result first search used
    to return immediately before the second convention was attempted. This
    preflight only changes candidate order when the recorder itself advertises a
    non-zero offset and a recording is actually discoverable at that shifted
    window. The normal agent still performs exact-window and clock verification.
    """
    if getattr(hik, "_verified_playback_clock_offset", 0):
        return

    channel_id = int(job["channel_id"])
    clip_start = common.parse_iso(str(job["clip_start_at"]))
    clip_end = common.parse_iso(str(job["clip_end_at"]))
    transaction_at = common.parse_iso(str(job["transaction_at"]))
    offset = _advertised_recorder_offset(hik, channel_id)
    if not offset:
        return

    try:
        utc_result = hik.search_recording(
            channel_id, clip_start, clip_end, transaction_at
        )
    except Exception:
        utc_result = None
    if isinstance(utc_result, dict) and utc_result.get("found"):
        return

    shifted_start = clip_start + timedelta(seconds=offset)
    shifted_end = clip_end + timedelta(seconds=offset)
    shifted_transaction = transaction_at + timedelta(seconds=offset)
    try:
        shifted = hik.search_recording(
            channel_id, shifted_start, shifted_end, shifted_transaction
        )
    except Exception:
        return
    if not isinstance(shifted, dict) or not shifted.get("found"):
        return

    hik._verified_playback_clock_offset = offset
    log(
        "recording_search_clock_recovery=true "
        f"channel={channel_id} recorder_utc_offset_seconds={offset}"
    )


def install(agent_module: Any, log: Callable[[str], None]) -> None:
    """Install the missing-recording recovery preflight exactly once."""
    current = agent_module.process_job
    if getattr(current, "_zhirox_recording_recovery", False):
        return

    def wrapped(cloud, heartbeat_cloud, hik, job):
        try:
            _prefer_working_clock_convention(hik, job, log)
        except Exception as exc:
            log(
                "recording_search_recovery_error="
                f"{type(exc).__name__}:{str(exc)[:180]}"
            )
        return current(cloud, heartbeat_cloud, hik, job)

    wrapped._zhirox_recording_recovery = True
    agent_module.process_job = wrapped
