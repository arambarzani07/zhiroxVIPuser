from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Callable

import common
import transaction_video_invariant


LEGACY_LOCAL_CLOCK_FIRMWARES = {"V3.4.107"}


def _recorder_clock_profile(hik: Any, channel_id: int) -> tuple[dict, int | None]:
    """Read recorder facts and its advertised UTC offset without changing state."""
    try:
        facts = hik.playback_diagnostics(channel_id)
        raw = str(facts.get("nvr_time") or "").strip()
        if not raw:
            return facts, None
        value = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        offset = value.utcoffset()
        if offset is None:
            return facts, None
        seconds = int(offset.total_seconds())
        if seconds == 0 or abs(seconds) > 14 * 3600:
            return facts, None
        return facts, seconds
    except Exception:
        return {}, None


def _advertised_recorder_offset(hik: Any, channel_id: int) -> int | None:
    """Compatibility helper used by older tests and diagnostics."""
    _, offset = _recorder_clock_profile(hik, channel_id)
    return offset


def _prefer_working_clock_convention(hik: Any, job: dict, log: Callable[[str], None]) -> None:
    """Prefer the recorder wall-clock index when legacy firmware requires it.

    Hikvision V3.4.107 can report a non-zero local UTC offset while also returning
    a plausible recording for an unshifted UTC query. That UTC result is a false
    positive in the recorder's wall-clock index: a 12:27 local transaction can
    yield the 09:27 scene. On this known legacy firmware, probe the recorder-local
    window first and prefer it whenever it exists. Newer firmware preserves the
    previous UTC-first behavior.

    The normal agent still performs exact-window, codec, duration and clock
    verification after this ordering decision; this function never marks media
    itself as verified.
    """
    if getattr(hik, "_verified_playback_clock_offset", 0):
        return

    channel_id = int(job["channel_id"])
    clip_start = common.parse_iso(str(job["clip_start_at"]))
    clip_end = common.parse_iso(str(job["clip_end_at"]))
    transaction_at = common.parse_iso(str(job["transaction_at"]))
    facts, offset = _recorder_clock_profile(hik, channel_id)
    if not offset:
        return

    shifted_start = clip_start + timedelta(seconds=offset)
    shifted_end = clip_end + timedelta(seconds=offset)
    shifted_transaction = transaction_at + timedelta(seconds=offset)
    firmware = str(facts.get("firmware") or "").strip()

    if firmware in LEGACY_LOCAL_CLOCK_FIRMWARES:
        try:
            shifted = hik.search_recording(
                channel_id, shifted_start, shifted_end, shifted_transaction
            )
        except Exception:
            shifted = None
        if isinstance(shifted, dict) and shifted.get("found"):
            hik._verified_playback_clock_offset = offset
            log(
                "legacy_local_clock_priority=true "
                f"channel={channel_id} firmware={firmware} "
                f"recorder_utc_offset_seconds={offset}"
            )
        return

    try:
        utc_result = hik.search_recording(
            channel_id, clip_start, clip_end, transaction_at
        )
    except Exception:
        utc_result = None
    if isinstance(utc_result, dict) and utc_result.get("found"):
        return

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
    """Install clock recovery plus the fail-closed transaction-video invariant."""
    transaction_video_invariant.install(agent_module, log)

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
