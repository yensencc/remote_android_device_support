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

# join SEP FILE...: concatenate with SEP after each file. Several upstream files end
# without a newline (or with a "//# sourceMappingURL" comment), so plain cat would
# glue the next file onto that line and break it; gulp-concat adds the separator too.
join() {
  local sep="$1"; shift
  for f in "$@"; do cat "$f"; printf '%b' "$sep"; done
}

# Same file lists and order as $SRC/gulpfile.js.
join '\n;\n' "$SRC"/js/lib/{jquery-3.3.1,bootstrap-4.3.1,adapter-6.4.0,popper-2.5.3,bootbox-5.4.0}.min.js \
    "$SRC"/js/lib/toastr.min.js > "$OUT/dist/js/deps.min.js"
join '\n;\n' "$SRC"/js/{janus,utils,debug-utils,cheat-codes,keyboard,clipboard,session-monitoring,ui,remote-chat,commands,remote-video,video-stats,gesture-builder,remote-admin}.js \
    > "$OUT/dist/js/app.min.js"
join '\n' "$SRC"/css/lib/{bootstrap-4.3.1,font-awesome-4.6.2,toastr}.min.css > "$OUT/dist/css/deps.min.css"
join '\n' "$SRC"/css/{main,loader}.css > "$OUT/dist/css/app.min.css"
cp -R "$SRC/static" "$OUT/static"
cp "$SRC/index.html" "$OUT/index.html"

# Settings (Janus URLs + API secret) from the environment; see remote/web-admin.
envsubst '${JANUS_API_SECRET}' < remote/web-admin/settings.js.tmpl > "$OUT/dist/js/settings.js"
# Fail the build (not the browser) if concatenation produced invalid JavaScript.
if command -v node >/dev/null; then
  for f in "$OUT"/dist/js/*.js; do node --check "$f" || { echo "invalid JS: $f" >&2; exit 1; }; done
fi
echo "Web console built in $OUT"
