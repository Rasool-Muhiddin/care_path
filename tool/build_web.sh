#!/usr/bin/env bash
# Production build of the PWA, served at https://axon.tera-software1.com/app/
#
#   bash tool/build_web.sh        → build/web  (+ build/axon-web.tar.gz to upload)
#
# - --base-href /app/         : the app lives under /app/ (nginx: deploy/nginx-axon.conf)
# - --no-web-resources-cdn    : CanvasKit is served from our own server, not gstatic
# - web_firebase.json         : Firebase web config for push (optional; see
#                               web_firebase.example.json). Without it: no push.
set -euo pipefail
# Git Bash (Windows) would otherwise rewrite "/app/" into "C:/Program Files/Git/app/"
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."

defines=()
if [[ -f web_firebase.json ]]; then
  defines+=(--dart-define-from-file=web_firebase.json)
else
  echo "WARNING: web_firebase.json not found — building WITHOUT web push notifications." >&2
fi

flutter build web --release \
  --base-href /app/ \
  --no-web-resources-cdn \
  --no-source-maps \
  --no-wasm-dry-run \
  "${defines[@]}"

# Renderer variants the JS build never loads (only canvaskit/canvaskit.* and
# canvaskit/chromium/* are fetched); dropping them keeps the upload small.
rm -f build/web/canvaskit/skwasm* build/web/canvaskit/wimp* build/web/canvaskit/*.symbols \
      build/web/canvaskit/chromium/*.symbols
rm -rf build/web/canvaskit/experimental_webparagraph

tar -czf build/axon-web.tar.gz -C build web
echo "Built build/web and build/axon-web.tar.gz"
