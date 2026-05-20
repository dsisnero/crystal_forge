---
description: Initialize a Crystal project for language-porting work by creating baseline project structure, adding upstream as a git submodule, wiring quality gates, and documenting source-of-truth constraints. Use when starting a new Crystal port or retrofitting an existing Crystal repo for structured upstream parity work.
name: initialize-crystal-porting-project
---
# Initialize Crystal Porting Project

## Goal

Create a clean project baseline so later implementation can be done with
`porting-to-crystal` and `cross-language-crystal-parity` (for source parity inventory
across Go, Rust, Crystal, Java, and Ruby).

## Inputs to Collect

Collect these values before making edits:

1. Upstream repository URL.
2. Optional upstream subdirectory (for example `x/ansi`).
3. Port name (default: upstream repo name).
4. Submodule path (default: `vendor/<port-name>`).
5. Upstream ref policy: track `main` or pin a specific tag/commit.

If no submodule exists yet, ask these required questions explicitly:

1. "Do you want to add upstream as a git submodule?"
2. "Where is the source code to port?"
   1. project root
   2. subdirectory in this repo (provide path)
   3. other path (provide explicit path)

Explain briefly when asked:

- a git submodule is a pinned external repository checkout embedded in this
  repo, used for reproducible upstream parity.

## Setup Workflow

### 1) Add upstream as submodule

Default flow:

```bash
git submodule add -b main <source_url> vendor/<port-name>
```

If pinning immediately:

```bash
git -C vendor/<port-name> fetch --tags
git -C vendor/<port-name> checkout <tag-or-commit>
```

### 2) Ensure Crystal quality dependencies

Ensure `shard.yml` includes ameba as a development dependency:

```yaml
development_dependencies:
  ameba:
    github: crystal-ameba/ameba
    version: ~> 1.0
```

Add runtime dependencies only when required for parity with upstream behavior.

Ensure `.ameba.yml` baseline includes at least the shared template entries from:
`/Users/dominic/.agents/skills/crystal_forge/skills/crystal-forge-setup-project/templates.ameba.yml`

### 3) Ensure baseline automation commands

Project should expose these commands (via `Makefile` or equivalent):

- `install`
- `update`
- `format`
- `lint`
- `test`
- `clean`

Preferred Crystal gates:

```bash
crystal tool format --check src spec
ameba src spec
crystal spec
```

### 4) Add docs baseline

Create/update:

- `README.md`: merge local README content with relevant upstream submodule
  README content (do not replace wholesale).
  Required README markers:
  - explicit statement: `This repository is a Crystal port of <upstream-url>`.
  - pinned upstream ref (tag/commit) used for current parity work.
  - section heading: `## Upstream README Highlights` summarizing key upstream
    workflow/usage context copied from the submodule README.
- `AGENTS.md`: define source-of-truth policy and contributor workflow.
- `docs/`: add architecture/development/testing/coding/pr-workflow stubs if
  missing.

### 5) Handoff to implementation skills

After initialization:

- Use `porting-to-crystal` for translation and parity execution.
- Use `cross-language-crystal-parity` when inventory/drift tracking is needed for Go,
  Rust, Crystal, Java, or Ruby upstreams.
- Use `find-crystal-shards` only when dependency replacement decisions are
  required.

### 6) Bootstrap parity inventory plan

Before implementation begins, create/validate inventory manifests:

```bash
./bin/ensure_parity_plan.sh . <source_path> <language> auto 0
```

This establishes `plans/inventory/*` as the project parity ledger from day one.

### 7) Verify baseline outputs deterministically

Run baseline verifier after setup and before first major parity pass:

```bash
/Users/dominic/.agents/skills/crystal_forge/skills/initialize-crystal-porting-project/scripts/verify_initialized_project_baseline.sh <project_root>
```

This checks expected initialization elements in:

- `Makefile` targets (`install`, `update`, `format`, `lint`, `test`, `clean`)
- `.ameba.yml`
- `.rumdl.toml` (or `.rumdl`)
- `docs/` baseline files
- `.gitignore` sanity (`.crystal-cache/` ignored, `docs/` not ignored)
- `README.md` port/source attribution and upstream-README merge markers

## Completion Checklist

1. Submodule exists at agreed path and resolves to intended ref.
2. `shard.yml` has required dev dependencies.
3. Quality gate commands are present and runnable.
4. README/AGENTS/docs exist and describe upstream source-of-truth constraints.
5. Inventory plan is bootstrapped under `plans/inventory/`.
6. Baseline verifier passes for setup artifacts.
7. Next skill handoff is explicit in notes/PR.

## Related Skills

- [porting-to-crystal](/Users/dominic/.agents/skills/crystal_forge/skills/porting-to-crystal/SKILL.md)
- [cross-language-crystal-parity](/Users/dominic/.agents/skills/crystal_forge/skills/cross-language-crystal-parity/SKILL.md)
- [find-crystal-shards](/Users/dominic/.agents/skills/crystal_forge/skills/find-crystal-shards/SKILL.md)
- [crystal-forge-setup-project](/Users/dominic/.agents/skills/crystal_forge/skills/crystal-forge-setup-project/SKILL.md)
