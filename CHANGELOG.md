# Changelog

All notable user-facing changes to this project will be documented in this file.

Changes are grouped by release date and category. Only user-facing changes
are included — internal refactors, test updates, and CI changes are omitted.

## [Unreleased]

## [1.12.5] - 2026-11-23

### Fixed

- `migrate_crystal_refs.py --port-dir` indexes the port with `chiasmus-discover`
  (`path::kind::qualified_name`) instead of `chiasmus-facts`, so emitted refs are
  exactly the ids `check_port_inventory --crystal-source` validates. The facts
  vocabulary differs (`function` vs `method`, module-qualified names), which made
  every migrated ref fail validation; `--port-facts` remains for callers that
  already have facts.


## [1.12.4] - 2026-11-23

### Fixed

- `check_kind_vocabulary.py` treats TypeScript `field_prop` (interface and
  object-type property signatures) as auxiliary, next to `field`. The extractor
  emits it for every interface member, so a TypeScript gate reported 479
  "dropped" rows that no ledger ever tracked — the misleading kind of finding
  that makes a gate ignorable.


## [1.12.3] - 2026-11-23

### Changed

- Multi-target `crystal_refs` have one canonical written form: comma-separated
  with no spaces (`src/a.cr,src/b.cr::method::X`). The tab-delimited field needs
  no quoting, and `split(",")` is what every consumer already does. Parsing stays
  liberal (`;`, ` + `) for older ledgers.
- `migrate_crystal_refs.py` now rewrites each ref independently instead of
  collapsing the row to one symbol: unmatched refs are preserved, resolved ones
  become symbol refs, duplicates are dropped, and the fallback global name search
  only runs when no ref in the row matched its own file (so a resolved row cannot
  sprout guesses from unrelated files).
- `--strict-refs` / `PORT_REF_STRICT=1` reject legacy separators, for repos that
  want to parse and write exactly one form.


## [1.12.2] - 2026-11-23

### Fixed

- `check_port_inventory` and `migrate_crystal_refs` split `crystal_refs` on `,`,
  `;` and ` + `. A real Java ledger wrote `a.cr + b.cr` for multi-target rows,
  which the comma-only splitter turned into one nonexistent path (26 gate errors
  on rows that were, mostly, fine).
- Later refs are resolved relative to the first ref's directory when the direct
  path is missing (`src/graphics/shading.cr + shading/type1.cr`), and a still
  unresolved path now reports the base it tried.

### Changed

- `SKILL.md` documents the accepted separators; the sibling rule is a fallback,
  not a substitute for complete paths.


## [1.12.1] - 2026-11-23

### Fixed

- `check_kind_vocabulary.py` merges several `--scan` roots for one language
  instead of letting the last root win; Java modules and Crystal `src` + `spec`
  trees were silently under-counted.
- `vendor_drift.py` gains `--prefix-mode path` (with `--prefix-root`) for
  multi-module vendors such as Java, where `pdfbox/src/main/java` and
  `fontbox/src/main/java` both collapsed to a `java/` prefix. Duplicate
  declaration ids across roots now fail loudly instead of overwriting.
- `migrate_crystal_refs.py` reports a ref that names a directory as `coarse` and
  a ref whose file is gone as `missing` (stages 5 and 6) instead of name-matching
  them globally. On a real Java ledger that turned 1,989 bogus "stale file ref"
  hits into 6,265 honest coarse refs and 26 missing paths.
- `check_port_inventory` gains `PORT_REQUIRE_FILE=1` / `--require-file` so a
  directory ref can be rejected; the existence check alone accepted `src`.


## [1.12.0] - 2026-11-23

### Added

- `check_kind_vocabulary.py` gates each language's curated kind set against what
  `chiasmus-discover` actually emits, reporting the dropped declaration kinds
  with row counts. It reads `CURATED_KINDS` from `parity_inventory_lib.rb` so the
  vocabulary keeps one source of truth, and excludes auxiliary rows
  (`params`, `field`, `reference.call`, `definition.*`) that no curated set
  should contain — without that split a Go check reports thousands of false
  drops.
- `migrate_crystal_refs.py` rewrites a ledger's `crystal_refs` from file paths to
  symbol ids (`path::kind::qualified_name`) in a copy, staging every row as
  qualified-in-file, bare-in-file, symbol-elsewhere (stale file ref), or
  unresolved. It never guesses: unresolved rows are usually many-to-one collapse
  and need an explicit decision.
- `vendor_drift.py` reports a vendor bump per declaration instead of per path:
  added / removed / moved, visibility, the phase inherited from the path triage,
  and the ledger status — including rows that still claim `ported` for
  declarations upstream deleted.

### Changed

- `check_port_inventory` accepts `path::kind::name` refs. The file half stays
  authoritative (the `::` form passes `split(":")`), malformed symbol refs fail,
  and setting `PORT_CRYSTAL_SOURCE=src` additionally verifies that discovery
  emits the named Crystal symbol.
- `cross-language-crystal-parity` documents the three `crystal_refs` forms, the
  aggregate policy for many-to-one rows, the curated-kind gate, and a
  per-declaration vendor drift step alongside the existing facts-level one.

### Fixed

- Go parity manifests retain native `class`, `function`, and `interface`
  declarations alongside the historical regex kinds. Generated source parity
  manifests and port inventories declare their kind scope in a `# kinds=`
  comment so drift checks detect a new kind or a missing final row of a kind.
