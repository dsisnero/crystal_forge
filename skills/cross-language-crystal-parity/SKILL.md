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
skill. Regex extractor lists and curated-kind filters are language-specific;
inspect both when adopting a new native discovery vocabulary.

Read `references/usage-guidelines.md` or `references/invariants.md` only when
you need the extra detail.

## Artifacts

- Session entrypoint: `AGENTS.md` (often symlinked to `CLAUDE.md`) with a
  **How to resume** block that points at `plans/parity.md`
- Curated feature plan: `plans/parity.md` (skeleton:
  `templates/parity_plan.md`)
- Curated working ledger: `plans/inventory/<language>_port_inventory.tsv`
- Generated manifests:
  - `plans/inventory/<language>_source_parity.tsv`
  - `plans/inventory/<language>_test_parity.tsv`
- Optional deterministic notes:
  - `plans/inventory/<language>_source_notes.tsv`

## Resumable plan contract

`plans/parity.md` is the first thing a new session reads, so it must carry the
state instead of leaving it in git history or chat:

- Start the file with a `## Where we are` block containing **Current focus**,
  an ordered **Next up** list, status by area, scoping notes/gotchas, the last
  commit, and the current gate results.
- Keep per-symbol detail in the ledger, not in the plan.
- Refresh the block after every feature, before committing and before ending a
  session. A stale block is a broken resume path.
- If the file grows too large, split areas into `plans/parity/<area>.md`, link
  each from `plans/parity.md`, and name the file being worked on plus the next
  one.
- Repo-level rules (gates, definition of done, commit message) live in
  `AGENTS.md`; the plan links to them instead of restating them.

Use `templates/parity_plan.md` when the plan does not exist yet, and
`crystal-forge-setup-project/templates.AGENTS.md` +
`crystal-forge-setup-project/templates.resuming.md` for the entrypoint and
`docs/resuming.md`.

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
- `scripts/check_kind_vocabulary.py` (gate the curated kind sets)
- `scripts/migrate_crystal_refs.py` (file refs -> symbol refs)
- `scripts/vendor_drift.py` (per-declaration vendor bump report)

The three Python tools resolve `chiasmus-discover` / `chiasmus-facts` through
`resolve_toolchain.py`, exactly like the shell wrappers, and accept an explicit
`--discover-bin` / `--facts-bin` override for local work.

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
generated manifests. Go and Rust admit both native and historical vocabularies.

| Native Chiasmus label | Go declaration | Rust declaration |
| --- | --- | --- |
| `function` | free function | free function |
| `class` | struct | struct or enum |
| `interface` | interface | trait |

Go retains the historical regex labels `func`, `struct`, and `type`. Rust retains
`func`, `struct`, `enum`, and `trait`. The Go curated defaults exclude auxiliary
captures such as `definition.type`, `field`, `package`, and `reference.call`.
Removing historical labels or renaming native labels changes which IDs can
appear in a manifest. Treat those changes as migrations.
Never copy the native discovery `status` column into a curated ledger: discovery
identifies symbols, it does not sign off Crystal implementation.

The split matters because discovery writes declaration rows and auxiliary rows
into the same TSV. A curated set can only drop declarations, so run the gate
before trusting a generated ledger:

```bash
python3 "${SKILL_DIR}/scripts/check_kind_vocabulary.py" \
  --scan rust=vendor/upstream/crates/core/src --scan go=vendor/upstream
```

A non-empty `dropped` list means a whole category is missing from the manifests
and the counts say how many rows. Prove the gate itself by re-running it with
`--curated-override rust=const,struct,enum,trait,type,func,method,test`; it must
report the drops (the historical `function`/`class`/`interface` gap).

### Existing repositories with copied parity scripts

Inspect the script actually invoked by the repository before diagnosing a parser
failure. Older copied `scripts/parity_inventory_lib.rb` versions contain a
placeholder `tree-sitter` branch that still calls `discover_with_regex`; their
`PORT_PARSER=tree-sitter` mode may warn and exit successfully. Installing the
Ruby `tree_sitter` gem changes the warning, not extraction. Use this skill's
canonical scripts directly, or deliberately migrate the repository's wrappers
to them. Do not call a repository gate blocked when its regex check exits zero.

Confirm the effective backend with `PARITY_DISCOVERY_BACKEND` and the generated
manifest's `.metadata.json`; a requested parser mode does not prove which
extractor ran. In the canonical scripts, explicit `tree-sitter` mode requires a
verified `chiasmus-discover` toolchain and fails if it cannot run. `auto` can
fall back to regex, so pin `PORT_PARSER=regex` when maintaining a ledger created
with that vocabulary until a reviewed migration is complete.

For new Go manifests, strict discovery retains the native declarations listed
above alongside `const` and `method`. To migrate an existing regex-based Go
ledger, generate a separate native candidate and review it against the curated
baseline. Named types such as `type Counter int` can appear only as
`definition.type`, which is outside the curated defaults. Audit these types
and review any duplicate captures before mapping IDs to preserve curated
coverage and implementation status.

## Scope and preflight

Use `PORT_SCOPE_INCLUDE` (comma-separated roots relative to the upstream source)
and `PORT_SCOPE_EXCLUDE` (comma-separated relative globs) to make a workspace
scope explicit. Every generated TSV has a sibling `.metadata.json` recording
the effective backend, discovery command, and effective scope.

