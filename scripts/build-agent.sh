#!/usr/bin/env bash
# Builds the signed remote-support agent (agent/) into dist/remote-support-agent-<version>.apk.
# Needs JDK 17 and the Android SDK (platform 33). The signing key stays outside the
# repo: see agent/README-LTS.md ("Signing").
set -euo pipefail
cd "$(dirname "$0")/.."

: "${JAVA_HOME:=$(/usr/libexec/java_home -v 17 2>/dev/null || echo /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home)}"
: "${ANDROID_HOME:=${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
export JAVA_HOME ANDROID_HOME
SIGNING="${AGENT_SIGNING_PROPERTIES:-$HOME/.config/remote-support/agent-signing.properties}"
[[ -f "$SIGNING" ]] || { echo "No signing properties at $SIGNING (see agent/README-LTS.md)" >&2; exit 1; }

cd agent
[[ -f local.properties ]] || echo "sdk.dir=$ANDROID_HOME" > local.properties
sh ./gradlew -q clean assembleRelease
cd ..

version="$(sed -n 's/.*versionName "\(.*\)".*/\1/p' agent/app/build.gradle)"
mkdir -p dist
out="dist/remote-support-agent-$version.apk"
cp agent/app/build/outputs/apk/release/app-release.apk "$out"
apksigner="$(ls -d "$ANDROID_HOME"/build-tools/*/ | sort -V | tail -1)apksigner"
"$apksigner" verify --print-certs "$out" | grep -m1 'SHA-256'   # fails the build if unsigned
echo "Built $out"
