#!/usr/bin/env bash
set -euo pipefail

if [[ "${SKIP_BUNDLED_SEPARATOR_HELPER:-}" == "1" ]]; then
  echo "warning: skipping bundled separator helper embed because SKIP_BUNDLED_SEPARATOR_HELPER=1"
  exit 0
fi

SOURCE_DIR="$SRCROOT/build/JammLabSeparatorHelper/dist/JammLabSeparatorHelper"
DEST_DIR="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Resources/JammLabSeparatorHelper"
LEGACY_DEST_DIR="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/JammLabSeparatorHelper"

if [[ ! -x "$SOURCE_DIR/JammLabSeparatorHelper" ]]; then
  echo "error: missing bundled separator helper at $SOURCE_DIR. Run scripts/build_separator_helper.sh before building JammLab." >&2
  exit 1
fi

if ! CAPABILITIES_JSON="$("$SOURCE_DIR/JammLabSeparatorHelper" --capabilities_json 2>&1)"; then
  echo "error: bundled separator helper is stale or incompatible and cannot publish protocol capabilities." >&2
  echo "error: rebuild it with scripts/build_separator_helper.sh before building JammLab." >&2
  printf '%s\n' "$CAPABILITIES_JSON" >&2
  exit 1
fi

if [[ -z "$CAPABILITIES_JSON" || "$CAPABILITIES_JSON" != \{* ]] ||
  ! printf '%s' "$CAPABILITIES_JSON" | /usr/bin/plutil -convert json -o /dev/null - >/dev/null 2>&1; then
  echo "error: bundled separator helper returned invalid capability JSON. Run scripts/build_separator_helper.sh before building JammLab." >&2
  printf '%s\n' "$CAPABILITIES_JSON" >&2
  exit 1
fi

rm -rf "$DEST_DIR" "$LEGACY_DEST_DIR"
mkdir -p "$(dirname "$DEST_DIR")"
cp -R "$SOURCE_DIR" "$DEST_DIR"
find "$DEST_DIR" -type f -name "*.py" -exec perl -i -0pe 's/\A#![^\n]*\n//' {} +

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi

while IFS= read -r file; do
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$file"
done < <(find "$DEST_DIR" -type f \( -perm -111 -o -name "*.so" -o -name "*.dylib" \))
