from __future__ import annotations

from typing import Any, Callable

from rtsp_codec_relay import take_timing_attestation


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
    """Accept normal proof or a proven-success download with only relay teardown noise.

    A relay can see BrokenPipe/ConnectionReset when FFmpeg intentionally closes the
    loopback RTSP session after the requested duration. The recorder timing proof is
    still independent and valid if DESCRIBE/PLAY/absolute Range all matched exactly
    and the download function itself returned successfully. No other relay failure is
    promoted, and OCR mismatch remains authoritative in ``install`` below.
    """
    if not _strict_timing_fields_match(attestation, duration_seconds):
        return False
    if attestation.get("verified") is True:
        return True
    return bool(
        attestation.get("reason") == "relay_failed"
        and attestation.get("relay_failed") is True
        and attestation.get("download_succeeded") is True
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
                attestation = dict(attestation)
                # Reaching this line means the guarded relay download returned
                # normally (FFmpeg returncode 0, corrected SDP, non-empty output).
                # This flag is intentionally added here, never inside the relay.
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
            tolerated_teardown = bool(
                attestation.get("verified") is not True
                and attestation.get("reason") == "relay_failed"
            )
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

        reason = str(attestation.get("reason") or "attestation_unverified")
        enriched = dict(result)
        original_reason = str(result.get("reason") or "clock_reading_unavailable")
        enriched["reason"] = f"{original_reason};transport_{reason}"[:180]
        enriched["transport_attestation"] = attestation
        return enriched

    verify_with_transport_clock._zhirox_transport_clock = True
    agent_module.verify_clip_time = verify_with_transport_clock
