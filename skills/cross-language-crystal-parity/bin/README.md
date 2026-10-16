# Bundled Chiasmus Binaries

This directory is reserved for platform-specific `chiasmus-discover` and
`chiasmus-parity` release artifacts plus their `grammars/` bundle.

Expected layout:

- `darwin-aarch64/chiasmus-discover`
- `darwin-aarch64/chiasmus-parity`
- `darwin-aarch64/grammars/...`
- `linux-x86_64/chiasmus-discover`
- `linux-x86_64/chiasmus-parity`
- `linux-x86_64/grammars/...`
- `windows-x86_64/chiasmus-discover.exe`
- `windows-x86_64/chiasmus-parity.exe`
- `windows-x86_64/grammars/...`

Populate this directory from a tagged `dsisnero/chiasmus.cr` release with:

```bash
./scripts/sync_chiasmus_release_binaries.sh <tag>
```

These files are legacy/manual bundles. The parity scripts now resolve one
manifest-verified release toolchain automatically and do not select binaries
from this directory. See `../references/toolchain-resolution.md`.
