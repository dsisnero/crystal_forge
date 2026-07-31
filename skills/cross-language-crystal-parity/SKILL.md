---
name: cross-language-crystal-parity
description: Track source-to-Crystal parity with reproducible manifests and a curated `plans/parity.md`. Use for Go, Rust, Crystal, Java, Ruby, or TypeScript/JavaScript upstreams when ad-hoc parity tracking is too loose.
---

# Cross-Language Crystal Parity

Use one workflow for parity planning, drift checks, and signoff across supported
upstream languages: `go`, `rust`, `crystal`, `java`, `csharp`, `ruby`,
`typescript`/`javascript`, and `python`. The workflow is grammar-driven: any
language with an available tree-sitter grammar (bundled in `chiasmus-discover`,
`CHIASMUS_GRAMMAR_DIR`, or a repo-local `./grammars`) works without editing the
skill. The hard-coded language lists are only the regex fallback for languages
without a grammar.

Read `references/usage-guidelines.md` or `references/invariants.md` only when
you need the extra detail.

## Artifacts

- Curated feature plan: `plans/parity.md`
- Curated working ledger: `plans/inventory/<language>_port_inventory.tsv`
- Generated manifests:
  - `plans/inventory/<language>_source_parity.tsv`
  - `plans/inventory/<language>_test_parity.tsv`
- Optional deterministic notes:
  - `plans/inventory/<language>_source_notes.tsv`

## Core scripts

- `scripts/ensure_parity_plan.sh`
- `scripts/generate_port_inventory.sh`
- `scripts/generate_source_parity_manifest.sh`
- `scripts/generate_test_parity_manifest.sh`
- `scripts/check_port_inventory.sh`
- `scripts/check_source_parity.sh`
- `scripts/check_test_parity.sh`
- `scripts/verify_parity_adversarial.sh`

Legacy `generate_go_*` and `check_go_*` wrappers remain available for older
repos.

## Parser mode

All generators accept `auto`, `regex`, or `tree-sitter` via `--parser` or
`PORT_PARSER`.

- `auto`: preferred default
- `tree-sitter`: require the Chiasmus discovery binary; fail when it is not
  available rather than silently producing a regex inventory
- `regex`: lowest-fidelity fallback

Tree-sitter binary lookup order:

1. `CHIASMUS_DISCOVER_BIN`
2. bundled skill binary under `bin/<platform>/`
3. target repo `bin/chiasmus-discover`
4. target repo source fallback (`src/chiasmus_discover.cr`)
5. regex fallback in `auto` mode only

The `darwin-aarch64` discovery bundle includes native grammars for Java, Rust,
C#, TypeScript, Python, Ruby, and Go. Use the language identifiers `java`,
`rust`, `csharp`, `typescript`, `python`, `ruby`, and `go` with strict mode.

## Scope and preflight

Use `PORT_SCOPE_INCLUDE` (comma-separated roots relative to the upstream source)
and `PORT_SCOPE_EXCLUDE` (comma-separated relative globs) to make a workspace
scope explicit. Every generated TSV has a sibling `.metadata.json` recording
the effective backend, discovery command, and effective scope.

Run `scripts/verify_skill_install.sh <target-root> <language> tree-sitter`
before a strict downstream refresh. It verifies wrapper permissions and executes
a minimal tree-sitter discovery probe. `auto` remains allowed to report regex
when no discovery binary is available; `tree-sitter` fails instead.

## Canonical script execution

Run scripts from this canonical skill directory. Do not copy them into a target
repo or maintain a second installed script snapshot: both drift and become
stale. If a Codex-installed skill needs these scripts, point its `scripts/`
directory at this one (for example with a symlink) rather than copying files.

Resolve script paths relative to this `SKILL.md` file, then pass the target repo
root as the first argument.

Example:

```bash
SKILL_DIR=/Users/dominic/.agents/skills/crystal_forge/skills/cross-language-crystal-parity
"${SKILL_DIR}/scripts/ensure_parity_plan.sh" /path/to/repo <source_path> <language> auto 0
```

If you want the skill to carry its own Chiasmus binaries, sync a tagged release
from `dsisnero/chiasmus.cr` into the skill bundle first:

