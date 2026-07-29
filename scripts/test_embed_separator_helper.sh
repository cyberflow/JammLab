#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"

cleanup() {
  if [[ -n "${TEST_ROOT:-}" && -d "$TEST_ROOT" ]]; then
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup EXIT

HELPER_DIR="$TEST_ROOT/build/JammLabSeparatorHelper/dist/JammLabSeparatorHelper"
DEST_DIR="$TEST_ROOT/target/JammLab.app/Contents/Resources/JammLabSeparatorHelper"
mkdir -p "$HELPER_DIR"

FAKE_HELPER="$HELPER_DIR/JammLabSeparatorHelper"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'case "${FAKE_HELPER_MODE:?}" in' \
  '  stale)' \
  '    printf "%s\n" "JammLabSeparatorHelper: error: unrecognized arguments: --capabilities_json" >&2' \
  '    exit 2' \
  '    ;;' \
  '  invalid)' \
  '    printf "%s\n" "{broken"' \
  '    ;;' \
  '  valid)' \
  '    printf "%s\n" "{\"protocolVersion\":6}"' \
  '    ;;' \
  'esac' > "$FAKE_HELPER"
chmod +x "$FAKE_HELPER"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local output="$1"
  local expected="$2"
  [[ "$output" == *"$expected"* ]] || fail "expected output to contain: $expected"
}

run_failure_case() {
  local mode="$1"
  local output
  local status
  local sentinel="$DEST_DIR/existing-helper"

  mkdir -p "$DEST_DIR"
  printf 'preserve me\n' > "$sentinel"

  set +e
  output="$(
    SRCROOT="$TEST_ROOT" \
      TARGET_BUILD_DIR="$TEST_ROOT/target" \
      CONTENTS_FOLDER_PATH="JammLab.app/Contents" \
      FAKE_HELPER_MODE="$mode" \
      SKIP_BUNDLED_SEPARATOR_HELPER=0 \
      bash "$ROOT_DIR/scripts/embed_separator_helper.sh" 2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "$mode helper unexpectedly succeeded"
  [[ -f "$sentinel" ]] || fail "$mode helper removed the existing destination"
  [[ "$(< "$sentinel")" == "preserve me" ]] || fail "$mode helper mutated the existing destination"
  printf '%s' "$output"
}

stale_output="$(run_failure_case stale)"
assert_contains "$stale_output" "bundled separator helper is stale or incompatible"
assert_contains "$stale_output" "scripts/build_separator_helper.sh"
assert_contains "$stale_output" "unrecognized arguments: --capabilities_json"

invalid_output="$(run_failure_case invalid)"
assert_contains "$invalid_output" "bundled separator helper returned invalid capability JSON"
assert_contains "$invalid_output" "scripts/build_separator_helper.sh"
assert_contains "$invalid_output" "{broken"

SRCROOT="$TEST_ROOT" \
  TARGET_BUILD_DIR="$TEST_ROOT/target" \
  CONTENTS_FOLDER_PATH="JammLab.app/Contents" \
  FAKE_HELPER_MODE=valid \
  SKIP_BUNDLED_SEPARATOR_HELPER=0 \
  bash "$ROOT_DIR/scripts/embed_separator_helper.sh"
[[ -x "$DEST_DIR/JammLabSeparatorHelper" ]] || fail "valid helper was not embedded"

printf 'embed_separator_helper tests passed\n'
