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

- `CHIASMUS_VERSION`: exact stable release tag. Cached pins are reused; an
  unavailable or incompatible pin fails rather than selecting another version.
- `CHIASMUS_TOOLCHAIN_DIR`: unpacked complete release to verify and use. Useful
  for development and air-gapped installations.
- `CHIASMUS_TOOLCHAIN_CACHE_DIR`: alternate cache location.
- `CHIASMUS_TOOLCHAIN_OFFLINE=1`: require an already-verified cached release.
- `CHIASMUS_RELEASE_INDEX`: release-index JSON file or alternate API URL for
  controlled tests and mirrors.

From the skill directory, install the newest compatible host toolchain:

```bash
bash scripts/install_chiasmus_toolchain.sh
bash scripts/install_chiasmus_toolchain.sh --version <exact-tag>
```

The installer requires discovery, typed declarations, and parity bundle
capabilities. It downloads only the requested platform (the current host by
default), preserves the complete manifest and grammar bundle, and prints the
verified directory. It uses the same resolver as runtime commands. The legacy
`sync_chiasmus_release_binaries.sh <tag>` command forwards to this installer;
it no longer writes to the skill's `bin/` directory.

Export `CHIASMUS_VERSION=<exact-tag>` for subsequent parity commands to keep
using that release. `--version` pins the installation command only. Offline
pins resolve that exact cached directory even if another version is active.
An explicit `CHIASMUS_TOOLCHAIN_DIR` can accompany a pin only when it is that
pin's resolved cache directory; omit the pin for a manually provisioned bundle.

On Windows, the shell wrappers require Bash (for example Git Bash), Ruby, and
Python 3, and select the packaged `.exe` tools.

If no compatible release has been published, strict tree-sitter and
reconciliation commands fail. Publish a release archive with a v1 manifest
before relying on automatic installation. Regex mode remains available for
lower-fidelity inventory generation. An offline cache can be older than the
latest published release; reconnect to refresh it.
