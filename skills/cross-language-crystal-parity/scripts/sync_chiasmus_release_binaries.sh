#!/usr/bin/env bash
# Compatibility entrypoint: install the host platform into the verified cache.
set -euo pipefail
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <tag> [dsisnero/chiasmus.cr]" >&2
  exit 1
fi
if [[ "${2:-dsisnero/chiasmus.cr}" != "dsisnero/chiasmus.cr" ]]; then
  echo "Use CHIASMUS_RELEASE_INDEX with install_chiasmus_toolchain.sh for a release mirror." >&2
  exit 1
fi
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/install_chiasmus_toolchain.sh" --version "$1"
