# Chiasmus Release Follow-up

Prepared 2026-10-19 for `dsisnero/chiasmus.cr`. Crystal Forge now uses one
manifest-verified cache installation per platform and release tag. No Chiasmus
files were changed when this note was first prepared. The implementation status
below records subsequent work in both repositories.

## Verified Consumer Results (2026-10-19)

- Stable release: [v0.3.2](https://github.com/dsisnero/chiasmus.cr/releases/tag/v0.3.2).
  Its [release run](https://github.com/dsisnero/chiasmus.cr/actions/runs/39060748216)
  passed Linux, macOS, Windows, and publication. All three archives have the
  required GitHub API SHA-256 digests and names.
- Installed the published macOS aarch64 archive through Crystal Forge's
  manifest-verifying installer into the shared cache.
- Ran `scripts/verify_released_toolchain.py --version v0.3.2` with normal
  resolution and with `--offline`. Strict Java tree-sitter preflight and
  Java-to-Crystal reconciliation passed: Widget and Widget.size both matched,
  zero unmapped entities, and one matching zero-arity method surface. Explicit
  int-to-Int32 conversion rules made return-type matching pass as well.
- `otool -L` confirmed external Homebrew SQLite, OpenSSL 4, and tree-sitter
  0.27 dependencies in the macOS facts CLI. That release is not standalone.
- Added Chiasmus `docs/RELEASES.md` describing platform/grammar coverage and
  native prerequisites, and included it before release manifest generation.
- Hardened Chiasmus `release_smoke.py` and added regression tests. Its isolated
  real-package run passed Java/Go entity and surface assertions, AST provenance,
  Rust discovery, planning, and complete/incomplete status and ID queries.
  The combined smoke/manifest/workflow suite passed 29 tests.
- v0.3.2 supports discovery/facts cache flags but not parity `--cache-dir`.
  The smoke test and skill detect the latter via `--help` and pass it only
  when supported.

These consumer results establish macOS behavior on this host. They do not
establish clean-host portability or skill-wrapper execution on Linux/Windows.

## Already Present in the Local Chiasmus Checkout

The inspected `.github/workflows/release.yml` already has Linux x86_64,
macOS aarch64, and Windows x86_64 builds, all five required CLIs, manifest
creation/verification, archive extraction, and `release_smoke.py` before upload.
It also generates `SHA256SUMS` when publishing. Preserve these safeguards;
their presence in source does not establish that a published build passed.

## Acceptance Criteria and Current Status

1. **Satisfied for v0.3.2; repeat for the next release.**
   Run the release workflow on all three platforms and publish a stable tagged
   release after every packaging and runtime check passes. Provide the run URL
   and tag. Ensure the GitHub release asset API supplies `digest: sha256:<hex>`;
   the skill currently verifies that field, not the separate SHA256SUMS file.

2. **Verified on macOS; Linux/Windows consumer runs remain.**
   Test the exact archive through Crystal Forge's `resolve_toolchain.py` as a
   consumer. Keep archive names `chiasmus-Linux-x86_64-<tag>.tar.gz`,
   `chiasmus-macOS-aarch64-<tag>.tar.gz`, and
   `chiasmus-Windows-x86_64-<tag>.zip`. Each must unpack under `chiasmus/` and
   contain `toolchain-manifest.json`, discover/facts/parity/plan/complete CLIs
   (`.exe` on Windows), and native Java, Go, and Crystal grammar libraries.

3. **Implemented and regression-tested.** Keep the v1 manifest compatible: `manifest_version: 1`, platform keys
   `linux-x86_64`, `darwin-aarch64`, `windows-x86_64`, a nonempty `build_id`,
   SHA-256 and size records for every packaged file except the manifest, and
   capability groups containing `discover: [tree-sitter]`,
   `facts: [typed-declarations]`, and `parity: [bundle]`. Include runtime DLLs
   and shared libraries in the file records. Unix CLIs must be executable.

4. **Implemented and verified locally against v0.3.2.**
   Strengthen `release_smoke.py`: change the subprocess working directory to
   an isolated temporary directory, resolve executable paths first, and exclude
   source-checkout/cache grammar fallbacks. Assert actual tree-sitter parser
   provenance as well as finding Widget. The previous smoke checked generated
   report file existence; the new assertions inspect entity mappings and
   surface results so empty/header-only or incorrect reports fail.

5. **Implemented and verified locally against v0.3.2.**
   Exercise plan and complete beyond `--help`: generate planning output and
   evaluate a small complete/incomplete fixture. Cover `--cache-dir`, facts
   `--declarations-out`, parity `--source-declarations`,
   `--target-declarations`, and `--bundle-dir`, which the skill invokes.

6. **Prerequisites documented; clean-host checks remain.**
   Verify dynamic dependencies from the extracted package on clean hosts.
   Bundle redistributable libraries or document supported prerequisites;
   avoid dependencies on build-machine Homebrew/vcpkg paths. Check DLL loading
   on Windows and native library resolution on Linux/macOS. Windows shell
   integration also needs Git Bash, Ruby, and Python 3 on the consumer side.

7. **Documented in Chiasmus docs/RELEASES.md and packaged for future releases.**
   Publish the actual supported language set. The current packaging loop does
   not include every grammar the discovery library may support (for example
   C#); either package and test additional grammars or document the subset.
   macOS Intel and Linux ARM64 are optional additional build targets, not
   covered by the current three-platform matrix.

## Consumer Verification After Publication

From the Crystal Forge parity skill directory:

```bash
bash scripts/install_chiasmus_toolchain.sh --version <stable-tag>
export CHIASMUS_VERSION=<stable-tag>
bash scripts/verify_skill_install.sh /path/to/port java tree-sitter
bash scripts/reconcile_parity.sh /path/to/port vendor/upstream java src
```

Repeat with `CHIASMUS_TOOLCHAIN_OFFLINE=1` and confirm the pinned verified cache
works without network access. An unavailable pin must fail rather than switch
versions. Record real cross-platform results separately from fixture tests.
