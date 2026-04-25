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

bundle_mode=()
if [[ -f "$BUNDLE_DIR/Contents/Info.plist" ]]; then
  bundle_mode=(--inner-only)
fi

build_bundle debug "$BUNDLE_DIR" "${bundle_mode[@]}"

exec "$APP_BINARY" "${args[@]}"
