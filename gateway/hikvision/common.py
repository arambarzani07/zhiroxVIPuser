from __future__ import annotations

import base64
import ctypes
from ctypes import wintypes
import getpass
import hashlib
import html
import json
import os
import pathlib
import subprocess
import shutil
import sys
import tempfile
import time
import uuid
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Optional
from urllib.parse import parse_qs, parse_qsl, quote, urlencode, urlsplit, urlunsplit

import requests
from requests.auth import HTTPDigestAuth

GATEWAY_VERSION = "1.0.0"
CLOUD_URL = "https://madoflmbretqghqbqaak.supabase.co/functions/v1/hikvision-gateway"
APP_DIR = pathlib.Path(os.environ.get("LOCALAPPDATA", pathlib.Path.home())) / "ZHIROX" / "HikvisionGateway"
CONFIG_PATH = APP_DIR / "config.json"
LOG_PATH = APP_DIR / "gateway.log"
TEMP_DIR = APP_DIR / "tmp"


class DATA_BLOB(ctypes.Structure):
    _fields_ = [("cbData", wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_byte))]


def _blob(data: bytes):
    buf = ctypes.create_string_buffer(data)
    return DATA_BLOB(len(data), ctypes.cast(buf, ctypes.POINTER(ctypes.c_byte))), buf


def protect_secret(value: str) -> str:
    if os.name != "nt":
        raise RuntimeError("Windows DPAPI is required")
    in_blob, in_buf = _blob(value.encode("utf-8"))
    out_blob = DATA_BLOB()
    if not ctypes.windll.crypt32.CryptProtectData(
        ctypes.byref(in_blob), "ZHIROX Hikvision Gateway", None, None, None, 0,
        ctypes.byref(out_blob),
    ):
        raise ctypes.WinError()
    try:
        data = ctypes.string_at(out_blob.pbData, out_blob.cbData)
        return base64.b64encode(data).decode("ascii")
    finally:
        ctypes.windll.kernel32.LocalFree(out_blob.pbData)
        del in_buf


def unprotect_secret(value: str) -> str:
    if os.name != "nt":
        raise RuntimeError("Windows DPAPI is required")
    raw = base64.b64decode(value)
    in_blob, in_buf = _blob(raw)
    out_blob = DATA_BLOB()
    if not ctypes.windll.crypt32.CryptUnprotectData(
        ctypes.byref(in_blob), None, None, None, None, 0, ctypes.byref(out_blob)
    ):
        raise ctypes.WinError()
    try:
        return ctypes.string_at(out_blob.pbData, out_blob.cbData).decode("utf-8")
    finally:
        ctypes.windll.kernel32.LocalFree(out_blob.pbData)
        del in_buf


def run_background(command, **kwargs):
    """Keep media/OCR child processes off the Windows desktop."""
    kwargs.setdefault("stdin", subprocess.DEVNULL)
    if os.name == "nt":
        kwargs["creationflags"] = kwargs.get("creationflags", 0) | subprocess.CREATE_NO_WINDOW
    return subprocess.run(command, **kwargs)


def log(message: str) -> None:
    APP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().astimezone().isoformat(timespec="seconds")
    with LOG_PATH.open("a", encoding="utf-8") as fh:
        fh.write(f"{stamp} {message[:1200]}\n")


def parse_iso(value: str) -> datetime:
    text = value.strip().replace("Z", "+00:00")
    dt = datetime.fromisoformat(text)
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def hik_time(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def bounded_playback_uri(uri: str, start: datetime, end: datetime, track_id: int) -> str:
    """Explicit download-by-time URI, never the search result's file selector."""
    if start.tzinfo is None or end.tzinfo is None or end <= start:
        raise ValueError("invalid_download_window")
    parts = urlsplit(html.unescape(uri))
    if parts.scheme not in {"rtsp", "rtsps"} or not parts.hostname:
        raise ValueError("invalid_playback_uri")
    if parts.username or parts.password:
        raise ValueError("credentials_in_playback_uri")
    if parts.path.rstrip("/").rsplit("/", 1)[-1] != str(track_id):
        raise ValueError("playback_track_mismatch")
    # name/size mean download-by-file; retaining them may return its beginning.
    query = [(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True)
             if k.lower() not in {"starttime", "endtime", "name", "size"}]
    query += [("starttime", start.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")),
              ("endtime", end.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))]
    return urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query), ""))


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