```bash
"${SKILL_DIR}/scripts/sync_chiasmus_release_binaries.sh" <tag>
```

This populates `bin/<platform>/` with `chiasmus-discover`,
`chiasmus-parity`, and the matching `grammars/` directory.

## Standard flow

### 1. Create or refresh the plan

```bash
"${SKILL_DIR}/scripts/ensure_parity_plan.sh" . <source_path> <language> auto 0
```

This should leave you with validated inventory manifests plus a curated
`plans/parity.md`.

### 2. Keep the right files curated

- `plans/parity.md` is a feature roadmap, not a generated dump.
- `<language>_port_inventory.tsv` is the day-to-day ledger.
- Source and test parity TSVs are generated reference manifests.
- Regenerate generated manifests only for intentional upstream refresh.

### 3. Implement from the plan

For each feature:

1. Read the upstream source module and nearest upstream tests.
2. Port the next failing or missing parity spec first.
3. Make the smallest behavior change that turns the spec green.
4. Keep looping until the whole feature is done.
5. Update the affected inventory rows before closing the feature.
6. Check the feature box in `plans/parity.md`.

Do not stop at helper-sized milestones if the top-level feature is still open.

### 4. Commit at feature completion (required)

**Every feature completed in `plans/parity.md` must be committed before
starting the next feature.** This is not optional. A single feature may
span many files, but it must be committed as one atomic change after its
checkbox is checked.

Before committing:

1. Check `git status` and `git diff --stat` to review scope.
2. Stage only files belonging to the feature (plus `plans/parity.md` and
   inventory updates).
3. Write a commit message starting with `port:` followed by the feature
   name(s) and a bullet list of what was implemented.
4. Run `crystal tool format --check src spec` and `crystal build --no-codegen`
   to verify nothing is broken.
5. Push or keep local — but the commit must exist.

Example:
```
port: JobExecutor execute, SubscriptionManager

- JobExecutor: full execute with hooks, middleware, retry, snooze, stuck detection
- SubscriptionManager: event subscriptions with SubscribeConfig, cancel support
```

### 5. Re-run drift checks continuously

```bash
"${SKILL_DIR}/scripts/check_port_inventory.sh" . plans/inventory/<language>_port_inventory.tsv <source_path> <language>
"${SKILL_DIR}/scripts/check_source_parity.sh" . plans/inventory/<language>_source_parity.tsv <source_path> <language>
"${SKILL_DIR}/scripts/check_test_parity.sh" . plans/inventory/<language>_test_parity.tsv <source_path> <language>
```

### 6. Run adversarial signoff

```bash
"${SKILL_DIR}/scripts/verify_parity_adversarial.sh" . <source_path> <language> \
  'crystal spec' \
  '<upstream test command>'
```

Run this as an independent review pass when possible.

## Ledger rules

Allowed `port_inventory` statuses:

- `missing`
- `in_progress`
- `partial`
- `ported`
- `skipped`
- `intentional_divergence`

Rules:

- `partial` and `ported` rows must include `crystal_refs`.
- Use `-` for intentionally unfilled TSV cells; do not leave empty columns.
- Record naming differences and Crystal-native replacements in `notes`.
- Keep deterministic source notes in `<language>_source_notes.tsv` if they must
  survive regeneration.

## Feature slicing rules

- `plans/parity.md` items should be branch-sized user-visible features, not
  single helper methods.
- Mark a feature complete only when its mapped rows are closed with rationale
  and the parity checks are green.
- If a feature is too large, split it into several still-meaningful features.

## Guardrails

- Use the inventory to decide scope and `plans/parity.md` to decide sequence.
- Commit after every completed feature in `plans/parity.md`. Never batch
  multiple unrelated features into one commit. Never leave completed features
  uncommitted at session end.
- Do not regenerate curated ledgers on top of active manual work.
- Do not weaken upstream tests or fixtures to make Crystal look green.
- Preserve behaviorally important internal data structures when upstream
  semantics depend on them.

## Related skills

- `initialize-crystal-porting-project`
- `porting-to-crystal`
