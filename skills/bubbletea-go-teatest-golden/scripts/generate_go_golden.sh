#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BASH_VERSION:-}" ]]; then
  exec /usr/bin/env bash "$0" "$@"
fi

usage() {
  cat <<USAGE
Usage: $0 --workdir <dir> --out <file> [--cmd <go command>] [--out-file <file>]

Provide either:
- --cmd that writes raw bytes to stdout, or
- --out-file to copy an existing file after --cmd runs.
USAGE
}

wd=""
cmd=""
out=""
out_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workdir) wd="$2"; shift 2 ;;
    --cmd) cmd="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --out-file) out_file="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$wd" || -z "$out" ]]; then
  usage
  exit 1
fi

if [[ -z "$cmd" && -z "$out_file" ]]; then
  echo "error: provide --cmd or --out-file" >&2
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "error: go not found in PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$out")"

export GOCACHE="${GOCACHE:-$wd/.cache/go-build}"
export GOMODCACHE="${GOMODCACHE:-$wd/.cache/go-mod}"
mkdir -p "$GOCACHE" "$GOMODCACHE"

if [[ -n "$cmd" && -z "$out_file" ]]; then
  (
    cd "$wd"
    /bin/bash -lc "$cmd"
  ) > "$out"
else
  if [[ -n "$cmd" ]]; then
    (
      cd "$wd"
      /bin/bash -lc "$cmd"
    )
  fi
  (
    cd "$wd"
    cp "$out_file" "$out"
  )
fi

echo "wrote $out"
