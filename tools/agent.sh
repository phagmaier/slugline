#!/usr/bin/env bash
# One entry point for the checks AGENTS.md lists, so humans and agents of any
# kind run the same commands with the same flags.
#
#   ./tools/agent.sh doctor              # environment pre-flight
#   ./tools/agent.sh quick <crate>       # one Rust crate: fountain|fdx|document|layout|render_pdf|storage|spell|bridge
#   ./tools/agent.sh docs                # layering + version + docs + reference checks (fast, no build)
#   ./tools/agent.sh lint                # cargo fmt check + clippy (slower, whole workspace)
#   ./tools/agent.sh backlog-next        # first unticked, non-blocked BACKLOG item
#   ./tools/agent.sh bindings            # regenerate bridge bindings to temp and diff (minutes)
#   ./tools/agent.sh regen               # print the golden-regeneration commands (does not run them)
#
# Run from anywhere. Thin wrapper only: the underlying tools remain the
# authority, this script only fixes their invocation. Prefer it over
# re-deriving flags from prose.
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

usage() {
  sed -n '2,/^$/p' "$ROOT/tools/agent.sh" | sed 's/^# \?//'
}

cmd=${1:-help}
case "$cmd" in
  doctor)
    exec "$ROOT/tools/doctor.sh"
    ;;
  quick)
    crate=${2:-}
    case "$crate" in
      fountain|fdx|document|layout|render_pdf|storage|spell|bridge) ;;
      *)
        echo "usage: tools/agent.sh quick <crate>" >&2
        echo "crates: fountain fdx document layout render_pdf storage spell bridge" >&2
        exit 2
        ;;
    esac
    exec cargo test -p "slugline_$crate"
    ;;
  docs)
    set -e
    python3 "$ROOT/tools/check_layering.py"
    python3 "$ROOT/tools/check_version.py"
    python3 "$ROOT/tools/check_docs.py"
    python3 "$ROOT/tools/make_reference.py" --check
    ;;
  lint)
    set -e
    cargo fmt --all --check
    cargo clippy --workspace --all-targets -- -D warnings
    ;;
  backlog-next)
    exec python3 "$ROOT/tools/backlog.py" next
    ;;
  bindings)
    exec "$ROOT/tools/check_bridge_bindings.sh"
    ;;
  regen)
    cat <<'EOF'
Golden regeneration rewrites committed fixtures. Run one only on purpose,
and say in the commit message whether the change was deliberate (AGENTS.md).
EOF
    echo
    echo "UPDATE_LAYOUT_GOLDENS=1 cargo test -p slugline_layout --test golden"
    echo "UPDATE_PDF_HASHES=1 cargo test -p slugline_render_pdf --test golden"
    echo "UPDATE_LINE_BREAK_FIXTURES=1 cargo test -p slugline_layout --test line_break_differential"
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    echo "unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
