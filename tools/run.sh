#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_DIR="$REPO_ROOT/.build/bundle/PetNative.app"
APP_BINARY="$BUNDLE_DIR/Contents/MacOS/PetNative"

clean=false
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      clean=true
      shift
      ;;
    --)
      shift
      args=("$@")
      break
      ;;
    *)
      echo "usage: $0 [--clean] [-- <args...>]" >&2
      exit 2
      ;;
  esac
done

if [[ "$clean" == true ]]; then
  rm -rf "$BUNDLE_DIR"
fi

# shellcheck source=tools/_bundle.sh
source "$SCRIPT_DIR/_bundle.sh"

bundle_mode=""
if [[ -f "$BUNDLE_DIR/Contents/Info.plist" ]]; then
  fingerprint_file="$BUNDLE_DIR/Contents/Resources/.petnative-resource-fingerprint"
  resource_bundle="$BUNDLE_DIR/Contents/Resources/PetNative_PetNative.bundle"
  current_fingerprint="$(resource_fingerprint)"
  stored_fingerprint=""
  if [[ -f "$fingerprint_file" ]]; then
    stored_fingerprint="$(<"$fingerprint_file")"
  fi

  if [[ "$stored_fingerprint" == "$current_fingerprint" ]] && validate_packaged_resources "$resource_bundle"; then
    bundle_mode="--inner-only"
  else
    bundle_log "resource state changed; rebuilding app resources"
  fi
fi

if [[ -n "$bundle_mode" ]]; then
  build_bundle debug "$BUNDLE_DIR" "$bundle_mode"
else
  build_bundle debug "$BUNDLE_DIR"
fi

# Launch via `open` so Launch Services registers the bundle and TCC can read Info.plist.
# Running the inner binary directly bypasses LS, which makes TCC reject privacy-sensitive
# APIs (e.g. INFocusStatusCenter) with a crash even when Info.plist contains the keys.
if [[ ${#args[@]} -gt 0 ]]; then
  exec /usr/bin/open -W "$BUNDLE_DIR" --args "${args[@]}"
else
  exec /usr/bin/open -W "$BUNDLE_DIR"
fi
