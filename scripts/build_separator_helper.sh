#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_DIR="$ROOT_DIR/JammLabSeparatorHelper"
BUILD_DIR="$ROOT_DIR/build/JammLabSeparatorHelper"
VENV_DIR="$BUILD_DIR/venv"
DIST_DIR="$BUILD_DIR/dist"
MODEL_CACHE_DIR="$BUILD_DIR/model-cache"
HELPER_MANIFEST="$HELPER_DIR/helper-manifest.json"
PYINSTALLER_CONFIG_DIR="$BUILD_DIR/pyinstaller-config"
PYTHON_BIN="${PYTHON_BIN:-python3}"

# Check before changing any existing build output.
"$PYTHON_BIN" "$ROOT_DIR/scripts/check_separator_dependencies.py" --check-platform

mkdir -p "$BUILD_DIR" "$PYINSTALLER_CONFIG_DIR"
export PYINSTALLER_CONFIG_DIR

# Never reuse an environment from another Python installation or dependency set.
"$PYTHON_BIN" -m venv --clear "$VENV_DIR"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-$BUILD_DIR/pip-cache}"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTHONNOUSERSITE=1
LOCK_FILE="$HELPER_DIR/requirements-macos-arm64.lock"
PIP_PIN="$(sed -n '/^pip==/p' "$LOCK_FILE")"
"$VENV_DIR/bin/python" -m pip install --no-deps "$PIP_PIN"
"$VENV_DIR/bin/python" -m pip install --no-deps \
  --build-constraint "$HELPER_DIR/build-constraints.txt" -r "$LOCK_FILE"
"$VENV_DIR/bin/python" -m pip check
"$VENV_DIR/bin/python" "$ROOT_DIR/scripts/check_separator_dependencies.py" --check-environment
mkdir -p "$BUILD_DIR/reports"
"$VENV_DIR/bin/python" -m pip freeze --all > "$BUILD_DIR/reports/installed-packages.txt"

mkdir -p "$MODEL_CACHE_DIR"
SEPARATOR_MODELS="$("$PYTHON_BIN" -c 'import json,sys; print(" ".join(model["name"] for model in json.load(open(sys.argv[1]))["models"]))' "$HELPER_MANIFEST")"
for model in $SEPARATOR_MODELS; do
  "$VENV_DIR/bin/python" "$HELPER_DIR/runner.py" \
    --prefetch_model "$model" \
    --model_file_dir "$MODEL_CACHE_DIR"
  "$VENV_DIR/bin/python" "$HELPER_DIR/runner.py" \
    --validate_model_cache "$model" \
    --model_file_dir "$MODEL_CACHE_DIR"
done

rm -rf "$DIST_DIR" "$BUILD_DIR/work" "$PYINSTALLER_CONFIG_DIR"
mkdir -p "$PYINSTALLER_CONFIG_DIR"
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
"$HELPER_EXEC" --capabilities_json
echo "Built $DIST_DIR/JammLabSeparatorHelper"
