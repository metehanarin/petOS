#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_DIR="${PETOS_RELEASE_BUNDLE_DIR:-/private/tmp/petOS-release/petOS.app}"

# shellcheck source=tools/_bundle.sh
source "$SCRIPT_DIR/_bundle.sh"

rm -rf "$BUNDLE_DIR"
build_bundle release "$BUNDLE_DIR"

echo "[bundle] release app: $BUNDLE_DIR"
echo "[bundle] first run note: macOS may ask for confirmation because this app is ad-hoc signed."