- The native-Go fixture now expects `type::Counter` alongside the other native
  declarations, matching the shipped discovery vocabulary.

## [1.11.0] - 2026-11-17

### Added

- `check_port_inventory` now fails on a `crystal_refs` entry whose file no
  longer exists. The ledger joins two churning trees, so a renamed, split or
  deleted Crystal file otherwise leaves rows pointing nowhere with nothing to
  notice — 522 stale paths and 22 dangling refs survived several releases in a
  real port before this check. Line anchors stay advisory (the file is checked,
  not the line).
- `{{INVENTORY_COMMAND}}` placeholder and the ledger gate in
  `templates.AGENTS.md`'s definition of done, plus the rule that the ledger is a
  current-state artifact of the pinned baseline: re-base it at each release and
  keep per-release history in `plans/inventory/v<NN>_delta_triage.tsv`.
- `{{PARITY_SKILL_DIR}}` and `{{PARITY_PARSER}}` placeholders and a **Parity
  tooling** section in `templates.AGENTS.md`, so a generated port repo runs the
  installed skill's own scripts and records which discovery vocabulary its
  ledger uses instead of inheriting a silent copy.
- `verify_skill_install.sh` reports `PARITY_DISCOVERY_BACKEND`, because a
  requested parser mode and an installed grammar gem do not prove tree-sitter
  ran.

### Changed

- `cross-language-crystal-parity`'s invariants state both rules, with the
  measured cost of ignoring them (a v0.42-keyed ledger targeting v0.43 had 2,362
  stale and 2,188 absent rows — 39% still matched), and the drift checks are
  described as gates rather than release-time chores.
- Port entrypoints warn that older copied `parity_inventory_lib.rb` versions
  keep a `tree-sitter` branch that still calls `discover_with_regex`; such a run
  can warn and exit successfully while emitting regex ids. Diagnose the script
  actually invoked, not the mode requested.

## [1.10.0] - 2026-10-19

### Added

- Portable `AGENTS.md` template (`templates.AGENTS.md`) and `docs/resuming.md`
  template (`templates.resuming.md`) for any porting repo, with per-repo
  placeholders for the upstream pin, vendor path, gates, and plan paths.
- `templates/parity_plan.md` in `cross-language-crystal-parity`, including the
  **Where we are** resume block.
- Resume contract shared by `crystal-forge-setup-project`,
  `initialize-crystal-porting-project`, `porting-to-crystal`, and
  `cross-language-crystal-parity`: entrypoint structure, session start/end
  steps, plan refresh, and atomic per-feature commits.

### Changed

- `initialize-crystal-porting-project` baseline verifier now checks the agent
  entrypoint (resume block, principles, session continuity, definition of done,
  commit prefix, no leftover placeholders) and `docs/resuming.md`.

### Fixed

- Rust parity discovery now retains the native Chiasmus `function`, `class`, and
  `interface` declarations emitted by strict tree-sitter discovery alongside the
  historical `func`, `struct`, and `trait` labels, instead of silently dropping
  them from generated source and test manifests.

## [1.9.0] - 2026-10-19

### Added

- Verified-cache Chiasmus installer with exact release pins and offline reuse.
- Workspace skill refresh and drift checks that preserve origin metadata and
  link supporting resources to canonical sources.
- Real-release consumer verification through discovery and reconciliation.

### Fixed

- Relative repository roots now resolve reconciliation rules correctly.
- The legacy release sync command uses the verified installer instead of
  assembling incomplete binary bundles inside the skill.
- Windows wrappers select packaged executables, and explicit regex discovery
  avoids toolchain resolution.
- Skill documentation and shell lint findings, including stale installation
  instructions and workspace resource copies.

## [1.4.0] — 2026-05-25

### Changed
- **Skill library**: Reduced instruction redundancy across all Crystal Forge
  skills and standardized them around tighter trigger, routing, workflow, and
  guardrail sections so the skills are easier to load and follow.
- **Bubble Tea parity skills**: Simplified orchestration, golden-generation,
  and example-parity guidance while preserving the handoff boundaries between
  workflow, example, and shard-fix ownership.
- **Crystal project and porting skills**: Compressed setup, initialization,
  performance, shard-patching, dependency-selection, and porting workflows into
  shorter operational guides with the same core constraints.
- **cross-language-crystal-parity**: Consolidated parity-plan guidance into a
  smaller workflow centered on curated `plans/parity.md`, manifest ownership,
  and adversarial signoff.

### Fixed
- **cross-language-crystal-parity references**: Corrected supporting guidance
  to consistently refer to `plans/parity.md` instead of the older repo-root
  `parity.md` path.

## [1.3.0] — 2026-05-25

### Changed
- **cross-language-crystal-parity**: Refined parity.md policies with granular
  red-green TDD cycles, upstream source/test reading requirements, and
  small-commit checkpoint discipline for feature-level parity tracking.
- **porting-to-crystal**: Aligned porting loop with parity.md feature-level
  workflow; added Rust source-reading step, small-commit checkpoint policy,
  and full gate suite verification before feature completion.

### Fixed
- **parity_inventory_lib**: Fixed AppleDouble (`._*`) file filtering by
  checking each path segment instead of the full path prefix, avoiding
  false negatives with nested paths.
