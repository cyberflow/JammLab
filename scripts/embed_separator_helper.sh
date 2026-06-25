#!/usr/bin/env bash
set -euo pipefail

if [[ "${SKIP_BUNDLED_SEPARATOR_HELPER:-}" == "1" ]]; then
  echo "warning: skipping bundled separator helper embed because SKIP_BUNDLED_SEPARATOR_HELPER=1"
  exit 0
fi

SOURCE_DIR="$SRCROOT/build/JammLabSeparatorHelper/dist/JammLabSeparatorHelper"
DEST_DIR="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Resources/JammLabSeparatorHelper"
LEGACY_DEST_DIR="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/JammLabSeparatorHelper"
REQUIRED_MODELS="htdemucs.yaml htdemucs_6s.yaml UVR-MDX-NET-Inst_HQ_5.onnx"
MANIFEST="$SOURCE_DIR/_internal/bundled-model-cache/jammlab-models.txt"

if [[ ! -x "$SOURCE_DIR/JammLabSeparatorHelper" ]]; then
  echo "error: missing bundled separator helper at $SOURCE_DIR. Run scripts/build_separator_helper.sh before building JammLab." >&2
  exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "error: bundled separator helper model manifest is missing. Run scripts/build_separator_helper.sh before building JammLab." >&2
  exit 1
fi

for model in $REQUIRED_MODELS; do
  if ! grep -qx "$model" "$MANIFEST"; then
    echo "error: bundled separator helper is missing required model $model. Run scripts/build_separator_helper.sh before building JammLab." >&2
    exit 1
  fi
done

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
