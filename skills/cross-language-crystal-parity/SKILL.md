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
- `scripts/reconcile_parity.sh`

## Parser mode

All generators accept `auto`, `regex`, or `tree-sitter` via `--parser` or
`PORT_PARSER`.

- `auto`: preferred default
- `tree-sitter`: require the Chiasmus discovery binary; fail when it is not
  available rather than silently producing a regex inventory. A configured
  binary is authoritative for grammar availability: its bundled grammars are
  used even when the target repository has no local `grammars/` directory.
- `regex`: lowest-fidelity fallback

Tree-sitter discovery resolves one verified Chiasmus release toolchain, then uses
its discovery CLI and matching grammars. The resolver checks the newest stable
compatible release on each top-level run and caches complete archives by platform
and tag. `CHIASMUS_TOOLCHAIN_DIR` selects a complete, manifest-verified local
toolchain; `CHIASMUS_TOOLCHAIN_OFFLINE=1` uses the last verified cached release.
Set `CHIASMUS_VERSION=<exact-tag>` to pin all commands to a stable release.
Individual `CHIASMUS_*_BIN` overrides and stale bundled/repo binaries are not
accepted. See `references/toolchain-resolution.md` for details.

Available languages depend on the selected release's grammar bundle. The strict
preflight checks that the requested language actually uses tree-sitter.

### Curated kind vocabulary

Each language's curated kind set decides which discovered declarations reach the
generated manifests. Rust admits both vocabularies:

| Native Chiasmus label | Declaration |
| --- | --- |
| `function` | free function |
| `class` | struct or enum |
| `interface` | trait |

Keep the historical regex extractor labels (`func`, `struct`, `enum`, `trait`)
alongside those native labels. Removing a historical label can drop IDs that
existing curated ledgers already reference, and renaming native labels changes
manifest IDs, so it is a versioned migration rather than an unannounced fix.
Never copy the native discovery `status` column into a curated ledger: discovery
identifies symbols, it does not sign off Crystal implementation.

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

Release archives are resolved automatically. For an air-gapped installation,
set `CHIASMUS_TOOLCHAIN_DIR` to an unpacked complete release directory or warm
the resolver cache before setting `CHIASMUS_TOOLCHAIN_OFFLINE=1`.

To install explicitly, run `bash "${SKILL_DIR}/scripts/install_chiasmus_toolchain.sh"`.
Use `--version <exact-tag>` to install a specific release. In this repository,
refresh workspace skills with `python3 scripts/sync_workspace_skills.py` and
detect drift with `python3 scripts/sync_workspace_skills.py --check`.

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

1. Pick the next feature and record it as current in `plans/parity.md`.
2. Read the upstream source module and nearest upstream tests.
3. Port the next failing or missing parity spec first.
4. Make the smallest behavior change that turns the spec green.
5. Keep looping until the whole feature is done.
6. Update the affected inventory rows before closing the feature.
7. Check the feature box in `plans/parity.md` and make sure it is marked complete.

If `plans/parity.md` grows too large, move details into
`plans/feature-<phase-or-id>.md` subplans and link them from `plans/parity.md`.
Keep the current feature visible in the top-level plan.

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

```text
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

## Cross-language reconciliation (maps / surfaces / divergences)

Beyond generated manifests, the skill can reconcile a source tree against the
Crystal port by entity identity using declarative rule data, and surface
ledger-vs-structure disagreements. Requires a compatible complete Chiasmus
toolchain resolved as described above.

Rule data lives in the port repo (recommended `plans/parity_rules.yml`):

```yaml
version: 1
source_language: java
target_language: crystal
match_owner: true
source:
  strip_namespace: ["org.apache.pdfbox."]
  strip_prefix: [COS, PD, FDF, PDF]
  strip_accessor: true
  type_map: { void: nil, int: int, boolean: bool }
target:
  strip_namespace: ["Pdfbox::"]
  strip_prefix: [COS, PD, PDF]
  type_map: { Nil: nil, Int32: int, Bool: bool }
