# Invariants

## Ledger Invariants

1. `plans/parity.md` is the curated feature plan for major parity slices.
2. `plans/parity.md` uses `[ ]` and `[x]` checkboxes only for major git-feature-sized
   work items that can be completed through red-green TDD.
3. `plans/inventory/<language>_port_inventory.tsv` is the working ledger.
4. Do not overwrite curated ledger/manifests during normal progress tracking.
5. Status transitions reflect reality:

- `missing` -> `in_progress` -> `partial` -> `ported` (or `skipped` with rationale)

6. `partial` and `ported` rows must include concrete `crystal_refs`.
7. Mark a `plans/parity.md` feature `[x]` only after its corresponding inventory rows
   and parity specs show the slice is actually complete.

## Manifest Format Invariants

1. No empty TSV fields (`\t\t` or trailing tab).
2. Use `-` as explicit placeholder for unfilled fields.
3. Source/test manifests must track current upstream discoverable IDs.
4. Regeneration of existing manifests requires explicit force intent.

## Naming-Drift Invariants

1. Intentional upstream->Crystal naming differences are recorded in ledger
   `crystal_refs` and `notes`.
2. Deterministic source-note overrides live in:
   `plans/inventory/<language>_source_notes.tsv`.
3. Regeneration should preserve override notes via the overrides file, not
   manual edits to generated source manifests.

## Signoff Invariants

1. Drift checks pass (`check_port_inventory`, `check_source_parity`,
   `check_test_parity`).
2. Adversarial verification passes (`verify_parity_adversarial`).
3. Placeholder specs (`pending`, `xit`, etc.) are absent in parity scope.

## Resume Invariants

1. `AGENTS.md` (or its `CLAUDE.md` symlink target) contains a **How to resume**
   block pointing at `plans/parity.md` and the real gates.
2. `plans/parity.md` opens with a **Where we are** block covering current focus,
   ordered next up, status by area, scoping notes, last commit, and gate results.
3. The block is refreshed in the same commit that closes a feature; it is never
   left describing an older state.
4. Session state is recovered from the plan, not from git history or chat.
