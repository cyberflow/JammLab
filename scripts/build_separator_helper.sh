#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_DIR="$ROOT_DIR/JammLabSeparatorHelper"
BUILD_DIR="$ROOT_DIR/build/JammLabSeparatorHelper"
VENV_DIR="$BUILD_DIR/venv"
DIST_DIR="$BUILD_DIR/dist"
MODEL_CACHE_DIR="$BUILD_DIR/model-cache"
MODEL_MANIFEST="$MODEL_CACHE_DIR/jammlab-models.txt"
PYINSTALLER_CONFIG_DIR="$BUILD_DIR/pyinstaller-config"
PYTHON_BIN="${PYTHON_BIN:-python3}"
SEPARATOR_MODELS="${SEPARATOR_MODELS:-htdemucs.yaml htdemucs_6s.yaml UVR-MDX-NET-Inst_HQ_5.onnx}"

mkdir -p "$BUILD_DIR" "$PYINSTALLER_CONFIG_DIR"
export PYINSTALLER_CONFIG_DIR

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/python" -m pip install --upgrade pip "setuptools<82" wheel
"$VENV_DIR/bin/python" -m pip install -r "$HELPER_DIR/requirements.txt"

mkdir -p "$MODEL_CACHE_DIR"
for model in $SEPARATOR_MODELS; do
  "$VENV_DIR/bin/python" "$HELPER_DIR/runner.py" \
    --prefetch_model "$model" \
    --model_file_dir "$MODEL_CACHE_DIR"
  "$VENV_DIR/bin/python" "$HELPER_DIR/runner.py" \
    --validate_model_cache "$model" \
    --model_file_dir "$MODEL_CACHE_DIR"
done
printf "%s\n" $SEPARATOR_MODELS > "$MODEL_MANIFEST"

rm -rf "$DIST_DIR" "$BUILD_DIR/work"
(
  cd "$HELPER_DIR"
  "$VENV_DIR/bin/python" -m PyInstaller \
    --clean \
    --noconfirm \
    --distpath "$DIST_DIR" \
    --workpath "$BUILD_DIR/work" \
    JammLabSeparatorHelper.spec
)

HELPER_EXEC="$DIST_DIR/JammLabSeparatorHelper/JammLabSeparatorHelper"
if [[ ! -x "$HELPER_EXEC" ]]; then
  echo "error: PyInstaller did not produce executable $HELPER_EXEC" >&2
  exit 1
fi

find "$DIST_DIR/JammLabSeparatorHelper" -type f -name "*.py" \
  -exec perl -i -0pe 's/\A#![^\n]*\n//' {} +

"$HELPER_EXEC" --env_info
echo "Built $DIST_DIR/JammLabSeparatorHelper"
