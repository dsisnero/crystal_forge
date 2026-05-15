#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BASH_VERSION:-}" ]]; then
  exec /usr/bin/env bash "$0" "$@"
fi

usage() {
  cat <<USAGE
Usage: $0 --out-dir <dir> \
  --go-workdir <dir> [--go-cmd <cmd>] [--go-out-file <file>] \
  --crystal-workdir <dir> [--crystal-cmd <cmd>] [--crystal-out-file <file>] \
  [--show-head-bytes <n>] [--temp-dir <dir>]

For each side (go/crystal), provide either:
- a command that writes raw bytes to stdout, or
- --*-out-file pointing to a file produced by the command.

If both cmd and out-file are provided, cmd runs first and then the file is copied.
USAGE
}

out_dir=""
go_wd=""
go_cmd=""
go_out_file=""
cr_wd=""
cr_cmd=""
cr_out_file=""
show_head_bytes="128"
parity_temp_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) out_dir="$2"; shift 2 ;;
    --go-workdir) go_wd="$2"; shift 2 ;;
    --go-cmd) go_cmd="$2"; shift 2 ;;
    --go-out-file) go_out_file="$2"; shift 2 ;;
    --crystal-workdir) cr_wd="$2"; shift 2 ;;
    --crystal-cmd) cr_cmd="$2"; shift 2 ;;
    --crystal-out-file) cr_out_file="$2"; shift 2 ;;
    --show-head-bytes) show_head_bytes="$2"; shift 2 ;;
    --temp-dir) parity_temp_dir="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$out_dir" || -z "$go_wd" || -z "$cr_wd" ]]; then
  usage
  exit 1
fi

if [[ -z "$go_cmd" && -z "$go_out_file" ]]; then
  echo "error: provide --go-cmd or --go-out-file" >&2
  exit 1
fi

if [[ -z "$cr_cmd" && -z "$cr_out_file" ]]; then
  echo "error: provide --crystal-cmd or --crystal-out-file" >&2
  exit 1
fi


if [[ -z "$parity_temp_dir" ]]; then
  parity_temp_dir="$cr_wd/temp/parity"
fi
mkdir -p "$parity_temp_dir"
export PARITY_TEMP_DIR="$parity_temp_dir"
mkdir -p "$out_dir"
go_out="$out_dir/go.golden"
cr_out="$out_dir/crystal.golden"

capture_side() {
  local side="$1"
  local wd="$2"
  local cmd="$3"
  local out_file="$4"
  local out_target="$5"

  if [[ -n "$cmd" && -z "$out_file" ]]; then
    (
      cd "$wd"
      if [[ "$side" == "go" ]]; then
        export GOCACHE="${GOCACHE:-$wd/.cache/go-build}"
        export GOMODCACHE="${GOMODCACHE:-$wd/.cache/go-mod}"
        mkdir -p "$GOCACHE" "$GOMODCACHE"
      elif [[ "$side" == "crystal" ]]; then
        export CRYSTAL_CACHE_DIR="${CRYSTAL_CACHE_DIR:-$wd/.crystal-cache}"
        mkdir -p "$CRYSTAL_CACHE_DIR"
      fi
      /bin/bash -lc "$cmd"
    ) > "$out_target"
    return
  fi

  if [[ -n "$cmd" && -n "$out_file" ]]; then
    (
      cd "$wd"
      if [[ "$side" == "go" ]]; then
        export GOCACHE="${GOCACHE:-$wd/.cache/go-build}"
        export GOMODCACHE="${GOMODCACHE:-$wd/.cache/go-mod}"
        mkdir -p "$GOCACHE" "$GOMODCACHE"
      elif [[ "$side" == "crystal" ]]; then
        export CRYSTAL_CACHE_DIR="${CRYSTAL_CACHE_DIR:-$wd/.crystal-cache}"
        mkdir -p "$CRYSTAL_CACHE_DIR"
      fi
      /bin/bash -lc "$cmd"
    )
  fi

  if [[ -n "$out_file" ]]; then
    (
      cd "$wd"
      cp "$out_file" "$out_target"
    )
  fi
}

capture_side "go" "$go_wd" "$go_cmd" "$go_out_file" "$go_out"
capture_side "crystal" "$cr_wd" "$cr_cmd" "$cr_out_file" "$cr_out"

base64 < "$go_out" > "$out_dir/go.base64.txt"
base64 < "$cr_out" > "$out_dir/crystal.base64.txt"

hash_file() {
  local in_file="$1"
  local out_file="$2"
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$in_file" | awk '{print $NF}' > "$out_file"
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    if shasum -a 256 "$in_file" | awk '{print $1}' > "$out_file" 2>/dev/null; then
      return
    fi
  fi
  cksum "$in_file" | awk '{print $1":"$2}' > "$out_file"
}

hash_file "$go_out" "$out_dir/go.sha256.txt"
hash_file "$cr_out" "$out_dir/crystal.sha256.txt"

if cmp -s "$go_out" "$cr_out"; then
  echo "PARITY_OK"
echo "parity_temp_dir=$PARITY_TEMP_DIR"
  echo "go_bytes=$(wc -c < "$go_out" | tr -d ' ')"
  echo "crystal_bytes=$(wc -c < "$cr_out" | tr -d ' ')"
  exit 0
fi

echo "PARITY_MISMATCH" >&2
echo "parity_temp_dir=$PARITY_TEMP_DIR" >&2
echo "go_bytes=$(wc -c < "$go_out" | tr -d ' ')" >&2
echo "crystal_bytes=$(wc -c < "$cr_out" | tr -d ' ')" >&2
echo "go_sha256=$(cat "$out_dir/go.sha256.txt")" >&2
echo "crystal_sha256=$(cat "$out_dir/crystal.sha256.txt")" >&2

echo "first_diff_offset (1-based): $(cmp -l "$go_out" "$cr_out" | head -n 1 | awk '{print $1}')" >&2 || true
echo "go_head_base64=$(head -c "$show_head_bytes" "$go_out" | base64 | tr -d '\n')" >&2
echo "crystal_head_base64=$(head -c "$show_head_bytes" "$cr_out" | base64 | tr -d '\n')" >&2

exit 2
