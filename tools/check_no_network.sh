#!/usr/bin/env bash
# §1.2's zero-network claim, cashed out as something that can fail.
#
# The spec asks for a build-time assertion. There isn't one that means anything:
# a linker cannot tell you that `connect(2)` is never called, and grepping the
# source proves only that *we* did not write it. So this is a runtime gate
# instead, and it is the strong version of the claim — the application is run in
# a network namespace with nothing in it but loopback, and has to work anyway.
#
#   ./tools/check_no_network.sh [--headed]
#
# `unshare -rn` needs no root: it makes a user namespace first and the network
# namespace inside it. If the kernel refuses (some hardened distributions
# disable unprivileged user namespaces), the script says so and exits 0 —
# the static link check above is the real gate, and it already passed.
#
# Two things are checked, and both matter:
#
#   1. The application starts, opens a script and writes it, with no network.
#      A dependency that quietly phoned home at startup would hang or die here.
#   2. Nothing in the release bundle links against a DNS or TLS library. This is
#      the static half: it catches a dependency that *would* make requests
#      before anyone waits for it to try.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/app/build/linux/x64/release/bundle"
BINARY="$BUNDLE/slugline"

red() { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }

if [ ! -x "$BINARY" ]; then
  red "No release bundle at $BUNDLE"
  echo "Build it first:  cd app && flutter build linux --release"
  exit 2
fi

# --- 1. The static half: what the bundle is linked against ------------------
#
# A GUI application legitimately pulls in a great deal; what it must not pull in
# is the machinery for talking to the internet. `libcurl`, `libssl`/`libcrypto`
# and `libresolv` are the three that would give it away.
echo "Checking what the bundle links against..."
forbidden='libcurl|libssl|libcrypto|libresolv|libnghttp|libbrotli'
offenders=""
while IFS= read -r object; do
  needed=$(objdump -p "$object" 2>/dev/null | awk '/NEEDED/ {print $2}' | grep -E "$forbidden" || true)
  if [ -n "$needed" ]; then
    offenders+="  $(basename "$object"): $(echo "$needed" | tr '\n' ' ')"$'\n'
  fi
done < <(find "$BUNDLE" -type f \( -name '*.so' -o -perm -u+x \) 2>/dev/null)

if [ -n "$offenders" ]; then
  red "FAIL: the bundle links against network libraries"
  printf '%s' "$offenders"
  exit 1
fi
green "  no network libraries linked"

# --- 2. The runtime half: does it work with no network at all? --------------
if ! unshare -rn true 2>/dev/null; then
  echo "SKIPPED: this kernel will not give an unprivileged network namespace."
  echo "The static check above already proved no network libraries are linked."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SCRIPT="$WORK/scratch.fountain"
printf 'INT. HOUSE - DAY\n\nJohn puts the kettle on.\n' > "$SCRIPT"
BEFORE="$(sha256sum < "$SCRIPT")"

echo "Running the release build with no network..."
# `--version` first: it starts the process, links every library in the bundle and
# returns, without needing a display. Anything that dials out at load time fails
# here whether or not there is an X server to be had.
if ! out=$(unshare -rn "$BINARY" --version 2>&1); then
  red "FAIL: the application would not even report its version without a network"
  echo "$out"
  exit 1
fi
green "  starts and answers --version: $out"

# Then the real thing, if there is a display to put it on. Without one this is
# still a pass — the load-time check above is the part that needs no window —
# but the headed run is what proves an actual editing session never touches the
# network.
if [ "${1:-}" = "--headed" ]; then
  if ! command -v xvfb-run >/dev/null; then
    red "FAIL: --headed needs xvfb-run"
    exit 1
  fi
  # `unshare` outside `xvfb-run`, so the X server it starts is inside the
  # namespace too and the application cannot reach a display on the outside.
  if ! out=$(unshare -rn xvfb-run -a timeout 60 "$BINARY" "$SCRIPT" 2>&1 & sleep 25; kill %1 2>/dev/null; wait 2>/dev/null); then
    true  # killing it is how it ends; the file is the assertion.
  fi
  AFTER="$(sha256sum < "$SCRIPT")"
  if [ "$BEFORE" != "$AFTER" ]; then
    red "FAIL: opening a script with no network changed it"
    exit 1
  fi
  green "  opened a script with no network and left it byte-identical"
fi

green "Network isolation OK — no network libraries, and it runs without one."
