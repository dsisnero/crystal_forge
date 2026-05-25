# Usage Guidelines

## Crystal Discovery Binary (Optional but Recommended)

For tree-sitter-backed discovery, the parity scripts detect and delegate to a
Crystal discovery binary (`chiasmus-discover`). This provides:

- Per-language S-expression tree-sitter query patterns (10 languages).
- Non-blocking concurrent file processing via Crystal fibers + channels.
- Higher accuracy than regex for significant declarations (classes, interfaces,
  functions, methods, constants, tests).

If the binary is not found, the scripts fall back to the Ruby `tree_sitter` gem
or regex extraction with a clear "regex fallback used" warning.

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
./scripts/generate_port_inventory.sh . plans/inventory/rust_port_inventory.tsv vendor/upstream rust

# Intentional reset only
./scripts/generate_port_inventory.sh . plans/inventory/rust_port_inventory.tsv vendor/upstream rust 1

# Intentional source manifest reset only
./scripts/generate_source_parity_manifest.sh . plans/inventory/rust_source_parity.tsv vendor/upstream rust "" "" 1

# Intentional test manifest reset only
./scripts/generate_test_parity_manifest.sh . plans/inventory/rust_test_parity.tsv vendor/upstream rust 1
```

## Recommended Day-to-Day Loop

1. Bootstrap/validate once:

```bash
./scripts/ensure_parity_plan.sh . vendor/upstream rust auto 0
```

2. Create or refresh `plans/parity.md` as a curated feature plan.
   Use only major checkbox items (`[ ]` / `[x]`) that map to branch-sized,
   red-green-TDD-capable parity features.
3. Pick one unchecked feature from `plans/parity.md`, port the failing/missing specs
   for that feature first, then implement against that slice.
4. Update ledger statuses manually in
   `plans/inventory/rust_port_inventory.tsv` as the source of truth for exact
   upstream API/test coverage.
5. Re-run checks continuously:

```bash
./scripts/check_port_inventory.sh . plans/inventory/rust_port_inventory.tsv vendor/upstream rust
./scripts/check_source_parity.sh . plans/inventory/rust_source_parity.tsv vendor/upstream rust
./scripts/check_test_parity.sh . plans/inventory/rust_test_parity.tsv vendor/upstream rust
```

6. Mark the feature `[x]` in `plans/parity.md` only after its inventory rows are
   covered and the parity slice is green.
7. Run adversarial signoff before merge:

```bash
./scripts/verify_parity_adversarial.sh . vendor/upstream rust 'crystal spec' 'cargo test'
```