@dataclass
class GatewayConfig:
    nvr_host: str
    nvr_username: str
    nvr_password: str
    gateway_token: str
    cloud_url: str = CLOUD_URL

    @classmethod
    def load(cls) -> "GatewayConfig":
        raw = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        return cls(
            nvr_host=str(raw["nvr_host"]),
            nvr_username=str(raw.get("nvr_username", "admin")),
            nvr_password=unprotect_secret(str(raw["nvr_password_dpapi"])),
            gateway_token=unprotect_secret(str(raw["gateway_token_dpapi"])),
            cloud_url=str(raw.get("cloud_url", CLOUD_URL)),
        )

    def save(self) -> None:
        APP_DIR.mkdir(parents=True, exist_ok=True)
        payload = {
            "nvr_host": self.nvr_host,
            "nvr_username": self.nvr_username,
            "nvr_password_dpapi": protect_secret(self.nvr_password),
            "gateway_token_dpapi": protect_secret(self.gateway_token),
            "cloud_url": self.cloud_url,
            "saved_at": datetime.now(timezone.utc).isoformat(),
        }
        CONFIG_PATH.write_text(json.dumps(payload, indent=2), encoding="utf-8")


class CloudClient:
    def __init__(self, cfg: GatewayConfig):
        self.url = cfg.cloud_url
        self.token = cfg.gateway_token
        self.session = requests.Session()

    def call(self, action: str, **body: Any) -> dict[str, Any]:
        headers = {
            "x-zhirox-gateway-token": self.token,
            "x-gateway-version": GATEWAY_VERSION,
            "x-gateway-platform": "windows",
            "Content-Type": "application/json",
        }
        response = self.session.post(
            self.url,
            headers=headers,
            json={"action": action, **body},
            timeout=35,
        )
        try:
            data = response.json()
        except Exception:
            data = {}
        if response.status_code >= 400:
            raise RuntimeError(str(data.get("error") or f"cloud_http_{response.status_code}"))
        return data

    def upload(self, signed_url: str, file_path: pathlib.Path) -> None:
        size = file_path.stat().st_size
        if size > 100 * 1024 * 1024:
            raise RuntimeError("clip_exceeds_100mb")
        with file_path.open("rb") as fh:
            response = requests.put(
                signed_url,
                data=fh,
                headers={"Content-Type": "video/mp4", "x-upsert": "false"},
                timeout=180,
            )
        if response.status_code >= 300:
            raise RuntimeError(f"upload_http_{response.status_code}")


