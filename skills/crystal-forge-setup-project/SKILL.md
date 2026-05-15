---
name: crystal-forge-setup-project
description: Set up or retrofit a repository with Crystal Forge meta-structure by creating CLAUDE.md/AGENTS.md, core docs, and baseline project conventions. Use when a project lacks agent-facing guidance or needs standardized engineering documentation and command gates.
---

# Crystal Forge Project Setup

## Goal

Create a minimal, consistent project meta-structure that supports both human
contributors and agent workflows.

## Scope

This skill owns repo-level meta scaffolding only.

Use companion skills for specialized work:

- `initialize-crystal-porting-project` for source submodule + port bootstrap.
- `porting-to-crystal` for translation/parity execution.
- `forge-update-changelog` for change documentation updates.

## Workflow

### 1) Inspect current state

Check what already exists before creating files:

```bash
ls -la CLAUDE.md AGENTS.md README.md CHANGELOG.md .gitignore 2>/dev/null
ls docs 2>/dev/null
```

Detect language/tooling and only keep commands that actually exist.

### 2) Gather missing project facts

Collect only what cannot be inferred from the repository:

- one-line project purpose
- 3-5 core engineering principles
- optional project-specific conventions or constraints

Do not ask for details already discoverable from files/scripts.

### 3) Create/update `CLAUDE.md`

Include these sections:

1. Project name + one-line description.
2. Verified commands block (`install`, `update`, `format`, `lint`, `test`, etc.)
   using only real commands from `Makefile`/scripts.
3. Documentation table linking to:
   - `docs/architecture.md`
   - `docs/development.md`
   - `docs/coding-guidelines.md`
   - `docs/testing.md`
   - `docs/pr-workflow.md`
4. Core principles.
5. Commit message convention.
6. Project conventions (only if concrete and non-generic).

For Crystal projects, include Crystal gates:

```bash
crystal tool format --check src spec
ameba src spec
crystal spec
```

### 4) Ensure `AGENTS.md` points to `CLAUDE.md`

Keep guidance synchronized by symlinking:

```bash
ln -sf CLAUDE.md AGENTS.md
```

### 5) Ensure docs files exist

Create missing files under `docs/` with concise, actionable starter content:

- `architecture.md`
- `development.md`
- `coding-guidelines.md`
- `testing.md`
- `pr-workflow.md`

Do not create extra meta documentation files.

### 6) Ensure `.gitignore` baseline

If missing, create `.gitignore`. Ensure project-local tool directories and temp
artifacts are ignored when appropriate (for example `.claude/`, `temp/`, local
cache directories).

Guardrails:

- Do not ignore `docs/` (baseline documentation must be versioned).
- Ignore local Crystal cache directory `.crystal-cache/`.
- Use template baseline from:
  - `/Users/dominic/.agents/skills/crystal_forge/skills/crystal-forge-setup-project/templates.gitignore`

### 6b) Ensure `temp/` directory convention and Makefile `clean` target

All temporary files must be generated in `./temp` of the working directory to
bypass permission issues. The `./temp` directory should:

1. Exist in the repo (or be created on demand by scripts).
2. Be listed in `.gitignore`.
3. Be excluded from ameba, rumdl, and Crystal format checks.

The `Makefile` must include a `clean` target that removes temporary files:

```make
clean:
	rm -rf ./temp/*
```

If the project has no `Makefile`, create one with at minimum `clean` and
project-appropriate gates.

### 6c) Ensure Crystal lint/markdown config baselines

For Crystal projects, ensure config files exist and include at least template
baseline entries:

- `.ameba.yml` baseline from:
  - `/Users/dominic/.agents/skills/crystal_forge/skills/crystal-forge-setup-project/templates.ameba.yml`
- `.rumdl.toml` baseline from:
  - `/Users/dominic/.agents/skills/crystal_forge/skills/crystal-forge-setup-project/templates.rumdl.toml`

### 7) Validate consistency

Verify:

1. Commands in `CLAUDE.md` exist and are runnable.
2. `AGENTS.md` is a symlink to `CLAUDE.md`.
3. Docs table links resolve.
4. No duplicated policy blocks across files.

## Completion Criteria

1. `CLAUDE.md` exists with verified commands and principles.
2. `AGENTS.md` symlinks to `CLAUDE.md`.
3. Core docs exist under `docs/`.
4. `.gitignore` contains required local-only paths including `temp/`.
5. `Makefile` includes a `clean` target that runs `rm -rf ./temp/*`.
6. Crystal projects include `.ameba.yml` and `.rumdl.toml` baseline config.
7. `temp/` is excluded from ameba, rumdl, and format checks.
8. Content is concise, non-duplicative, and repository-specific.

## Related Skills

- [initialize-crystal-porting-project](/Users/dominic/.agents/skills/crystal_forge/skills/initialize-crystal-porting-project/SKILL.md)
- [porting-to-crystal](/Users/dominic/.agents/skills/crystal_forge/skills/porting-to-crystal/SKILL.md)
- [forge-update-changelog](/Users/dominic/.agents/skills/crystal_forge/vendor/forge/skills/forge-update-changelog/SKILL.md)
