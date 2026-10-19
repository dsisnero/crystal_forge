#!/usr/bin/env bash
# Install or verify one complete toolchain; stdout is its absolute directory.
set -euo pipefail
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${SCRIPT_DIR}/resolve_toolchain.py" \
  --require-capability discover.tree-sitter \
  --require-capability facts.typed-declarations \
  --require-capability parity.bundle "$@"
