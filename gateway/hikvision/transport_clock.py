from __future__ import annotations

from typing import Any, Callable

from rtsp_codec_relay import take_timing_attestation
from transport_spot_check import verify_transport_spot_check


def _strict_timing_fields_match(attestation: dict, duration_seconds: float) -> bool:
    """Require the full absolute-clock proof, independent of relay teardown state."""
    try:
        requested = float(attestation.get("requested_duration_seconds"))
        duration = float(duration_seconds)
        start_delta = float(attestation.get("start_delta_seconds"))
        end_delta_raw = attestation.get("end_delta_seconds")
        end_delta = None if end_delta_raw is None else float(end_delta_raw)
    except (TypeError, ValueError):
        return False

    end_present = attestation.get("range_end_present") is True
    return bool(
        attestation.get("sdp_corrected") is True
        and attestation.get("describe_accepted") is True
        and attestation.get("play_accepted") is True
        and attestation.get("range_kind") == "clock"
        and abs(requested - duration) <= 0.1
        and abs(start_delta) <= 1.0
        and (not end_present or (end_delta is not None and abs(end_delta) <= 1.0))
    )


def _attestation_matches_duration(attestation: dict, duration_seconds: float) -> bool:
    """Accept normal proof or a proven-success download with only relay teardown noise."""
    if not _strict_timing_fields_match(attestation, duration_seconds):
        return False
    if attestation.get("verified") is True:
        return True
    return bool(
        attestation.get("reason") == "relay_failed"
        and attestation.get("relay_failed") is True
        and attestation.get("download_succeeded") is True
    )


def _promote_transport(result: dict, attestation: dict, log: Callable[[str], None]) -> dict:
    tolerated_teardown = bool(
        attestation.get("verified") is not True
        and attestation.get("reason") == "relay_failed"
    )
    promoted = dict(result)
    promoted.update(
        status="matched",
        method="rtsp_play_absolute_clock",
        reason=(
            "upstream_play_clock_range_matched_after_successful_download"
            if tolerated_teardown
            else "upstream_play_clock_range_matched"
        ),
        transport_attestation=attestation,
    )
    log(
        "clip_clock_verified_by=rtsp_play_absolute_clock "
        f"relay_teardown_tolerated={tolerated_teardown}"
    )
    return promoted


def install(agent_module: Any, client_class: type, log: Callable[[str], None]) -> None:
    """Promote only independently attested RTSP absolute clock ranges.

    Strict transport proof gets a fail-safe OSD contradiction spot-check instead of
    the expensive five-frame OCR alignment pass. A confirmed two-frame OSD mismatch
    always blocks the clip. If transport proof is incomplete, the original full OCR
    verifier runs unchanged.
    """
    original_download = client_class.download_playback_stream
    if not getattr(original_download, "_zhirox_transport_clock", False):
        def download_with_attestation(self, playback_uri, output_path, duration):
            take_timing_attestation(playback_uri)
            self._playback_timing_attestation = None
            result = original_download(self, playback_uri, output_path, duration)
            if getattr(self, "_playback_codec_relay_used", False) is True:
                attestation = take_timing_attestation(playback_uri) or {
                    "verified": False,
                    "reason": "attestation_missing",
                }
                attestation = dict(attestation)
                # Returning normally means FFmpeg succeeded, corrected SDP was used,
                # and the guarded download produced non-empty media.
                attestation["download_succeeded"] = True
                self._playback_timing_attestation = attestation
                teardown_candidate = bool(
                    attestation.get("reason") == "relay_failed"
                    and attestation.get("relay_failed") is True
                )
                log(
                    "rtsp_timing_attestation "
                    f"verified={bool(attestation.get('verified'))} "
                    f"reason={str(attestation.get('reason') or 'unknown')[:80]} "
                    f"range_kind={str(attestation.get('range_kind') or 'none')[:20]} "
                    f"download_succeeded=true teardown_candidate={teardown_candidate}"
                )
            return result

        download_with_attestation._zhirox_transport_clock = True
        client_class.download_playback_stream = download_with_attestation

    original_verify = agent_module.verify_clip_time
    if getattr(original_verify, "_zhirox_transport_clock", False):
        return

    def verify_with_transport_clock(hik, channel_id, path, clip_start, duration_seconds):
        relay_used = getattr(hik, "_playback_codec_relay_used", False) is True
        attestation = getattr(hik, "_playback_timing_attestation", None)
        if not isinstance(attestation, dict):
            attestation = {"verified": False, "reason": "attestation_missing"}

        # Fast path only when the recorder itself independently attests the exact
        # historical PLAY clock range and the corrected download completed.
        if relay_used and _attestation_matches_duration(attestation, duration_seconds):
            spot = verify_transport_spot_check(path, clip_start, duration_seconds)
            if isinstance(spot, dict) and spot.get("status") == "mismatch":
                blocked = dict(spot)
                blocked["transport_attestation"] = attestation
                log("clip_clock_rejected_by=osd_transport_spot_check")
                return blocked
            base = spot if isinstance(spot, dict) else {
                "status": "unknown",
                "method": "osd_transport_spot_check",
                "reason": "spot_check_unavailable",
            }
            promoted = _promote_transport(base, attestation, log)
            promoted["osd_spot_check"] = spot
            promoted["transport_fast_path"] = True
            return promoted

        # No complete transport proof: retain the original five-frame verifier.
        result = original_verify(hik, channel_id, path, clip_start, duration_seconds)
        if not isinstance(result, dict):
            return result
        status = result.get("status")
        if status != "unknown":
            return result
        if not relay_used:
            return result

        reason = str(attestation.get("reason") or "attestation_unverified")
        enriched = dict(result)
        original_reason = str(result.get("reason") or "clock_reading_unavailable")
        enriched["reason"] = f"{original_reason};transport_{reason}"[:180]
        enriched["transport_attestation"] = attestation
        return enriched

    verify_with_transport_clock._zhirox_transport_clock = True
    agent_module.verify_clip_time = verify_with_transport_clock
