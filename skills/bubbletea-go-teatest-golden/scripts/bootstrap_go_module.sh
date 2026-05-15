#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BASH_VERSION:-}" ]]; then
  exec /usr/bin/env bash "$0" "$@"
fi

usage() {
  cat <<USAGE
Usage: $0 --workdir <dir> [--module <name>] [--local-bubbletea <path>] [--skip-tidy]

Defaults:
- GOCACHE=<workdir>/.cache/go-build
- GOMODCACHE=<workdir>/.cache/go-mod
USAGE
}

wd=""
mod_name="parity_tmp"
local_bt=""
skip_tidy=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workdir) wd="$2"; shift 2 ;;
    --module) mod_name="$2"; shift 2 ;;
    --local-bubbletea) local_bt="$2"; shift 2 ;;
    --skip-tidy) skip_tidy=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$wd" ]]; then
  usage
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "error: go not found in PATH" >&2
  exit 1
fi

mkdir -p "$wd"
cd "$wd"

if [[ ! -f go.mod ]]; then
  cat > go.mod <<EOF2
module ${mod_name}

go 1.24

require (
  charm.land/bubbletea/v2 v2.0.0
  charm.land/bubbles/v2 v2.0.0
  charm.land/lipgloss/v2 v2.0.0
  github.com/charmbracelet/x/exp/teatest v0.0.0-20241212170349-ad4b7ae0f25f
  github.com/charmbracelet/x/exp/golden v0.0.0-20241212170349-ad4b7ae0f25f
)
EOF2

  if [[ -n "$local_bt" ]]; then
    printf '\nreplace charm.land/bubbletea/v2 => %s\n' "$local_bt" >> go.mod
  fi
fi

export GOCACHE="${GOCACHE:-$wd/.cache/go-build}"
export GOMODCACHE="${GOMODCACHE:-$wd/.cache/go-mod}"
mkdir -p "$GOCACHE" "$GOMODCACHE"

if [[ "$skip_tidy" -eq 0 ]]; then
  go mod tidy
fi

echo "go bootstrap complete in $wd"
echo "GOCACHE=$GOCACHE"
echo "GOMODCACHE=$GOMODCACHE"
