#!/usr/bin/env bash
set -euo pipefail

# Argument 1 remains the target root for compatibility; the probe is isolated.
LANGUAGE="${2:-rust}"
PARSER="${3:-tree-sitter}"
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for wrapper in "${SCRIPT_DIR}"/*.sh; do
  [[ -x "${wrapper}" ]] || { echo "Parity skill wrapper is not executable: ${wrapper}" >&2; exit 2; }
done

discover_bin=""
if [[ "${PARSER}" != "regex" ]]; then
  if toolchain="$(python3 "${SCRIPT_DIR}/resolve_toolchain.py" --require-capability discover.tree-sitter)"; then
    discover_bin="${toolchain}/chiasmus-discover"
    [[ -f "${discover_bin}.exe" ]] && discover_bin="${discover_bin}.exe"
    export CHIASMUS_TOOLCHAIN_DIR="${toolchain}"
    export CHIASMUS_GRAMMAR_DIR="${toolchain}/grammars"
  elif [[ "${PARSER}" == "tree-sitter" ]]; then
    exit 2
  fi
fi
if [[ -z "${discover_bin}" ]]; then
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
    java) printf 'public class SkillProbe {}\n' > "${sample_dir}/SkillProbe.java" ;;
    python) printf 'class SkillProbe:\n    pass\n' > "${sample_dir}/probe.py" ;;
    ruby) printf 'class SkillProbe\nend\n' > "${sample_dir}/probe.rb" ;;
    csharp) printf 'public class SkillProbe {}\n' > "${sample_dir}/SkillProbe.cs" ;;
    typescript) printf 'export class SkillProbe {}\n' > "${sample_dir}/probe.ts" ;;
    javascript) printf 'export class SkillProbe {}\n' > "${sample_dir}/probe.js" ;;
    crystal) printf 'class SkillProbe\nend\n' > "${sample_dir}/probe.cr" ;;
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
