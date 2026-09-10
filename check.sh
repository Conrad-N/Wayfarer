#!/usr/bin/env bash
# The one command that proves the project is healthy. Run it before every commit.
#   ./check.sh            import + tests
#   ./check.sh --quick    tests only (skip re-import)
# Needs `godot` on PATH (Godot 4.7.x). See AGENTS.md "Setup".
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null; then
  echo "godot not found on PATH. See AGENTS.md > Setup." >&2
  exit 2
fi
if [[ "${1:-}" != "--quick" ]]; then
  echo "== import"
  "$GODOT" --headless --path godot --import >/dev/null 2>godot-import.log || { cat godot-import.log; exit 1; }
  rm -f godot-import.log
fi
echo "== tests"
"$GODOT" --headless --path godot -s tests/run_tests.gd
