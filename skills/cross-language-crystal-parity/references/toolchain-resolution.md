# Chiasmus toolchain resolution

The parity skill selects one complete Chiasmus release for the host operating
system and architecture. It uses the five CLIs and grammar libraries from that
same archive. It does not use independent binary overrides, target-repository
binaries, or previously bundled binaries.

On each top-level invocation, `scripts/resolve_toolchain.py` queries the stable
GitHub releases, chooses the newest release whose archive has the required
capabilities, verifies the GitHub asset SHA-256 digest, safely extracts the
archive, and verifies every file against `toolchain-manifest.json`. The selected
version is cached atomically under `~/.cache/chiasmus/toolchains/<platform>/<tag>`.
An unchanged release is reused after manifest verification; offline runs use the
last verified active release. A corrupt latest archive fails closed and leaves
the previous cached version intact.

Controls:

- `CHIASMUS_TOOLCHAIN_DIR`: unpacked complete release to verify and use. Useful
  for development and air-gapped installations.
- `CHIASMUS_TOOLCHAIN_CACHE_DIR`: alternate cache location.
- `CHIASMUS_TOOLCHAIN_OFFLINE=1`: require an already-verified cached release.
- `CHIASMUS_RELEASE_INDEX`: release-index JSON file or alternate API URL for
  controlled tests and mirrors.

Example:

```bash
python3 scripts/resolve_toolchain.py --require-capability discover.tree-sitter
```

If no compatible release has been published, strict tree-sitter and
reconciliation commands fail. Publish a release archive with a v1 manifest
before relying on automatic installation. Regex mode remains available for
lower-fidelity inventory generation. An offline cache can be older than the
latest published release; reconnect to refresh it.
