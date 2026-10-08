#!/usr/bin/env bash
# Environmental pre-flight for humans and agents.
#
#   ./tools/doctor.sh
#
# Run from anywhere. Exits 0 when the core Rust checks can run, non-zero
# when something they need is missing. Flutter, Xvfb, Poppler and xdotool
# are reported as warnings rather than failures: a Rust-only change does not
# need them, but a Flutter, integration or export change does.
#
# This is deliberately agent-agnostic (plain bash, no new dependencies):
# any agent or human runs the same command and reads the same output.
set -uo pipefail

errors=0
warnings=0

ok() { printf 'ok: %s\n' "$1"; }
warn() { printf 'warning: %s\n' "$1"; warnings=$((warnings + 1)); }
fail() { printf 'error: %s\n' "$1"; errors=$((errors + 1)); }

command_present() { command -v "$1" >/dev/null 2>&1; }

# Core: Rust, cargo components, Python.
if command_present cargo; then
  ok "cargo $(cargo --version 2>/dev/null | head -n 1)"
else
  fail "cargo not found on PATH"
fi

if command_present rustc; then
  rustc_version=$(rustc --version 2>/dev/null)
  ok "$rustc_version"
  # Workspace floor is Cargo.toml rust-version = "1.85" (see AGENTS.md).
  # Compare major.minor numerically without external tools.
  ver=$(printf '%s' "$rustc_version" | sed -n 's/.* \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p')
  # shellcheck disable=SC2086
  set -- $ver
  if [ "$#" -eq 2 ]; then
    if [ "$1" -lt 1 ] || { [ "$1" -eq 1 ] && [ "$2" -lt 85 ]; }; then
      warn "rustc is older than the workspace floor 1.85 (CI's msrv job builds on exactly 1.85.0)"
    fi
  fi
else
  fail "rustc not found on PATH"
fi

if cargo fmt --version >/dev/null 2>&1; then
  ok "cargo fmt present"
else
  fail "cargo fmt component missing (rustup component add rustfmt)"
fi

if cargo clippy --version >/dev/null 2>&1; then
  ok "cargo clippy present"
else
  fail "cargo clippy component missing (rustup component add clippy)"
fi

if command_present python3; then
  ok "python3 $(python3 --version 2>&1)"
else
  fail "python3 not found on PATH (needed for tools/check_*.py)"
fi

# Flutter toolchain (pinned to 3.44.8 by CI; see AGENTS.md).
if command_present flutter; then
  flutter_version=$(flutter --version 2>/dev/null | head -n 1)
  ok "flutter $flutter_version"
  case "$flutter_version" in
    *3.44.8*) ;;
    *) warn "flutter is not the pinned 3.44.8; app/pubspec.lock belongs to 3.44.8 and a newer SDK rewrites four pins (see BACKLOG B6)" ;;
  esac
  if command_present dart; then
    ok "dart $(dart --version 2>&1 | head -n 1)"
  else
    warn "dart not found on PATH even though flutter is present"
  fi
else
  warn "flutter not found on PATH; Flutter checks, codegen and Linux builds are unavailable"
fi

# Optional but required for specific suites.
if command_present xvfb-run; then
  ok "xvfb-run present (Linux integration tests)"
else
  warn "xvfb-run not found; ./tools/test_linux_integration.sh cannot run"
fi

for tool in pdftotext pdftohtml; do
  if command_present "$tool"; then
    ok "$tool present (export/PDF text-extraction tests)"
  else
    warn "$tool not found; export tests fail without poppler-utils (see BACKLOG B9)"
  fi
done

if command_present xdotool; then
  ok "xdotool present (runtime budget and clean-close harnesses)"
else
  warn "xdotool not found; tools/check_runtime_budgets.py and tools/check_clean_close.py cannot drive the release window"
fi

# Bridge codegen helpers (only needed when touching crates/bridge/src/api/).
if command_present flutter_rust_bridge_codegen; then
  ok "flutter_rust_bridge_codegen present"
else
  warn "flutter_rust_bridge_codegen not found; needed only after changing crates/bridge/src/api/ (cargo install flutter_rust_bridge_codegen cargo-expand)"
fi

if command_present cargo-expand; then
  ok "cargo-expand present"
else
  warn "cargo-expand not found; needed only for bridge codegen"
fi

printf '\n%d error(s), %d warning(s)\n' "$errors" "$warnings"
[ "$errors" -eq 0 ]
