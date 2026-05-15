---
name: cross-language-crystal-parity
description: Track source-to-Crystal parity by generating inventories of source API and tests, validating drift, and seeding backlog work from missing coverage. Use for Go, Rust, Crystal, Java, Ruby, or TypeScript/JavaScript upstreams when you need reproducible parity manifests instead of ad-hoc tracking, especially when tree-sitter discovery or Prolog fact queries would make the inventory more reliable.
---

# Cross-Language Crystal Parity

## Goal

Run one parity workflow across supported source languages while preserving
existing Go script compatibility.

Supported source languages:

- `go`
- `rust`
- `crystal`
- `java`
- `ruby`
- `typescript` (includes `.ts` and `.js` discovery)

Detailed operational rules live in:

- [references/usage-guidelines.md](/Users/dominic/.agents/skills/crystal_forge/skills/cross-language-crystal-parity/references/usage-guidelines.md)
- [references/invariants.md](/Users/dominic/.agents/skills/crystal_forge/skills/cross-language-crystal-parity/references/invariants.md)

## Dependencies

- `ruby` (for parity scripts)
- `rg` / [ripgrep](https://github.com/BurntSushi/ripgrep) (for adversarial verification empty-field checks and placeholder spec detection)
- Crystal discovery binary (`chiasmus-discover` or equivalent) — optional, preferred tree-sitter backend supporting 10 languages with query-pattern extraction and non-blocking concurrency
- `tree_sitter` Ruby gem — legacy fallback for tree-sitter parsing mode

## Parser Modes

All generators/checkers support parser selection:

- `auto` (default): use Crystal tree-sitter binary when available, otherwise Ruby gem, otherwise regex.
- `regex`: force regex extractors.
- `tree-sitter`: request tree-sitter grammar; checks for Crystal binary first, then Ruby gem; falls back to regex with warning if neither is available.

Set with `--parser <mode>` or `PORT_PARSER=<mode>`.

When the Crystal discovery binary is available, tree-sitter mode uses per-language S-expression query patterns to extract declarations with higher accuracy than regex. Supported languages: typescript, javascript, tsx, python, go, java, rust, ruby, crystal, scala. See the Crystal discovery module for query pattern details.

If only the Ruby gem is available (or neither), results carry a "regex fallback used" warning in the parser mode notes column.

## Generic Artifacts

- `plans/inventory/<language>_port_inventory.tsv`
- `plans/inventory/<language>_source_parity.tsv`
- `plans/inventory/<language>_test_parity.tsv`

Template headers live in:

- `templates/port_inventory.tsv`
- `templates/source_parity.tsv`
- `templates/test_parity.tsv`
- `templates/source_notes_overrides.tsv` (deterministic source-note overrides)

## Scripts

Core generators/checkers:

- `scripts/generate_port_inventory.sh`
- `scripts/generate_source_parity_manifest.sh`
- `scripts/generate_test_parity_manifest.sh`
- `scripts/check_port_inventory.sh`
- `scripts/check_source_parity.sh`
- `scripts/check_test_parity.sh`

Plan lifecycle helpers:

- `scripts/ensure_parity_plan.sh` (bootstrap missing manifests + run checks)
- `scripts/verify_parity_adversarial.sh` (independent parity signoff)

Backward-compatible Go wrappers remain available (`generate_go_*`, `check_go_*`).

Safety guard:

- `generate_port_inventory.sh` refuses to overwrite an existing
  `<language>_port_inventory.tsv` unless forced.
- `generate_source_parity_manifest.sh` refuses to overwrite an existing
  `<language>_source_parity.tsv` unless forced.
- `generate_test_parity_manifest.sh` refuses to overwrite an existing
  `<language>_test_parity.tsv` unless forced.
- Force only for intentional reset (`FORCE_OVERWRITE=1` arg or
  `PORT_FORCE_OVERWRITE=1` env var).

## Bootstrap Missing Tooling

If the target repo does not contain the parity scripts (`generate_*`,
`check_*`, `ensure_parity_plan.sh`, `verify_parity_adversarial.sh`), bootstrap
them first instead of silently treating fallback checks as equivalent.

Copy from this skill into target repo:

```bash
mkdir -p ./scripts
cp /Users/dominic/.agents/skills/crystal_forge/skills/cross-language-crystal-parity/scripts/* ./scripts/
chmod +x ./scripts/*.sh ./scripts/*.rb
```

Then run canonical parity flow from `./scripts/`.

Fallback mode is allowed only when bootstrap is not possible. In fallback mode:

1. State explicitly that results are partial (not full parity validation).
2. Run available local integrity checks.
3. Report exactly which canonical parity checks were not run.

## Parity Plan Lifecycle

### 1) Create or refresh a plan

```bash
./scripts/ensure_parity_plan.sh . vendor/upstream_repo rust auto 0
```

Arguments:

1. `ROOT_DIR`
2. `SOURCE_PATH`
3. `LANGUAGE`
4. `PARSER` (`auto|regex|tree-sitter`)
5. `REFRESH` (`0|1`) for source/test manifest regeneration
   - `REFRESH=1` intentionally regenerates source/test manifests using force
     overwrite behavior.

Expected output on success:

```text
Port inventory check passed (N items tracked).
Source parity check passed (N API items tracked).
Test parity check passed (N tests tracked).
Parity plan ready and validated for language=rust.
Manifests:
  - ./plans/inventory/rust_port_inventory.tsv
  - ./plans/inventory/rust_source_parity.tsv
  - ./plans/inventory/rust_test_parity.tsv
```

### 2) Work the plan

Update statuses in `<language>_port_inventory.tsv` as parity work progresses:

- `missing`
- `in_progress`
- `partial`
- `ported`
- `skipped`
- `intentional_divergence`

Rule: `ported`/`partial` rows must include `crystal_refs`.
Generator policy: use `-` as the explicit placeholder for unfilled fields;
do not emit empty TSV columns.

Status policy:

- `in_progress`: work started, parity not yet demonstrated, refs may stay `-`.
- `partial`: some parity exists but not complete; must include concrete
  `crystal_refs`.
- `ported`: fully parity-covered for that item; must include concrete
  `crystal_refs`.
- `intentional_divergence`: upstream item is deliberately replaced by a Crystal-native
  subsystem or cannot map 1:1; notes must name the replacement or blocker.

Ledger policy:

- Treat `<language>_port_inventory.tsv` as the working ledger.
- After onboarding, avoid re-running `generate_port_inventory.sh` on top of a
  curated ledger; use `check_port_inventory.sh` + manual status updates.
- `ensure_parity_plan.sh` is safe for active projects because it only creates
  missing manifests (it does not overwrite existing port inventory).

For deterministic exception notes, keep overrides in
`plans/inventory/<language>_source_notes.tsv` (`source_api_id<TAB>notes`) so
regeneration preserves notes.

Naming-change policy:

- When Crystal naming intentionally differs from upstream symbol naming, record
  the mapping in `crystal_refs` and explain rationale in `notes` on the
  `<language>_port_inventory.tsv` row.
- For deterministic source-manifest notes (so regeneration does not overwrite
  them), add `source_api_id<TAB>notes` entries to
  `plans/inventory/<language>_source_notes.tsv` and regenerate source parity.

### 2b) Curated vs Generated Files

Treat these files differently:

- Curated working ledger:
  - `plans/inventory/<language>_port_inventory.tsv`
- Generated/refresh manifests:
  - `plans/inventory/<language>_source_parity.tsv`
  - `plans/inventory/<language>_test_parity.tsv`
- Curated deterministic source-note overrides:
  - `plans/inventory/<language>_source_notes.tsv`

Day-to-day policy:

- Update progress/mapping notes primarily in `<language>_port_inventory.tsv`.
- Run `check_*` scripts continuously.
- Regenerate source/test manifests only for intentional refresh from upstream drift.

Implementation parity reminder:

- Do not simplify stateful internals just because the surface algorithm looks equivalent.
- For Java ports in particular, preserve data-structure shape when behavior depends on it
  (for example, `PDFTextStripper` duplicate-overlap suppression uses nested x/y maps;
  flattening that logic can silently drop glyphs while still looking close on simple fixtures).
- Keep upstream test setup exact when porting fixtures. Do not carry forward local debug toggles
  or convenience overrides into parity specs; for example, changing `suppressDuplicateOverlappingText`
  in a Crystal spec when the Java test leaves it at the default can create false parity failures that
  look like engine bugs.

### 3) Re-validate drift continuously

```bash
./scripts/check_port_inventory.sh . plans/inventory/rust_port_inventory.tsv vendor/upstream_repo rust
./scripts/check_source_parity.sh . plans/inventory/rust_source_parity.tsv vendor/upstream_repo rust
./scripts/check_test_parity.sh . plans/inventory/rust_test_parity.tsv vendor/upstream_repo rust
```

What each checker validates:

- `check_port_inventory.sh`
  - discovered source/test IDs are represented in `<language>_port_inventory.tsv`
  - no stale IDs remain
  - status vocabulary is valid
  - `partial`/`ported` rows include `crystal_refs`
- `check_source_parity.sh`
  - discovered source API IDs match `<language>_source_parity.tsv`
  - no stale/missing source API IDs
  - source status vocabulary is valid (`mapped|partial|missing`)
- `check_test_parity.sh`
  - discovered source test IDs match `<language>_test_parity.tsv`
  - no stale/missing test IDs
  - test status vocabulary is valid

## Queryable Inventory Facts

For large ports, generate Prolog facts from the manifests so conversion rules and gaps can be queried instead of manually scanned:

```bash
./scripts/generate_inventory_facts.rb \
  --inventory plans/inventory/typescript_port_inventory.tsv \
  --source plans/inventory/typescript_source_parity.tsv \
  --tests plans/inventory/typescript_test_parity.tsv \
  --rules plans/inventory/conversion_rules.tsv \
  > plans/inventory/parity_facts.pl
```

Useful facts include `missing_item(Id).`, `partial_item(Id).`, `intentional_divergence(Id, Notes).`, and `conversion_rule(FromLanguage, ToLanguage, UpstreamKind, CrystalKind, Notes).`

Use this for recurring mapping rules such as TypeScript `Promise<T>` to Crystal `Channel(T)`, Tau Prolog to crolog/SWI-Prolog, or dynamic module discovery to explicit Crystal registration.

## Adversarial Verification

Use a second, independent pass before parity signoff:

```bash
./scripts/verify_parity_adversarial.sh . vendor/upstream_repo rust \
  'crystal spec' \
  'cargo test'
```

What it enforces:

1. Plan/manifests exist and pass all drift checks.
2. Manifest rows have no empty TSV columns (`\t\t` or trailing tabs).
3. Inventory row quality (`ported`/`partial` rows include refs).
4. No placeholder specs in `src/`/`spec` (`pending`, `xit`, etc.).
5. Optional Crystal and upstream test command success.

Expected output on success:

```text
Port inventory check passed (N items tracked).
Source parity check passed (N API items tracked).
Test parity check passed (N tests tracked).
Parity plan ready and validated for language=rust.
Manifests:
  - ./plans/inventory/rust_port_inventory.tsv
  - ./plans/inventory/rust_source_parity.tsv
  - ./plans/inventory/rust_test_parity.tsv
Adversarial parity verification passed for language=rust.
```

Recommended process: run this in a separate review pass (or CI job) from the
implementation pass.

## Usage Examples

Generate inventory:

```bash
./scripts/generate_port_inventory.sh . plans/inventory/java_port_inventory.tsv vendor/upstream_repo java
```

Intentional reset only:

```bash
./scripts/generate_port_inventory.sh . plans/inventory/java_port_inventory.tsv vendor/upstream_repo java 1
```

Generate source/test parity manifests:

```bash
./scripts/generate_source_parity_manifest.sh . plans/inventory/java_source_parity.tsv vendor/upstream_repo java
./scripts/generate_test_parity_manifest.sh . plans/inventory/java_test_parity.tsv vendor/upstream_repo java
```

Intentional reset only:

```bash
./scripts/generate_source_parity_manifest.sh . plans/inventory/java_source_parity.tsv vendor/upstream_repo java "" "" 1
./scripts/generate_test_parity_manifest.sh . plans/inventory/java_test_parity.tsv vendor/upstream_repo java 1
```

Source-notes overrides example:

```bash
./scripts/generate_source_parity_manifest.sh . plans/inventory/go_source_parity.tsv vendor/huh go plans/inventory/go_source_notes.tsv
```

## Related Skills

- [initialize-crystal-porting-project](/Users/dominic/.agents/skills/crystal_forge/skills/initialize-crystal-porting-project/SKILL.md)
- [porting-to-crystal](/Users/dominic/.agents/skills/crystal_forge/skills/porting-to-crystal/SKILL.md)
