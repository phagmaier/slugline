#!/usr/bin/env bash
# Fail when the bridge bindings do not match the bridge sources.
#
#   ./tools/check_bridge_bindings.sh
#
# Run from anywhere, including mid-change with uncommitted edits. Regenerates
# the bindings from crates/bridge/src/api/ into a temporary directory inside
# app/ (the generator refuses an output outside the Dart package) and diffs it
# against app/lib/src/rust/, ignoring *.freezed.dart, which build_runner owns.
#
# The documented `flutter_rust_bridge_codegen generate` also refreshes Rust
# glue and freezed files in place, so this check snapshots those tracked
# files first and restores them byte-for-byte afterwards: a stale verdict
# never leaves a half-regenerated tree behind, and your own uncommitted edits
# are never touched. New files codegen may leave behind are reported, not
# deleted.
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
APP="$ROOT/app"
COMMITTED="$APP/lib/src/rust"
YAML="$APP/flutter_rust_bridge.yaml"
# Tracked files codegen is known to write besides its Dart output.
SNAPSHOT_PATHS="app/lib/src/rust crates/bridge/src app/pubspec.lock"

for tool in git flutter_rust_bridge_codegen cargo-expand dart flutter tar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'error: required command not found: %s\n' "$tool" >&2
    exit 1
  fi
done

CFG=$(mktemp -p "$APP" .frb-stale-check.XXXXXX.yaml)
OUT=$(mktemp -d -p "$APP" .frb-stale-check-out.XXXXXX)
LOG=$(mktemp -t slugline-frb-check.XXXXXX.log)
SNAP=$(mktemp -t slugline-frb-snap.XXXXXX.tar)
cleanup() { rm -rf "$CFG" "$OUT" "$LOG" "$SNAP"; }
trap cleanup EXIT

# Snapshot tracked files under the guarded paths (contents only).
# shellcheck disable=SC2086
git -C "$ROOT" ls-files -- $SNAPSHOT_PATHS | tar -cf "$SNAP" -C "$ROOT" -T -
# Record which files exist there now, to spot anything codegen adds.
# shellcheck disable=SC2086
before=$(git -C "$ROOT" status --porcelain -- $SNAPSHOT_PATHS)

sed 's|^dart_output:.*|dart_output: '"$OUT"'|' "$YAML" >"$CFG"

restore() { tar -xf "$SNAP" -C "$ROOT"; }

if (cd "$APP" && flutter_rust_bridge_codegen generate --config-file "$(basename "$CFG")" >"$LOG" 2>&1); then
  printf 'codegen ran\n'
else
  printf 'error: codegen failed:\n' >&2
  tail -n 20 "$LOG" >&2
  restore
  exit 1
fi

failures=0

if diff -r -x '*.freezed.dart' "$OUT" "$COMMITTED"; then
  printf 'bindings match app/lib/src/rust/\n'
else
  printf 'error: bindings are stale for the current bridge sources; regenerate:\n' >&2
  printf '  cd app && flutter_rust_bridge_codegen generate\n' >&2
  failures=1
fi

# Anything codegen changed or added in the real tree means the committed
# freezed files, glue or lockfile were stale too. Report only the delta
# against the pre-run state, so the caller's own uncommitted edits are not
# blamed on codegen.
# shellcheck disable=SC2086
after=$(git -C "$ROOT" status --porcelain -- $SNAPSHOT_PATHS)
delta=$(grep -Fxvf <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true)
if [ -n "$delta" ]; then
  printf 'error: codegen touched the tree besides its redirected output:\n%s\n' "$delta" >&2
  failures=1
fi
restore

# Confirm the restore held (paranoia: our own uncommitted edits must survive).
# shellcheck disable=SC2086
final=$(git -C "$ROOT" status --porcelain -- $SNAPSHOT_PATHS)
if [ "$final" != "$before" ]; then
  printf 'error: snapshot restore did not hold; investigate before committing:\n%s\n' "$final" >&2
  exit 1
fi

[ "$failures" -eq 0 ]
