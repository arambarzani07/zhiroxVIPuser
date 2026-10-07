from __future__ import annotations

from typing import Any, Callable

from fast_clock_guard import verify_transport_contradiction
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
    """Verify corrected RTSP playback without an unbounded OCR bottleneck.

    SDP correction alone is never timing proof. The relay must observe a successful
    upstream DESCRIBE and PLAY plus an absolute ``Range: clock=...`` response whose
    start (and end, when present) matches the exact bounded historical URI.

    When that independent transport proof is complete, a bounded two-frame OSD
    guard looks for a contradictory visible clock. A detected mismatch always
    vetoes approval. Missing/unreadable OSD does not block an otherwise fully
    attested RTSP clock range.

    A relay transport failure is never accepted and is returned immediately as an
    unknown clock so the DB backoff can retry it, rather than spending several
    minutes in exhaustive OCR that cannot repair a failed RTSP relay. Other
    incomplete attestations retain the exhaustive OCR fallback because visible OSD
    can still independently prove their clip time.
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
        relay_used = getattr(hik, "_playback_codec_relay_used", False) is True
        attestation = getattr(hik, "_playback_timing_attestation", None)
        if not isinstance(attestation, dict):
            attestation = {"verified": False, "reason": "attestation_missing"}

        # Fast path is allowed only after the NVR itself has supplied a fully
        # verified absolute clock range for this exact bounded PLAY request.
        if relay_used and _attestation_matches_duration(attestation, duration_seconds):
            guard = verify_transport_contradiction(path, clip_start, duration_seconds)
            if not isinstance(guard, dict):
                guard = {
                    "status": "unknown",
                    "method": "osd_ocr_fast_guard",
                    "reason": "guard_result_invalid",
                }

            if guard.get("status") == "mismatch":
                rejected = dict(guard)
                rejected["transport_attestation"] = attestation
                log("clip_clock_transport_rejected_by=osd_fast_guard")
                return rejected

            promoted = dict(guard)
            promoted.update(
                status="matched",
                method="rtsp_play_absolute_clock",
                reason="upstream_play_clock_range_matched",
                transport_attestation=attestation,
                osd_guard_status=str(guard.get("status") or "unknown"),
                osd_guard_reason=str(guard.get("reason") or "clock_reading_unavailable")[:120],
            )
            log(
                "clip_clock_verified_by=rtsp_play_absolute_clock "
                f"osd_guard={promoted['osd_guard_status']}"
            )
            return promoted

        # A relay that actually failed cannot be repaired by OCR. Keep the result
        # unverified and let the DB's bounded backoff retry a fresh RTSP session.
        if relay_used and (
            attestation.get("relay_failed") is True
            or attestation.get("reason") == "relay_failed"
        ):
            log("clip_clock_retry_reason=transport_relay_failed_fast")
            return {
                "status": "unknown",
                "method": "rtsp_play_absolute_clock",
                "reason": "transport_relay_failed_fast_retry",
                "transport_attestation": attestation,
                "osd_guard_status": "skipped",
                "osd_guard_reason": "relay_failed_before_clock_proof",
            }

        # Without complete transport proof retain the exhaustive legacy verifier.
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
