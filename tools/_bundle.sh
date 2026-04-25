#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRODUCT_NAME="PetNative"

bundle_log() {
  echo "[bundle] $*"
}

resource_fingerprint() {
  local source_info_plist="$REPO_ROOT/Sources/PetNative/Info.plist"
  local source_resources="$REPO_ROOT/Sources/PetNative/Resources"

  (
    cd "$REPO_ROOT"

    echo "petnative-resource-fingerprint-v2"

    if [[ -f "$source_info_plist" ]]; then
      local hash
      hash="$(shasum -a 256 "Sources/PetNative/Info.plist" | awk '{print $1}')"
      printf 'file %s %s\n' "Sources/PetNative/Info.plist" "$hash"
    else
      echo "missing Sources/PetNative/Info.plist"
    fi

    if [[ -d "$source_resources" ]]; then
      find "Sources/PetNative/Resources" -type f -print | LC_ALL=C sort | while IFS= read -r path; do
        local hash
        hash="$(shasum -a 256 "$path" | awk '{print $1}')"
        printf 'file %s %s\n' "$path" "$hash"
      done
    else
      echo "missing Sources/PetNative/Resources"
    fi
  ) | shasum -a 256 | awk '{print $1}'
}

validate_packaged_resources() {
  if [[ $# -ne 1 ]]; then
    echo "usage: validate_packaged_resources <resource-bundle-dir>" >&2
    return 2
  fi

  local resource_bundle="$1"
  local source_resources="$REPO_ROOT/Sources/PetNative/Resources"

  if [[ ! -d "$resource_bundle" ]]; then
    echo "[bundle] error: missing SwiftPM resource bundle: $resource_bundle" >&2
    return 1
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"

  find "$source_resources" -type f -exec basename {} \; | LC_ALL=C sort -u > "$tmp_dir/source-basenames"
  find "$resource_bundle" -type f -exec basename {} \; | LC_ALL=C sort -u > "$tmp_dir/packaged-basenames"

  if ! comm -23 "$tmp_dir/packaged-basenames" "$tmp_dir/source-basenames" > "$tmp_dir/extra-basenames"; then
    rm -rf "$tmp_dir"
    echo "[bundle] error: failed to compare packaged resources" >&2
    return 1
  fi

  if [[ -s "$tmp_dir/extra-basenames" ]]; then
    echo "[bundle] error: packaged resources not present in source resources:" >&2
    sed 's/^/[bundle]   /' "$tmp_dir/extra-basenames" >&2
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$tmp_dir"
}

build_bundle() {
  if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: build_bundle <debug|release> <bundle-output-dir> [--inner-only]" >&2
    return 2
  fi

  local config="$1"
  local bundle_dir="$2"
  local mode="${3:-}"

  if [[ "$config" != "debug" && "$config" != "release" ]]; then
    echo "[bundle] error: config must be debug or release" >&2
    return 2
  fi

  if [[ -n "$mode" && "$mode" != "--inner-only" ]]; then
    echo "[bundle] error: unknown option: $mode" >&2
    return 2
  fi

  local contents_dir="$bundle_dir/Contents"
  local macos_dir="$contents_dir/MacOS"
  local resources_dir="$contents_dir/Resources"
  local info_plist="$contents_dir/Info.plist"
  local source_info_plist="$REPO_ROOT/Sources/PetNative/Info.plist"
  local resource_bundle_name="${PRODUCT_NAME}_${PRODUCT_NAME}.bundle"
  local app_resource_bundle="$resources_dir/$resource_bundle_name"
  local app_binary="$macos_dir/$PRODUCT_NAME"
  local fingerprint_file="$resources_dir/.petnative-resource-fingerprint"

  local bin_path
  bin_path="$(cd "$REPO_ROOT" && swift build -c "$config" --show-bin-path)"

  local rebuild_inner_only=false
  if [[ "$mode" == "--inner-only" && -f "$info_plist" ]]; then
    rebuild_inner_only=true
  fi

  local processed_bundle="$bin_path/$resource_bundle_name"
  if [[ "$rebuild_inner_only" == false ]]; then
    rm -rf "$processed_bundle"
  fi

  bundle_log "building $PRODUCT_NAME ($config)"
  (cd "$REPO_ROOT" && swift build -c "$config" --product "$PRODUCT_NAME")

  local built_binary="$bin_path/$PRODUCT_NAME"
  if [[ ! -x "$built_binary" ]]; then
    echo "[bundle] error: built binary is not executable: $built_binary" >&2
    return 1
  fi

  bundle_log "assembling $bundle_dir"
  mkdir -p "$macos_dir" "$resources_dir"

  if [[ "$rebuild_inner_only" == false ]]; then
    if [[ ! -f "$source_info_plist" ]]; then
      echo "[bundle] error: missing Info.plist: $source_info_plist" >&2
      return 1
    fi

    cp "$source_info_plist" "$info_plist"

    local processed_resources="$processed_bundle/Contents/Resources"

    rm -rf "$resources_dir" "$bundle_dir/$resource_bundle_name"
    mkdir -p "$resources_dir"

    if [[ -d "$processed_resources" ]]; then
      mkdir -p "$app_resource_bundle/Contents/Resources"
      ditto "$processed_resources" "$app_resource_bundle/Contents/Resources"
      bundle_log "copied processed resource bundle"
    elif [[ -d "$processed_bundle" ]]; then
      ditto "$processed_bundle" "$app_resource_bundle"
      bundle_log "copied processed resource bundle"
    else
      bundle_log "no processed resources found"
    fi

    resource_fingerprint > "$fingerprint_file"
  else
    bundle_log "updating executable only"
  fi

  cp "$built_binary" "$app_binary"
  chmod +x "$app_binary"

  bundle_log "codesigning"
  codesign --force --deep --sign - "$bundle_dir"
  codesign --verify --deep --strict "$bundle_dir"

  bundle_log "ready: $bundle_dir"
}
