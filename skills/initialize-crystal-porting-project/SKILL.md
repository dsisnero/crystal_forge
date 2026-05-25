---
name: initialize-crystal-porting-project
description: Initialize a Crystal porting repo with upstream source checkout, baseline gates, and source-of-truth documentation. Use when starting a new port or retrofitting an existing Crystal repo for structured parity work.
---

# Initialize Crystal Porting Project

Use this skill to create the project baseline before real porting starts.

## Inputs

Collect the minimum missing facts:

1. upstream repository URL
2. optional upstream subdirectory
3. port name if it should differ from the repo name
4. submodule path if it should differ from `vendor/<port-name>`
5. whether to track `main` or pin a tag/commit

If no upstream checkout exists, explicitly ask whether the source should be
added as a git submodule and where the source-of-truth lives.

## Workflow

### 1. Add upstream checkout

Prefer a git submodule:

```bash
git submodule add -b main <source_url> vendor/<port-name>
```

Pin a tag or commit immediately if that is the agreed policy.

### 2. Ensure Crystal baseline tooling

- `shard.yml` should include `ameba` as a development dependency.
- Add runtime dependencies only when parity work actually needs them.
- Reuse the shared `.ameba.yml` baseline from `crystal-forge-setup-project`.

### 3. Ensure standard repo commands

Expose at least:

- `install`
- `update`
- `format`
- `lint`
- `test`
- `clean`

For Crystal repos, prefer `format`, `ameba`, and `crystal spec` gates.

### 4. Add docs baseline

Create or update:

- `README.md` with clear upstream attribution and pinned source revision
- `AGENTS.md` with source-of-truth and contributor workflow
- missing docs under `docs/`

Do not replace useful local content wholesale; merge with it.

### 5. Bootstrap the parity plan

```bash
./scripts/ensure_parity_plan.sh . <source_path> <language> auto 0
```

This should establish `plans/inventory/*` from day one.

### 6. Verify setup

Run:

```bash
./scripts/verify_initialized_project_baseline.sh <project_root>
```

## Completion

Initialization is complete when:

1. upstream checkout exists at the agreed ref
2. baseline quality gates are present
3. README and AGENTS document the source of truth
4. `plans/inventory/*` exists
5. the baseline verifier passes

## Route next

- implementation work: `porting-to-crystal`
- inventory and drift checks: `cross-language-crystal-parity`
- dependency selection: `find-crystal-shards`
