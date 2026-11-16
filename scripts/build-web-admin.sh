#!/usr/bin/env bash
# Builds the Headwind Remote web console into ./generated/web-admin (served by nginx).
# Upstream builds it with gulp, which only concatenates and minifies; plain
# concatenation in the same order gives the same app without a Node toolchain.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=vendor/headwind-remote-server/web-admin
OUT=generated/web-admin
rm -rf "$OUT"
mkdir -p "$OUT/dist/js" "$OUT/dist/css"

# Same file lists and order as $SRC/gulpfile.js.
cat "$SRC"/js/lib/{jquery-3.3.1,bootstrap-4.3.1,adapter-6.4.0,popper-2.5.3,bootbox-5.4.0}.min.js \
    "$SRC"/js/lib/toastr.min.js > "$OUT/dist/js/deps.min.js"
cat "$SRC"/js/{janus,utils,debug-utils,cheat-codes,keyboard,clipboard,session-monitoring,ui,remote-chat,commands,remote-video,video-stats,gesture-builder,remote-admin}.js \
    > "$OUT/dist/js/app.min.js"
cat "$SRC"/css/lib/{bootstrap-4.3.1,font-awesome-4.6.2,toastr}.min.css > "$OUT/dist/css/deps.min.css"
cat "$SRC"/css/{main,loader}.css > "$OUT/dist/css/app.min.css"
cp -R "$SRC/static" "$OUT/static"
cp "$SRC/index.html" "$OUT/index.html"

# Settings (Janus URLs + API secret) from the environment; see remote/web-admin.
envsubst '${JANUS_API_SECRET}' < remote/web-admin/settings.js.tmpl > "$OUT/dist/js/settings.js"
echo "Web console built in $OUT"
