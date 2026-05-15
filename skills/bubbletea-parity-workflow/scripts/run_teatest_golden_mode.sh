#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BASH_VERSION:-}" ]]; then
  exec /usr/bin/env bash "$0" "$@"
fi

usage() {
  cat <<USAGE
Usage: $0 \
  --go-workdir <dir> --go-update-cmd <cmd> \
  --crystal-workdir <dir> --crystal-verify-cmd <cmd> \
  [--sync-goldens-from <dir> --sync-goldens-to <dir>]

Default behavior:
- Go command runs with GOLDEN_UPDATE=1 (generate/update golden files).
- Crystal command runs with GOLDEN_UPDATE=0 (verify only).

Optional sync copies *.golden files from Go tree to Crystal tree before verify.
USAGE
}

go_wd=""
go_update_cmd=""
cr_wd=""
cr_verify_cmd=""
sync_from=""
sync_to=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --go-workdir) go_wd="$2"; shift 2 ;;
    --go-update-cmd) go_update_cmd="$2"; shift 2 ;;
    --crystal-workdir) cr_wd="$2"; shift 2 ;;
    --crystal-verify-cmd) cr_verify_cmd="$2"; shift 2 ;;
    --sync-goldens-from) sync_from="$2"; shift 2 ;;
    --sync-goldens-to) sync_to="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$go_wd" || -z "$go_update_cmd" || -z "$cr_wd" || -z "$cr_verify_cmd" ]]; then
  usage
  exit 1
fi

if [[ -n "$sync_from" && -z "$sync_to" ]] || [[ -z "$sync_from" && -n "$sync_to" ]]; then
  echo "error: provide both --sync-goldens-from and --sync-goldens-to" >&2
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "error: go not found in PATH" >&2
  exit 1
fi

echo "[1/3] Go teatest/golden update"
(
  cd "$go_wd"
  export GOCACHE="${GOCACHE:-$PWD/.cache/go-build}"
  export GOMODCACHE="${GOMODCACHE:-$PWD/.cache/go-mod}"
  mkdir -p "$GOCACHE" "$GOMODCACHE"
  export GOLDEN_UPDATE=1
  /bin/bash -lc "$go_update_cmd"
)

if [[ -n "$sync_from" ]]; then
  echo "[2/3] Sync *.golden files"
  if [[ ! -d "$sync_from" ]]; then
    echo "error: sync source not found: $sync_from" >&2
    exit 1
  fi
  mkdir -p "$sync_to"
  (
    cd "$sync_from"
    while IFS= read -r -d '' f; do
      target="$sync_to/$f"
      mkdir -p "$(dirname "$target")"
      cp "$f" "$target"
    done < <(find . -type f -name '*.golden' -print0)
  )
else
  echo "[2/3] Skip golden sync"
fi

echo "[3/3] Crystal teatest/golden verify"
(
  cd "$cr_wd"
  export CRYSTAL_CACHE_DIR="${CRYSTAL_CACHE_DIR:-$PWD/.crystal-cache}"
  mkdir -p "$CRYSTAL_CACHE_DIR"
  export GOLDEN_UPDATE=0
  /bin/bash -lc "$cr_verify_cmd"
)

echo "TEATEST_GOLDEN_OK"
