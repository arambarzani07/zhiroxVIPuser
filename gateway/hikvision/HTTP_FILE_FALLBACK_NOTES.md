# Hikvision legacy HTTP file fallback

Older Hikvision NVR firmware can reject a bounded `/ISAPI/ContentMgmt/download` request when the playback URI has its `name` and `size` selectors removed, while still supporting the documented file-download flow using the original playback URI returned by `/ISAPI/ContentMgmt/search`.

Gateway order:
1. bounded HTTP-by-time download;
2. original search playback URI file download (preserving `name`/`size`), then exact local trim;
3. bounded RTSP playback only as the final fallback.

This avoids depending on legacy HEVC RTP packetization when the NVR can export the recording file directly.
