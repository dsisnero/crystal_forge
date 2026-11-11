# Invariants

## Ledger Invariants

1. `plans/parity.md` is the curated feature plan for major parity slices.
2. `plans/parity.md` uses `[ ]` and `[x]` checkboxes only for major git-feature-sized
   work items that can be completed through red-green TDD.
3. `plans/inventory/<language>_port_inventory.tsv` is the working ledger.
4. Do not overwrite curated ledger/manifests during normal progress tracking.
5. Status transitions reflect reality:

- `missing` -> `in_progress` -> `partial` -> `ported` (or `skipped` with rationale)

6. `partial` and `ported` rows must include concrete `crystal_refs`, and every
   ref must name a file that exists **in this repo today** — the ledger joins
   two churning trees, so a renamed, split or deleted Crystal file otherwise
   leaves the row pointing nowhere and nothing notices. Line anchors
   (`path:12-18`) are advisory: check the file, not the line.
7. The ledger is current-state, not history. Its leading `# baseline=` names the
   pinned upstream release; when that changes, **re-base** (carry over exact
   ids, recover moves by `kind`+`name`, mark genuinely new ids `missing` with a
   triage note, drop ids upstream deleted) instead of appending. Appending
   leaves most rows describing a tree that no longer exists: crig's v0.42-keyed
   ledger had 2,362 stale and 2,188 absent rows — 39% still matched — when its
   target had moved to v0.43.
8. Per-release transitions go to `plans/inventory/v<NN>_delta_triage.tsv`
   (added/modified/deleted), one file per release, never edited afterwards.
   That is the history the current-state ledger deliberately does not carry.
9. Mark a `plans/parity.md` feature `[x]` only after its corresponding inventory rows
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
   `check_test_parity`) — and they are **gates**, not release-time chores: wire
   `check_port_inventory` into the Makefile and the definition of done, or it
   will not run. It already detects duplicate ids, invalid statuses, rows naming
   upstream symbols the pinned tree lacks, and upstream symbols no row mentions;
   extend it to resolve `crystal_refs` files as well.
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
