"""Minimal server-side Supabase client for the ZHIROX camera worker.

Uses only the secret key supplied as a runtime environment variable. Nothing in
this module is intended for Flutter/client-side use.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


class SupabaseAPIError(RuntimeError):
    pass


class SupabaseAPI:
    def __init__(self, url: str, secret_key: str) -> None:
        self.url = url.rstrip("/")
        self.secret_key = secret_key
        if not self.url.startswith("https://"):
            raise SupabaseAPIError("SUPABASE_URL must use https")
        if not secret_key:
            raise SupabaseAPIError("SUPABASE_SECRET_KEY is required")

    def _request(
        self,
        method: str,
        path: str,
        *,
        body: bytes | None = None,
        content_type: str = "application/json",
        extra_headers: dict[str, str] | None = None,
        timeout: float = 30.0,
    ) -> bytes:
        headers = {
            "apikey": self.secret_key,
            "Authorization": f"Bearer {self.secret_key}",
            "Content-Type": content_type,
        }
        if extra_headers:
            headers.update(extra_headers)
        request = urllib.request.Request(
            self.url + path,
            data=body,
            method=method,
            headers=headers,
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310
                payload = response.read()
                if response.status < 200 or response.status >= 300:
                    raise SupabaseAPIError(f"supabase_http_{response.status}")
                return payload
        except urllib.error.HTTPError as error:
            # Never include response bodies because database/API errors can
            # contain operational details. Status is enough for retry logic.
            raise SupabaseAPIError(f"supabase_http_{error.code}") from None
        except (OSError, urllib.error.URLError, TimeoutError):
            raise SupabaseAPIError("supabase_network_error") from None

    def rpc(self, name: str, params: dict[str, object]) -> object:
        payload = self._request(
            "POST",
            "/rest/v1/rpc/" + urllib.parse.quote(name, safe=""),
            body=json.dumps(params, separators=(",", ":")).encode("utf-8"),
        )
        try:
            return json.loads(payload.decode("utf-8"))
        except (UnicodeError, json.JSONDecodeError):
            raise SupabaseAPIError("supabase_invalid_json") from None

    def claim_job(self, gateway_id: str) -> dict[str, object] | None:
        result = self.rpc(
            "hikvision_gateway_claim_v2_service",
            {"p_gateway_id": gateway_id},
        )
        if not isinstance(result, list):
            raise SupabaseAPIError("claim_invalid_response")
        if not result:
            return None
        item = result[0]
        if not isinstance(item, dict):
            raise SupabaseAPIError("claim_invalid_job")
        return item

    def fail_job(
        self,
        *,
        gateway_id: str,
        job_id: str,
        attempt_token: str,
        error: str,
        missing: bool = False,
    ) -> bool:
        result = self.rpc(
            "hikvision_gateway_fail_v2_service",
            {
                "p_gateway_id": gateway_id,
                "p_job_id": job_id,
                "p_attempt_token": attempt_token,
                "p_error": error[:900],
                "p_missing": missing,
            },
        )
        return result is True

    def complete_job(
        self,
        *,
        gateway_id: str,
        job_id: str,
        attempt_token: str,
        object_path: str,
        content_sha256: str,
        byte_size: int,
        duration_seconds: int,
        playback_metadata: dict[str, object],
    ) -> bool:
        result = self.rpc(
            "hikvision_gateway_complete_v2_service",
            {
                "p_gateway_id": gateway_id,
                "p_job_id": job_id,
                "p_attempt_token": attempt_token,
                "p_object_path": object_path,
                "p_thumbnail_path": None,
                "p_content_sha256": content_sha256,
                "p_byte_size": byte_size,
                "p_duration_seconds": duration_seconds,
                "p_playback_metadata": playback_metadata,
            },
        )
        return result is True

    def upload_clip(self, bucket: str, object_path: str, file_path: Path) -> None:
        encoded = "/".join(urllib.parse.quote(part, safe="") for part in object_path.split("/"))
        self._request(
            "POST",
            f"/storage/v1/object/{urllib.parse.quote(bucket, safe='')}/{encoded}",
            body=file_path.read_bytes(),
            content_type="video/mp4",
            extra_headers={"x-upsert": "true", "Cache-Control": "3600"},
            timeout=120.0,
        )
