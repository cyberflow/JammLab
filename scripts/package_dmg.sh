#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: scripts/package_dmg.sh <app-path> <output-dmg>" >&2
  exit 64
fi

APP_PATH="$1"
OUTPUT_DMG="$2"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found: $APP_PATH" >&2
  exit 66
fi

if [[ "${APP_PATH##*.}" != "app" ]]; then
  echo "error: app path must point to a .app bundle: $APP_PATH" >&2
  exit 65
fi

APP_NAME="$(basename "$APP_PATH")"
OUTPUT_DIR="$(dirname "$OUTPUT_DMG")"
DMG_NAME="$(basename "$OUTPUT_DMG")"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DMG"

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/jammlab-dmg.XXXXXX")"
cleanup() {
  rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

DMG_ROOT="$STAGING_ROOT/dmgroot"
mkdir -p "$DMG_ROOT"

ditto "$APP_PATH" "$DMG_ROOT/$APP_NAME"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "JammLab" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$OUTPUT_DIR/$DMG_NAME"

echo "Created $OUTPUT_DMG"
