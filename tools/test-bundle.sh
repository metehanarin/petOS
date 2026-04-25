#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_DIR="$REPO_ROOT/.build/bundle/PetNative.app"
APP_BINARY="$BUNDLE_DIR/Contents/MacOS/PetNative"
INFO_PLIST="$BUNDLE_DIR/Contents/Info.plist"
EXPECTED_BUNDLE_ID="com.petnative.PetNative"

# shellcheck source=tools/_bundle.sh
source "$SCRIPT_DIR/_bundle.sh"

rm -rf "$BUNDLE_DIR"
build_bundle debug "$BUNDLE_DIR"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "[bundle] error: missing Info.plist" >&2
  exit 1
fi
echo "[bundle] OK Info.plist"

if [[ ! -x "$APP_BINARY" ]]; then
  echo "[bundle] error: missing executable: $APP_BINARY" >&2
  exit 1
fi
echo "[bundle] OK executable"

codesign --verify --deep --strict "$BUNDLE_DIR"
echo "[bundle] OK codesign"

actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
if [[ "$actual_bundle_id" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "[bundle] error: CFBundleIdentifier was $actual_bundle_id, expected $EXPECTED_BUNDLE_ID" >&2
  exit 1
fi
echo "[bundle] OK bundle identifier"

echo "[bundle] PASS"
