---
name: crystal-forge-setup-project
description: Set up or retrofit a repo with Crystal Forge project scaffolding. Use when a repository lacks `CLAUDE.md`, `AGENTS.md`, baseline docs, or consistent local quality gates.
---

# Crystal Forge Project Setup

This skill owns repo-level scaffolding only. Use
`initialize-crystal-porting-project` for upstream submodule bootstrap and
`porting-to-crystal` for implementation work.

## Workflow

### 1. Inspect before editing

Check which of these already exist and reuse real project commands instead of
inventing generic ones:

- `CLAUDE.md`
- `AGENTS.md`
- `README.md`
- `CHANGELOG.md`
- `.gitignore`
- `docs/`
- `Makefile` or equivalent scripts

### 2. Create or tighten `CLAUDE.md`

Include only:

1. Project name and one-line purpose
2. Verified commands such as `install`, `update`, `format`, `lint`, `test`
3. Links to the core docs
4. A short principles section
5. Concrete project conventions when they are real and repo-specific

For Crystal projects, prefer:

```bash
crystal tool format --check src spec
ameba src spec
crystal spec
```

### 3. Sync `AGENTS.md`

Point `AGENTS.md` at `CLAUDE.md` with a symlink when possible:

```bash
ln -sf CLAUDE.md AGENTS.md
```

### 4. Ensure core docs exist

Create concise starter docs only for missing files:

- `docs/architecture.md`
- `docs/development.md`
- `docs/coding-guidelines.md`
- `docs/testing.md`
- `docs/pr-workflow.md`

Rules for content placement:

- **`README.md`** describes what the project is and how to use it. It must
  include links to all `docs/*` files. Do not put porting notes, upstream
  references, or implementation history in README — that goes in
  `docs/development.md`.
- **`docs/development.md`** is where porting/upstream notes, project structure,
  and workflow details live — referenced from README via a link.

### 5. Normalize repo-local temp and ignore rules

- Keep generated scratch data under `./temp`.
- Ensure `.gitignore` ignores `temp/` and `.crystal-cache/`.
- Do not ignore `docs/`.
- Use `templates.gitignore` as the baseline if a file is missing.

### 6. Ensure cleanup and lint config

- `Makefile` should expose `clean` and remove `./temp/*`.
- Crystal repos should also have:
  - `.ameba.yml` from `templates.ameba.yml`
  - `.rumdl.toml` from `templates.rumdl.toml`
- Exclude `temp/` from lint/format/documentation tooling where needed.

## Verification

Confirm all of the following:

1. Commands listed in `CLAUDE.md` exist.
2. `AGENTS.md` resolves to `CLAUDE.md`.
3. Doc links resolve.
4. Repo policy text is not duplicated across multiple files.
5. `temp/` is ignored and the cleanup path is explicit.