New source parity manifests and port inventories declare their complete curated
source-kind scope in a `# kinds=` comment. The checkers use the declared kinds
even when a kind has no rows in the manifest. Keep the comment when editing
rows so the checker detects new declarations and deletions of the last row of
a tracked kind. Existing ledgers without a kind header continue to infer kinds
from their IDs. To retain a reviewed narrower scope explicitly, list its kinds
separated by commas in one comment, for example `# kinds=class,const`.

Run `scripts/verify_skill_install.sh <target-root> <language> tree-sitter`
before a strict downstream refresh. It verifies wrapper permissions and executes
a minimal tree-sitter discovery probe. `auto` remains allowed to report regex
when no discovery binary is available; `tree-sitter` fails instead.

## Canonical script execution

When adopting the skill in a porting repository, add a **Parity tooling** section
to its `AGENTS.md` (and the matching `docs/resuming.md` step). Name the current
installed skill directory, the parser mode used by the curated ledger, and the
inventory command. Require that command to invoke the installed skill's current
scripts directly or through forwarding wrappers, never a copied implementation.
The `crystal-forge-setup-project/templates.AGENTS.md` template contains the
starter section. Retrofit existing entrypoints as well as new ones; installing
a newer skill does not rewrite a repository's copied scripts or instructions.

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
`plans/parity.md`. If the plan does not exist yet, seed it from
`templates/parity_plan.md` and fill the **Where we are** block.

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
8. Refresh the **Where we are** block (current focus, next up, last commit,
   gate results) so the next session can resume without reading git history.

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

Wire these into the repo's own gates (a `make inventory` target plus the
definition of done) — a check that only runs at release time does not run. The
inventory check also fails on a `crystal_refs` entry whose file no longer
exists, which is the failure mode that silently accumulates whenever this repo's
own files move.

When the pinned upstream release changes, **re-base** the ledger rather than
appending to it, and write the release's added/modified/deleted symbols to
`plans/inventory/v<NN>_delta_triage.tsv`.

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

4. Diff against the previous run and triage. Two views, both needed:

   - **Per declaration** (what the phases actually own):

     ```bash
     python3 "${SKILL_DIR}/scripts/vendor_drift.py" \
       --vendor vendor/<upstream> --old <previous-tag> --new <new-tag> \
       --scan-subdirs crates/core/src crates/core/tests \
       --ledger plans/inventory/<language>_port_inventory.tsv \
       --triage plans/inventory/<version>_delta_triage.tsv \
       --out plans/inventory/<version>_delta_symbols.tsv
     ```

     It reports added / removed / moved declarations with visibility, the phase
     inherited from the path triage, and the ledger status — including rows that
     still claim `ported` for declarations upstream deleted.

   - **Per fact** (what the call graph sees): `chiasmus-plan refresh
     --previous-facts <previous>.pl`, then review `maps.tsv` (new
     `unmapped_source` / `ambiguous`), `surfaces.tsv` (new arity drift), and
     `divergences.tsv` (new `falsely_missing` / `falsely_ported`).

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

### Crystal refs

Accepted forms, comma-separated when one row maps to several places:

| Form | Example | Checked |
| --- | --- | --- |
| file | `src/tea/clipboard.cr` | file exists |
| file + line anchor (advisory) | `src/tea/clipboard.cr:68-70` | file exists; lines are never compared |
| file + symbol | `src/tea/clipboard.cr::method::Bubbletea.read_clipboard` | file exists, syntax, and (with `--crystal-source`) that discovery emits the id |

The `::` form is the discovery id prefixed with the repo-relative path, so a row
can be validated instead of trusted. It also survives `check_port_inventory`'s
file check, because the file half is what `split(":")` returns.

Migrate file refs mechanically; never hand-edit a 4,000-row ledger:

```bash
python3 "${SKILL_DIR}/scripts/migrate_crystal_refs.py" \
  --ledger plans/inventory/<language>_port_inventory.tsv \
  --port-dir src --port-dir spec --port-root . \
  --out plans/inventory/<language>_port_inventory.migrated.tsv
```

It stages every row (qualified name in file, bare name in file, symbol elsewhere,
unresolved) and refuses to guess. Unresolved rows are usually **many-to-one
collapse**: 150 upstream accessors realized by a handful of Crystal methods.
Either point those rows at the one symbol or keep the file ref and mark the row
`aggregate` in `notes`; do not leave the decision implicit.

Validate symbol refs in the gate once the ledger carries them:

```bash
"${SKILL_DIR}/scripts/check_port_inventory.sh" . plans/inventory/<language>_port_inventory.tsv \
  <source_path> <language>   # add PORT_CRYSTAL_SOURCE=src to verify symbols
```
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
- Never end a session with a stale **Where we are** block: refresh focus, next
  up, last commit, and gate results before you stop.
- Do not regenerate curated ledgers on top of active manual work.
- Do not weaken upstream tests or fixtures to make Crystal look green.
- Preserve behaviorally important internal data structures when upstream
  semantics depend on them.

## Related skills

- `initialize-crystal-porting-project`
- `porting-to-crystal`
