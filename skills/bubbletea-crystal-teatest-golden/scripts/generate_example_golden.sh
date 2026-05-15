#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BASH_VERSION:-}" ]]; then
  exec /usr/bin/env bash "$0" "$@"
fi

usage() {
  cat <<USAGE
Usage: $0 --repo <repo> <example-file> [model-class]

Examples:
  $0 --repo /path/to/bubbletea examples/canvas.cr
  $0 --repo /path/to/bubbletea canvas.cr CanvasModel

Generates: <repo>/testdata/examples/<example-name>.golden
USAGE
}

repo=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if [[ -z "$repo" || $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

if [[ ! -d "$repo" ]]; then
  echo "error: repo not found: $repo" >&2
  exit 1
fi

cd "$repo"

example_input="$1"
if [[ -f "$example_input" ]]; then
  example_file="$example_input"
elif [[ -f "examples/$example_input" ]]; then
  example_file="examples/$example_input"
else
  echo "error: example file not found: $example_input" >&2
  exit 1
fi

example_name="$(basename "$example_file" .cr)"

if [[ $# -eq 2 ]]; then
  model_class="$2"
else
  IFS='_' read -r -a parts <<< "$example_name"
  model_class=""
  for part in "${parts[@]}"; do
    [[ -z "$part" ]] && continue
    first="$(printf '%s' "${part:0:1}" | tr '[:lower:]' '[:upper:]')"
    rest="${part:1}"
    model_class+="${first}${rest}"
  done
  model_class+="Model"
fi

out_dir="testdata/examples"
out_file="$out_dir/$example_name.golden"
mkdir -p "$out_dir"

cache_dir="${CRYSTAL_CACHE_DIR:-$PWD/.crystal-cache}"
mkdir -p "$cache_dir"

CRYSTAL_CACHE_DIR="$cache_dir" crystal eval "require \"./$example_file\"; model = $model_class.new; print model.view.content" > "$out_file"

echo "wrote $out_file from $example_file using $model_class"