class HikvisionClient:
    def __init__(self, cfg: GatewayConfig):
        self.host = cfg.nvr_host.strip().rstrip("/")
        if not self.host.startswith("http://") and not self.host.startswith("https://"):
            self.host = "http://" + self.host
        self.auth = HTTPDigestAuth(cfg.nvr_username, cfg.nvr_password)
        self.session = requests.Session()
        self.session.auth = self.auth

    def device_info(self) -> str:
        r = self.session.get(f"{self.host}/ISAPI/System/deviceInfo", timeout=15)
        r.raise_for_status()
        return r.text

    def _search_request(self, track_id: int, start: datetime, end: datetime, xmlns: Optional[str]) -> str:
        ns = f' version="1.0" xmlns="{xmlns}"' if xmlns else ""
        sid = "{" + str(uuid.uuid4()).upper() + "}"
        return (
            '<?xml version="1.0" encoding="UTF-8"?>'
            f'<CMSearchDescription{ns}>'
            f'<searchID>{sid}</searchID>'
            f'<trackIDList><trackID>{track_id}</trackID></trackIDList>'
            '<timeSpanList><timeSpan>'
            f'<startTime>{hik_time(start)}</startTime>'
            f'<endTime>{hik_time(end)}</endTime>'
            '</timeSpan></timeSpanList>'
            '<maxResults>40</maxResults><searchResultPostion>0</searchResultPostion>'
            '<metadataList><metadataDescriptor>//recordType.meta.std-cgi.com</metadataDescriptor></metadataList>'
            '</CMSearchDescription>'
        )

    def search_recording(self, channel_id: int, start: datetime, end: datetime, transaction_at: datetime) -> dict[str, Any]:
        track_id = channel_id * 100 + 1
        last_error = None
        for xmlns in (
            "http://www.hikvision.com/ver20/XMLSchema",
            None,
            "http://www.isapi.org/ver20/XMLSchema",
        ):
            xml = self._search_request(track_id, start, end, xmlns)
            try:
                r = self.session.post(
                    f"{self.host}/ISAPI/ContentMgmt/search",
                    data=xml.encode("utf-8"),
                    headers={"Content-Type": "application/xml"},
                    timeout=30,
                )
                if r.status_code >= 400:
                    last_error = f"search_http_{r.status_code}"
                    continue
                root = ET.fromstring(r.content)
                matches: list[dict[str, Any]] = []
                for item in root.iter():
                    if local_name(item.tag) != "searchMatchItem":
                        continue
                    data: dict[str, Any] = {}
                    for child in item.iter():
                        name = local_name(child.tag)
                        if name in {"playbackURI", "startTime", "endTime", "metadataDescriptor"} and child.text:
                            data[name] = child.text.strip()
                    if data.get("playbackURI"):
                        matches.append(data)
                if not matches:
                    return {"found": False, "track_id": track_id, "matches": 0}

                tx = transaction_at.astimezone(timezone.utc)
                def score(m: dict[str, Any]) -> float:
                    try:
                        a = parse_iso(str(m.get("startTime", ""))).astimezone(timezone.utc)
                        b = parse_iso(str(m.get("endTime", ""))).astimezone(timezone.utc)
                        if a <= tx <= b:
                            return 0.0
                        return min(abs((tx - a).total_seconds()), abs((tx - b).total_seconds()))
                    except Exception:
                        return 10**12

                eligible = []
                for match in matches:
                    try:
                        if (parse_iso(match["startTime"]) <= start and
                                parse_iso(match["endTime"]) >= end.replace(microsecond=0)):
                            eligible.append(match)
                    except (KeyError, ValueError):
                        continue
                if not eligible:
                    raise RuntimeError("recording_window_not_covered")
                best = min(eligible, key=score)
                return {
                    "found": True,
                    "track_id": track_id,
                    "playback_uri": html.unescape(str(best["playbackURI"])),
                    "segment_start": best.get("startTime"),
                    "segment_end": best.get("endTime"),
                    "matches": len(matches),
                }
            except Exception as exc:
                last_error = f"search_error:{type(exc).__name__}"
        raise RuntimeError(last_error or "search_failed")

    def download_recording(self, playback_uri: str, output_path: pathlib.Path) -> str:
        # XML is required in the GET request body on older ISAPI firmware too.
        safe_uri = html.escape(html.unescape(playback_uri), quote=False)
        endpoint = f"{self.host}/ISAPI/ContentMgmt/download"
        response = None
        download_mode = "time"
        retry_codes = {400, 405, 422, 501}
        def rejected(r):
            return r.status_code in retry_codes or (r.status_code == 200 and
                "xml" in (r.headers.get("content-type") or "").lower())
        # Firmware families accept different XML namespaces. Keep the time URI
        # unchanged; never restore name/size selectors from a search result.
        for xmlns in ("http://www.isapi.org/ver20/XMLSchema",
                      "http://www.hikvision.com/ver20/XMLSchema", None):
            ns = f' version="1.0" xmlns="{xmlns}"' if xmlns else ""
            body = ('<?xml version="1.0" encoding="UTF-8"?>'
                    f'<downloadRequest{ns}><playbackURI>{safe_uri}</playbackURI>'
                    '</downloadRequest>').encode("utf-8")
            kwargs = dict(data=body, headers={"Content-Type": "application/xml"},
                          timeout=(20, 180), stream=True)
            response = self.session.post(endpoint, **kwargs)
            if rejected(response):
                response.close()
                response = self.session.get(endpoint, **kwargs)
            if not rejected(response):
                break
            if xmlns is not None:
                response.close()
        assert response is not None
        # Some firmware expects playbackURI in the GET query, not an XML body.
        # Keep the exact historical window and never restore file name/size.
        if rejected(response):
            parts = urlsplit(html.unescape(playback_uri))
            query = parse_qs(parts.query)
            if (parts.scheme != "rtsp" or parts.username or parts.password or
                    parts.hostname != urlsplit(self.host).hostname or
                    set(query) != {"starttime", "endtime"}):
                response.close()
                raise RuntimeError("invalid_http_playback_window")
            variants = [html.unescape(playback_uri)]
            try:
                timestamps = {k: datetime.strptime(query[k][0], "%Y%m%dT%H%M%SZ")
                              for k in ("starttime", "endtime")}
                iso_query = urlencode({k: v.strftime("%Y-%m-%d %H:%M:%SZ")
                                       for k, v in timestamps.items()})
                variants.append(urlunsplit((parts.scheme, parts.netloc, parts.path, iso_query, "")))
            except (ValueError, IndexError):
                response.close()
                raise RuntimeError("invalid_http_playback_window") from None
            for uri in variants:
                response.close()
                response = self.session.get(endpoint, params={"playbackURI": uri},
                                            timeout=(20, 180), stream=True)
                download_mode = "http_query_time"
                if not rejected(response):
                    break
        with response as r:
            content_type = (r.headers.get("content-type") or "").lower()
            if r.status_code >= 400 or "xml" in content_type:
                # Log only device status fields, never the URI or credentials.
                details = []
                payload = bytearray()
                for chunk in r.iter_content(chunk_size=4096):
                    payload.extend(chunk[:4096 - len(payload)])
                    if len(payload) >= 4096:
                        break
                try:
                    root = ET.fromstring(bytes(payload))
                    for node in root.iter():
                        if local_name(node.tag) in {"statusCode", "statusString", "subStatusCode", "errorCode"}:
                            value = (node.text or "").strip()
                            if value and len(value) <= 120 and all(c.isalnum() or c in " _-." for c in value):
                                details.append(f"{local_name(node.tag)}={value}")
                except ET.ParseError:
                    pass
                raise RuntimeError(f"download_rejected:http={r.status_code};" + ";".join(details))
            with output_path.open("wb") as fh:
                for chunk in r.iter_content(chunk_size=1024 * 1024):
                    if chunk:
                        fh.write(chunk)
        return download_mode

    def download_playback_stream(self, playback_uri: str, output_path: pathlib.Path,
                                 duration: int) -> None:
        """Bounded historical RTSP playback when the HTTP export is rejected."""
        parts = urlsplit(playback_uri)
        query = parse_qs(parts.query)
        if (parts.scheme != "rtsp" or parts.username or parts.password or
                set(query) != {"starttime", "endtime"} or duration <= 0 or duration > 120):
            raise RuntimeError("invalid_rtsp_playback_window")
        host = urlsplit(self.host).hostname
        if parts.hostname != host:
            raise RuntimeError("playback_host_mismatch")
        credentials = f"{quote(self.auth.username, safe='')}:{quote(self.auth.password, safe='')}"
        uri = urlunsplit((parts.scheme, f"{credentials}@{parts.netloc}",
                          parts.path, parts.query, ""))
        # Some recorders fail to packetize historical playback correctly over
        # interleaved TCP. Retry the SAME bounded window over UDP, never live view.
        # The caller still verifies duration, full decoding and the clip clock.
        ffmpeg = find_ffmpeg()
        reason = "unknown"
        for transport in ("tcp", "udp"):
            output_path.unlink(missing_ok=True)
            try:
                result = run_background(
                    [ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                     "-rtsp_transport", transport, "-rtsp_flags", "filter_src",
                     "-timeout", "20000000",
                     "-err_detect", "ignore_err", "-fflags", "+discardcorrupt+genpts",
                     "-i", uri, "-t", str(duration), "-map", "0:v:0", "-map", "0:a:0?",
                     "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
                     "-pix_fmt", "yuv420p", "-tag:v", "avc1",
                     "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart",
                     "-f", "mp4", str(output_path)],
                    capture_output=True, timeout=duration + 90,
                )
                if (result.returncode == 0 and output_path.exists()
                        and output_path.stat().st_size > 0):
                    log(f"rtsp_playback_transport={transport}")
                    return
                stderr = (result.stderr or b"").decode("utf-8", errors="replace")
                reason = "unknown"
                for marker, category in (("Unsupported (HEVC) NAL type", "unsupported_hevc_payload"),
                                         ("453", "recorder_session_limit"),
                                         ("401 Unauthorized", "authentication"),
                                         ("Connection refused", "connection_refused"),
                                         ("timed out", "timeout"),
                                         ("dimensions not set", "missing_video_parameters")):
                    if marker in stderr:
                        reason = category
                        break
            except subprocess.TimeoutExpired:
                reason = "timeout"
            except Exception:
                # Exception strings and FFmpeg stderr can contain passwords.
                output_path.unlink(missing_ok=True)
                raise RuntimeError("rtsp_playback_failed") from None
            output_path.unlink(missing_ok=True)
            # Authentication/session-limit failures cannot be fixed by transport.
            if transport == "tcp" and reason in {
                "unsupported_hevc_payload", "missing_video_parameters", "timeout"
            }:
                log(f"rtsp_playback_retry_transport=udp reason={reason}")
                continue
            break
        raise RuntimeError("rtsp_playback_failed:" + reason) from None


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def find_ffmpeg() -> str:
    candidates = [str(APP_DIR / "ffmpeg.exe"),
                  str(pathlib.Path(sys.executable).parent / "ffmpeg.exe"),
                  shutil.which("ffmpeg.exe"), shutil.which("ffmpeg")]
    for candidate in dict.fromkeys(c for c in candidates if c):
        try:
            result = run_background([candidate, "-version"], capture_output=True, timeout=5)
            if result.returncode == 0:
                return candidate
        except (OSError, subprocess.TimeoutExpired):
            pass
    raise RuntimeError("ffmpeg_required_for_playback")


