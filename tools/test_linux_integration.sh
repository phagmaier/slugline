#!/usr/bin/env bash
# No arguments: all native suites. One suite/file plus optional Flutter test
# arguments: only that suite. --list: names, without requiring Flutter/Xvfb.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
APP="$ROOT/app"

ALL_TEST_FILES=(
  integration_test/bridge_test.dart
  integration_test/editor_test.dart
  integration_test/writing_test.dart
  integration_test/ime_test.dart
  integration_test/persistence_test.dart
  integration_test/export_test.dart
  integration_test/keystroke_benchmark_test.dart
)

EXPECTED_COUNT="$(
  find "$APP/integration_test" -maxdepth 1 -type f -name '*_test.dart' |
    wc -l
)"
[ "$EXPECTED_COUNT" -eq "${#ALL_TEST_FILES[@]}" ] || {
  printf 'error: update tools/test_linux_integration.sh for all integration tests\n' >&2
  exit 1
}

for test_file in "${ALL_TEST_FILES[@]}"; do
  [ -f "$APP/$test_file" ] || {
    printf 'error: integration test not found: %s\n' "$test_file" >&2
    exit 1
  }
done

TEST_FILES=("${ALL_TEST_FILES[@]}")
TEST_ARGS=()
case "${1:-}" in
  --list)
    for test_file in "${ALL_TEST_FILES[@]}"; do
      suite="${test_file#integration_test/}"
      printf '%s\n' "${suite%_test.dart}"
    done
    exit 0
    ;;
  "") ;;
  *)
    suite="${1#integration_test/}"
    suite="${suite%_test.dart}"
    selected="integration_test/${suite}_test.dart"
    found=false
    for test_file in "${ALL_TEST_FILES[@]}"; do
      if [ "$test_file" = "$selected" ]; then
        found=true
        break
      fi
    done
    if [ "$found" = false ]; then
      printf 'error: unknown native suite: %s (use --list)\n' "$1" >&2
      exit 2
    fi
    TEST_FILES=("$selected")
    shift
    TEST_ARGS=("$@")
    ;;
esac

REQUIRED_TOOLS=(flutter xvfb-run)
for test_file in "${TEST_FILES[@]}"; do
  if [ "$test_file" = integration_test/export_test.dart ]; then
    REQUIRED_TOOLS+=(pdftotext pdftohtml)
  fi
done
for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'error: required command not found: %s\n' "$tool" >&2
    exit 1
  fi
done

for test_file in "${TEST_FILES[@]}"; do
  printf '\n==> %s\n' "$test_file"
  (
    cd "$APP"
    xvfb-run -a flutter test "$test_file" -d linux "${TEST_ARGS[@]}"
  )
done
