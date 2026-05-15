#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BASH_VERSION:-}" ]]; then
  exec /usr/bin/env bash "$0" "$@"
fi

usage() {
  cat <<USAGE
Usage: $0 --workdir <dir> --cmd <go test command>

Runs with GOLDEN_UPDATE=1 and local Go caches by default.
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

if ! command -v go >/dev/null 2>&1; then
  echo "error: go not found in PATH" >&2
  exit 1
fi

(
  cd "$wd"
  export GOCACHE="${GOCACHE:-$PWD/.cache/go-build}"
  export GOMODCACHE="${GOMODCACHE:-$PWD/.cache/go-mod}"
  mkdir -p "$GOCACHE" "$GOMODCACHE"
  export GOLDEN_UPDATE=1
  /bin/bash -lc "$cmd"
)
