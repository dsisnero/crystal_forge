# Crystal Forge

Reusable agent skills for Crystal development, porting, parity verification,
concurrency, benchmarking, and dependency maintenance.

Canonical skills live under [skills/](skills/). Each skill has a `SKILL.md`
entrypoint and any scripts or references it needs.

## Workspace Installation

From this checkout:

```bash
python3 scripts/sync_workspace_skills.py
python3 scripts/sync_workspace_skills.py --check
```

The sync command refreshes this workspace's `.agents/skills/`, preserves
installed origin metadata, and links resource directories to canonical sources.
Replaced files are backed up in a temporary directory. Existing local binary
bundles are left untouched. After editing a source `SKILL.md`, run sync again;
resource edits are visible immediately through the links.

## Chiasmus Toolchain

The parity skill resolves one complete Chiasmus release into a verified cache.
To install explicitly:

```bash
bash skills/cross-language-crystal-parity/scripts/install_chiasmus_toolchain.sh
```

Use `--version <exact-tag>` to install a particular stable release and export
`CHIASMUS_VERSION=<exact-tag>` to pin subsequent parity commands. See
[toolchain resolution](skills/cross-language-crystal-parity/references/toolchain-resolution.md)
for offline use, platform requirements, and manifest verification.

## Verification

Requires Python 3 and Ruby. Markdown and shell linting additionally use
`rumdl` and `shellcheck`.

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s skills/cross-language-crystal-parity/tests -p 'test_*.py' -v
ruby skills/cross-language-crystal-parity/tests/reconcile_parity_sidecars_test.rb
ruby skills/cross-language-crystal-parity/tests/rust_native_kinds_test.rb
python3 scripts/sync_workspace_skills.py --check
rumdl check skills
shellcheck -S warning skills/*/scripts/*.sh
git diff --check
```

Crystal examples under `skills/crystal-concurrency/examples/` can be compiled
and run separately with the Crystal toolchain. Release artifact smoke tests
belong in `dsisnero/chiasmus.cr`.

To exercise a real published toolchain through the skill wrappers, install the
release first and run:

```bash
python3 scripts/verify_released_toolchain.py --version <exact-tag>
python3 scripts/verify_released_toolchain.py --version <exact-tag> --offline
```

This checks strict tree-sitter preflight, Java-to-Crystal entity mappings, and
method surfaces using explicit type-conversion rules. It requires the selected
release's native runtime libraries and is separate from the offline fixture tests.
