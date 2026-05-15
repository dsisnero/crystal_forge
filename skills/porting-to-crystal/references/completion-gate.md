# Port Completion Gate

Use this gate before declaring a porting task complete.

## 1) Inventory Completeness

Run and pass:

```bash
./bin/check_port_inventory.sh . plans/inventory/<language>_port_inventory.tsv <source_path> <language>
./bin/check_source_parity.sh . plans/inventory/<language>_source_parity.tsv <source_path> <language>
./bin/check_test_parity.sh . plans/inventory/<language>_test_parity.tsv <source_path> <language>
```

Requirements:

- Implemented rows are not left `missing`.
- `partial`/`ported` rows include concrete `crystal_refs`.
- Naming-drift mappings are documented in `crystal_refs` + `notes`.

## 2) Adversarial Parity Verification

Run and pass:

```bash
./bin/verify_parity_adversarial.sh . <source_path> <language> 'crystal spec' '<upstream test cmd>'
```

This enforces manifest integrity, status quality, and placeholder-spec checks.

## 3) Crystal Quality Gates

Run and pass:

```bash
crystal tool format --check src spec
ameba src spec
crystal spec
```

## 4) Behavior Parity Evidence

- Relevant fixture/golden comparisons are clean.
- Any unavoidable deviation is documented with rationale.

## 5) Repository Hygiene

- Temporary artifacts removed (`temp/`, capture binaries, ad-hoc files).
- No debug-only files are committed.
- Optional preflight:

```bash
git clean -ndX
```

(Use dry-run first; do not run destructive clean commands unless requested.)

## 6) Documentation Updates

- Update parity status docs (complete/in-progress/deviations).
- Update changelog for user-visible behavior changes.
- Keep README merged with upstream submodule README highlights; do not replace
  local README with upstream verbatim.
- Ensure README includes explicit attribution:
  `This repository is a Crystal port of <upstream-url>`.

## 6b) Initialization Baseline Verification

Run and pass:

```bash
/Users/dominic/.agents/skills/crystal_forge/skills/initialize-crystal-porting-project/scripts/verify_initialized_project_baseline.sh <project_root>
```

This verifies deterministic setup outputs for `Makefile`, `.ameba.yml`,
`.rumdl(.toml)`, `docs/`, and `README.md`.

## 7) Traceability

- Upstream commit/tag used for parity is recorded in notes/PR.
- Add a release tag only if project release workflow requires it.
