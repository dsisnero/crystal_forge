# Legacy Binary Directory

The skill installs complete, manifest-verified Chiasmus toolchains into
`~/.cache/chiasmus/toolchains/<platform>/<tag>` and does not load binaries here.
Existing local files may be retained, but are not an installation source.

From the skill directory, install the newest compatible stable release:

```bash
bash scripts/install_chiasmus_toolchain.sh
```

Use `--version <exact-tag>` or `CHIASMUS_VERSION` to pin a release. For offline
and manually provisioned installations, see
[toolchain resolution](../references/toolchain-resolution.md).
