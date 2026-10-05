#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_SHA="eeb3e67d11a83a02ba1f408fde8df1ca73218037"
python -m pip install --upgrade pip
python -m pip install -r camera_bridge/requirements.txt
rm -rf .okam-src
git clone --filter=blob:none https://github.com/oleandor/okam-ha-native.git .okam-src
git -C .okam-src checkout "$UPSTREAM_SHA"
python .okam-src/tools/fetch_official_sdk.py --wake-only --destination camera_bridge/vendor
cp .okam-src/native/amd64_connect/okam-amd64-connect camera_bridge/okam-amd64-connect
chmod 0755 camera_bridge/okam-amd64-connect
python - <<'PY'
import imageio_ffmpeg
print('ffmpeg=' + imageio_ffmpeg.get_ffmpeg_exe())
PY
