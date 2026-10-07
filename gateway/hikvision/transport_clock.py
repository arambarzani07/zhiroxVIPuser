from __future__ import annotations

from typing import Any, Callable

from rtsp_codec_relay import take_timing_attestation


def _attestation_matches_duration(attestation: dict, duration_seconds: float) -> bool:
    try:
        requested = float(attestation.get("requested_duration_seconds"))
        duration = float(duration_seconds)
    except (TypeError, ValueError):
        return False
    return bool(
        attestation.get("verified") is True
        and attestation.get("sdp_corrected") is True
        and attestation.get("describe_accepted") is True
        and attestation.get("play_accepted") is True
        and attestation.get("range_kind") == "clock"
        and abs(requested - duration) <= 0.1
    )


def install(agent_module: Any, client_class: type, log: Callable[[str], None]) -> None:
    """Promote only independently attested RTSP absolute clock ranges.

    SDP correction alone is never timing proof. The relay must observe a successful
    upstream DESCRIBE and PLAY plus an absolute ``Range: clock=...`` response whose
    start (and end, when present) matches the exact bounded historical URI. A real
    OCR mismatch always wins and is never overridden.
    """
    original_download = client_class.download_playback_stream
    if not getattr(original_download, "_zhirox_transport_clock", False):
        def download_with_attestation(self, playback_uri, output_path, duration):
            # Discard any stale record for this exact bounded URI before starting.
            take_timing_attestation(playback_uri)
            self._playback_timing_attestation = None
            result = original_download(self, playback_uri, output_path, duration)
            if getattr(self, "_playback_codec_relay_used", False) is True:
                attestation = take_timing_attestation(playback_uri) or {
                    "verified": False,
                    "reason": "attestation_missing",
                }
                self._playback_timing_attestation = attestation
                log(
                    "rtsp_timing_attestation "
                    f"verified={bool(attestation.get('verified'))} "
                    f"reason={str(attestation.get('reason') or 'unknown')[:80]} "
                    f"range_kind={str(attestation.get('range_kind') or 'none')[:20]}"
                )
            return result

        download_with_attestation._zhirox_transport_clock = True
        client_class.download_playback_stream = download_with_attestation

    original_verify = agent_module.verify_clip_time
    if getattr(original_verify, "_zhirox_transport_clock", False):
        return

    def verify_with_transport_clock(hik, channel_id, path, clip_start, duration_seconds):
        result = original_verify(hik, channel_id, path, clip_start, duration_seconds)
        if not isinstance(result, dict):
            return result
        status = result.get("status")
        # Never override a positive OCR match or a real mismatch.
        if status != "unknown":
            return result
        if getattr(hik, "_playback_codec_relay_used", False) is not True:
            return result

        attestation = getattr(hik, "_playback_timing_attestation", None)
        if not isinstance(attestation, dict):
            attestation = {"verified": False, "reason": "attestation_missing"}

        if _attestation_matches_duration(attestation, duration_seconds):
            promoted = dict(result)
            promoted.update(
                status="matched",
                method="rtsp_play_absolute_clock",
                reason="upstream_play_clock_range_matched",
                transport_attestation=attestation,
            )
            log("clip_clock_verified_by=rtsp_play_absolute_clock")
            return promoted

        reason = str(attestation.get("reason") or "attestation_unverified")
        enriched = dict(result)
        original_reason = str(result.get("reason") or "clock_reading_unavailable")
        enriched["reason"] = f"{original_reason};transport_{reason}"[:180]
        enriched["transport_attestation"] = attestation
        return enriched

    verify_with_transport_clock._zhirox_transport_clock = True
    agent_module.verify_clip_time = verify_with_transport_clock
