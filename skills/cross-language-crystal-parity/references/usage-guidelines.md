# Usage Guidelines

Set `SKILL_DIR` to the installed parity skill root before running these examples.

```bash
SKILL_DIR=/Users/dominic/.agents/skills/crystal_forge/skills/cross-language-crystal-parity
```

## Crystal Discovery Binary (Optional but Recommended)

For tree-sitter-backed discovery, the parity scripts detect and delegate to a
Crystal discovery binary (`chiasmus-discover`). This provides:

- Per-language S-expression tree-sitter query patterns (coverage depends on the release).
- Non-blocking concurrent file processing via Crystal fibers + channels.
- Higher accuracy than regex for significant declarations (classes, interfaces,
  functions, methods, constants, tests).

The scripts use one manifest-verified release toolchain; they never mix
independently selected binaries. Strict tree-sitter mode fails if none is
available. Auto mode may use a lower-fidelity regex fallback with a warning.
See `toolchain-resolution.md` for cache, offline, and local-toolchain controls.

## Safe Repeat Runs

Safe to run repeatedly:

- `ensure_parity_plan.sh`
- `check_port_inventory.sh`
- `check_source_parity.sh`
- `check_test_parity.sh`
- `verify_parity_adversarial.sh`

These commands validate drift and quality without resetting curated progress.

## Manifest Regeneration Policy

`generate_port_inventory.sh`, `generate_source_parity_manifest.sh`, and
`generate_test_parity_manifest.sh` are for initial bootstrap or intentional
reset only.

Behavior:

- If target manifest already exists, generation exits with an error by default.
- To intentionally overwrite, pass force arg `1` (script-specific position) or
  set `PORT_FORCE_OVERWRITE=1`.

Examples:

```bash
# Bootstrap only (expected once)
"${SKILL_DIR}/scripts/generate_port_inventory.sh" . plans/inventory/rust_port_inventory.tsv vendor/upstream rust

# Intentional reset only
"${SKILL_DIR}/scripts/generate_port_inventory.sh" . plans/inventory/rust_port_inventory.tsv vendor/upstream rust 1

# Intentional source manifest reset only
"${SKILL_DIR}/scripts/generate_source_parity_manifest.sh" . plans/inventory/rust_source_parity.tsv vendor/upstream rust "" "" 1

# Intentional test manifest reset only
"${SKILL_DIR}/scripts/generate_test_parity_manifest.sh" . plans/inventory/rust_test_parity.tsv vendor/upstream rust 1
```

## Vendor Refresh & Re-reconcile

When upstream moves, refresh the generated layer without clobbering curated work:

```bash
# 1. Bump the vendor checkout; record the new revision.
git -C vendor/<upstream> fetch --tags && git -C vendor/<upstream> checkout <tag>

# 2. Regenerate manifests + re-run drift checks (REFRESH=1). Preserves the
#    curated port inventory.
"${SKILL_DIR}/scripts/ensure_parity_plan.sh" . vendor/upstream rust auto 1

# 3. Re-derive reconciliation (idempotent).
"${SKILL_DIR}/scripts/reconcile_parity.sh" . vendor/upstream rust src

# 4. Triage new unmapped/divergent/surface-drift rows, then re-curate.
```

The curated `plans/inventory/<language>_port_inventory.tsv` and `plans/parity.md`
are authoritative; never regenerate the port inventory on a live ledger. For
facts-level drift, `chiasmus-plan refresh --previous-facts <previous>.pl` reports
added/removed/changed entities.

## Recommended Day-to-Day Loop

1. Bootstrap/validate once:

```bash
"${SKILL_DIR}/scripts/ensure_parity_plan.sh" . vendor/upstream rust auto 0
```

2. Create or refresh `plans/parity.md` as a curated feature plan.
   Seed it from `templates/parity_plan.md` and keep its **Where we are** block
   current so a new session can resume without git archaeology.
   Use only major checkbox items (`[ ]` / `[x]`) that map to branch-sized,
   red-green-TDD-capable parity features.
3. Pick one unchecked feature from `plans/parity.md`, port the failing/missing specs
   for that feature first, then implement against that slice.
4. Update ledger statuses manually in
   `plans/inventory/rust_port_inventory.tsv` as the source of truth for exact
   upstream API/test coverage.
5. Re-run checks continuously:

```bash
"${SKILL_DIR}/scripts/check_port_inventory.sh" . plans/inventory/rust_port_inventory.tsv vendor/upstream rust
"${SKILL_DIR}/scripts/check_source_parity.sh" . plans/inventory/rust_source_parity.tsv vendor/upstream rust
"${SKILL_DIR}/scripts/check_test_parity.sh" . plans/inventory/rust_test_parity.tsv vendor/upstream rust
```

6. Mark the feature `[x]` in `plans/parity.md` only after its inventory rows are
   covered and the parity slice is green.
7. Run adversarial signoff before merge:

```bash
"${SKILL_DIR}/scripts/verify_parity_adversarial.sh" . vendor/upstream rust 'crystal spec' 'cargo test'
```