renames: [{ source: DefaultResourceCache, target: ResourceCache }]
consolidate: [{ source: "Operator*", target: process_operator }]
owner_aliases: [{ source: contentstream, target: content_stream }]
```

Drive the full reconciliation:

```bash
"${SKILL_DIR}/scripts/reconcile_parity.sh" . <source-path> <source-language> <target-dir> [rules-file]
# e.g. Java -> Crystal
"${SKILL_DIR}/scripts/reconcile_parity.sh" . vendor/pdfbox java src plans/parity_rules.yml
```

The wrapper enables Chiasmus's persistent per-file extraction cache for both
facts runs. Set `PORT_RECONCILE_CACHE_DIR` to choose its location (otherwise it
uses `CHIASMUS_CACHE_DIR` or the platform cache default). With a Chiasmus binary
that advertises `chiasmus-discover --cache-dir`, generated Java, Crystal, and Go
manifests use the same cache; older discovery bundles keep their prior behavior.
The wrapper requires the typed declaration and bundle capabilities and checks
their CLI flags before extraction. It rejects older or mixed binary versions;
run the install preflight before a strict refresh.

Outputs in `plans/generated/parity/<language>/`:

- `maps.tsv` - `matched` / `ambiguous` / `unmapped_source` per source entity
- `surfaces.tsv` - arity drift on matched method pairs
- `divergences.tsv` - `falsely_missing` / `falsely_ported` ledger disagreements
- `maps.pl` - a Prolog program (`maps_to/2`, `surface_ok/1`, `incomplete/1`)
  queryable via `swipl` or the MCP `chiasmus_verify` tool

Control scope with `PORT_SCOPE_EXCLUDE` (comma-separated paths/globs, e.g.
`debugger,tools,benchmark,examples`); it is passed to `chiasmus-facts --exclude`
(repeatable) so out-of-scope trees stop inflating the map. `divergences.tsv`
columns: `source_id kind inventory_status map_status divergence target_name
target_file target_owner basis`.

See the tool docs `chiasmus.cr/docs/parity-rule-data.md` for the full schema,
authoring workflow, and the worked PDFBox example.

## Vendor refresh & re-reconcile

When the upstream/vendor source moves (submodule bump, new tag), the generated
manifests and reconciliation go stale while the curated ledger and
`plans/parity.md` stay authoritative. Re-derive the generated layer without
clobbering curated work:

1. Bump the vendor checkout and record the new revision (ledger notes or PR):

   ```bash
   git -C vendor/<upstream> fetch --tags
   git -C vendor/<upstream> checkout <new-tag-or-sha>
   ```

2. Refresh generated manifests and re-run drift checks, preserving the curated
   port inventory:

   ```bash
   "${SKILL_DIR}/scripts/ensure_parity_plan.sh" . <source_path> <language> auto 1
   ```

   `REFRESH=1` regenerates `<language>_source_parity.tsv` /
   `<language>_test_parity.tsv` and re-runs `check_*`. It never overwrites the
   curated `<language>_port_inventory.tsv`; never run `generate_port_inventory.sh`
   against a live ledger.

3. Re-derive the reconciliation (idempotent):

   ```bash
   "${SKILL_DIR}/scripts/reconcile_parity.sh" . <source_path> <language> <target-dir> plans/parity_rules.yml
   ```

4. Diff against the previous run and triage. For facts-level drift use
   `chiasmus-plan refresh --previous-facts <previous>.pl`, then review
   `maps.tsv` (new `unmapped_source` / `ambiguous`), `surfaces.tsv` (new arity
   drift), and `divergences.tsv` (new `falsely_missing` / `falsely_ported`).

5. Update the curated ledger rows and `plans/parity.md` for the changes, then
   re-run adversarial signoff:

   ```bash
   "${SKILL_DIR}/scripts/verify_parity_adversarial.sh" . <source_path> <language> 'crystal spec' '<upstream test command>'
   ```

Guardrail: the generated layer is disposable; the curated `port_inventory.tsv`
and `plans/parity.md` are not. Regenerate freely, re-curate deliberately.

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