def prepare_browser_clip(source: pathlib.Path, target: pathlib.Path,
                         clip_start: datetime, segment_start: Optional[str],
                         duration: int) -> dict[str, Any]:
    """Encode and decode-check the private clip; never fall back to raw HEVC."""
    if not segment_start:
        raise RuntimeError("recording_start_required")
    offset = (clip_start.astimezone(timezone.utc) -
              parse_iso(segment_start).astimezone(timezone.utc)).total_seconds()
    if offset < -0.05 or duration <= 0:
        raise RuntimeError("invalid_clip_window")
    ffmpeg = find_ffmpeg()
    try:
        result = run_background(
            [ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
             "-ss", f"{max(0.0, offset):.3f}", "-i", str(source),
             "-t", str(duration), "-map", "0:v:0", "-map", "0:a:0?",
             "-vf", "scale=w='min(1920,iw)':h='min(1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1,fps=25",
             "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
             "-profile:v", "main", "-level:v", "4.1", "-pix_fmt", "yuv420p",
             "-tag:v", "avc1", "-threads", "2",
             "-c:a", "aac", "-b:a", "128k", "-ac", "2", "-ar", "48000",
             "-movflags", "+faststart", str(target)],
            capture_output=True, timeout=600,
        )
        if result.returncode != 0 or not target.exists() or target.stat().st_size == 0:
            raise RuntimeError("clip_conversion_failed")
        # Decode every video frame. Count frames to reject header-only MP4s and
        # report actual duration instead of claiming the requested duration.
        check = run_background(
            [ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-xerror",
             "-i", str(target), "-map", "0:v:0", "-an", "-progress", "pipe:1",
             "-f", "null", "-"], capture_output=True, timeout=180,
        )
        frames = [int(line.split("=", 1)[1].strip())
                  for line in check.stdout.decode("utf-8", errors="replace").splitlines()
                  if line.startswith("frame=")]
        if check.returncode != 0 or not frames or frames[-1] <= 0:
            raise RuntimeError("clip_decode_validation_failed")
        actual_duration = frames[-1] / 25.0
        return {"duration_seconds": actual_duration,
                "exact_trim": abs(actual_duration - duration) <= 0.1,
                "video_codec": "h264", "video_tag": "avc1",
                "pixel_format": "yuv420p", "decode_verified": True,
                "preparation_version": 2}
    except Exception:
        target.unlink(missing_ok=True)
        raise

