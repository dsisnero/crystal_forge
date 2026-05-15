#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BASH_VERSION:-}" ]]; then
  exec /usr/bin/env bash "$0" "$@"
fi

usage() {
  cat <<USAGE
Usage: $0 --workdir <dir> --cmd <crystal test command>

Runs with GOLDEN_UPDATE=0 and default CRYSTAL_CACHE_DIR=<workdir>/.crystal-cache.
USAGE
}

wd=""
cmd=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workdir) wd="$2"; shift 2 ;;
    --cmd) cmd="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$wd" || -z "$cmd" ]]; then
  usage
  exit 1
fi

(
  cd "$wd"
  export CRYSTAL_CACHE_DIR="${CRYSTAL_CACHE_DIR:-$PWD/.crystal-cache}"
  mkdir -p "$CRYSTAL_CACHE_DIR"
  export GOLDEN_UPDATE=0
  /bin/bash -lc "$cmd"
)
