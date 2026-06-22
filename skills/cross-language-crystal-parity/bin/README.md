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

The parity scripts will prefer:

1. `CHIASMUS_DISCOVER_BIN`
2. bundled platform binary under this directory
3. target repo `bin/chiasmus-discover`
4. target repo source fallback
