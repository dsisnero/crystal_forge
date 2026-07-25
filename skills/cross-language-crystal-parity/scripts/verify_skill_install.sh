#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(pwd)}"
LANGUAGE="${2:-rust}"
PARSER="${3:-tree-sitter}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

for wrapper in "${SCRIPT_DIR}"/*.sh; do
  [[ -x "${wrapper}" ]] || { echo "Parity skill wrapper is not executable: ${wrapper}" >&2; exit 2; }
done

discover_bin="${CHIASMUS_DISCOVER_BIN:-}"
if [[ -z "${discover_bin}" ]]; then
  discover_bin="$(find "${SKILL_DIR}/bin" -maxdepth 2 -type f \( -name chiasmus-discover -o -name chiasmus_discover \) -perm -u+x -print -quit 2>/dev/null || true)"
fi
if [[ ! -x "${discover_bin}" ]]; then
  discover_bin="${ROOT_DIR}/bin/chiasmus-discover"
fi
if [[ "${PARSER}" == "tree-sitter" && ! -x "${discover_bin}" ]]; then
  echo "Chiasmus discovery binary not found; set CHIASMUS_DISCOVER_BIN or sync a skill release bundle." >&2
  exit 2
fi

if [[ ! -x "${discover_bin}" ]]; then
  echo "PARITY_SKILL_VERIFIED=1"
  echo "PARITY_DISCOVERY_BACKEND=regex"
  echo "PARITY_DISCOVERY_BINARY=unavailable"
  exit 0
fi

if [[ "${PARSER}" == "tree-sitter" ]]; then
  sample_dir="$(mktemp -d)"
  trap 'rm -rf "${sample_dir}"' EXIT
  case "${LANGUAGE}" in
    rust) printf 'pub struct SkillProbe;\n' > "${sample_dir}/probe.rs" ;;
    go) printf 'package probe\ntype SkillProbe struct{}\n' > "${sample_dir}/probe.go" ;;
    *) printf '// skill probe\n' > "${sample_dir}/probe.${LANGUAGE}" ;;
  esac
  output="$("${discover_bin}" --language "${LANGUAGE}" --dir "${sample_dir}" --parser tree-sitter)"
  grep -q 'parser=tree-sitter' <<<"${output}" || {
    echo "Chiasmus discovery did not use tree-sitter for ${LANGUAGE}." >&2
    exit 2
  }
fi

if command -v shasum >/dev/null 2>&1; then
  binary_id="sha256:$(shasum -a 256 "${discover_bin}" | awk '{print $1}')"
else
  binary_id="path:${discover_bin}"
fi
echo "PARITY_SKILL_VERIFIED=1"
echo "PARITY_DISCOVERY_BINARY=${discover_bin}"
echo "PARITY_DISCOVERY_BINARY_ID=${binary_id}"
