#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
APP="$ROOT/app"

# pdftotext and pdftohtml: export_test.dart reads its PDFs back through them.
for tool in flutter xvfb-run pdftotext pdftohtml; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'error: required command not found: %s\n' "$tool" >&2
    exit 1
  fi
done

TEST_FILES=(
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
[ "$EXPECTED_COUNT" -eq "${#TEST_FILES[@]}" ] || {
  printf 'error: update tools/test_linux_integration.sh for all integration tests\n' >&2
  exit 1
}

for test_file in "${TEST_FILES[@]}"; do
  [ -f "$APP/$test_file" ] || {
    printf 'error: integration test not found: %s\n' "$test_file" >&2
    exit 1
  }
  printf '\n==> %s\n' "$test_file"
  (
    cd "$APP"
    xvfb-run -a flutter test "$test_file" -d linux
  )
done
