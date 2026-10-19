---
name: crystal-forge-setup-project
description: Set up or retrofit a repo with Crystal Forge project scaffolding. Use when a repository lacks `CLAUDE.md`, `AGENTS.md`, baseline docs, or consistent local quality gates, or when the entrypoint needs a resumable session-continuity and definition-of-done section.
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

### 2. Create or tighten the agent entrypoint

Use `templates.AGENTS.md` (next to this `SKILL.md`) as the baseline for the
agent entrypoint file, then fill the placeholders and delete anything that does
not apply. It is written to work in any repository: the upstream project,
vendor path, gates, and plan paths are all placeholders.

Include only:

1. Project name and one-line purpose (for ports: "Crystal port of X from Y,
   vendored at `<vendor-path>` (release/commit)"). The vendor path varies per
   repo — never copy another project's `vendor/<name>`.
2. Verified commands such as `install`, `update`, `format`, `lint`, `test`
3. Links to the core docs
4. A short principles section
5. A **How to resume** block plus the **Definition of done** and commit message
   conventions (see step 2a)
6. Concrete project conventions when they are real and repo-specific

For Crystal projects, prefer:

```bash
crystal tool format --check src spec
ameba src spec
crystal spec
```

### 2a. Make the entrypoint resumable

The first screen of the entrypoint must tell a new session how to recover
state without reading git history:

- a `**How to resume:**` blockquote that names the parity plan
  (`plans/parity.md` by default), its **Where we are** block, and the gates to
  run;
- a **Session continuity** section with the three start-of-session steps
  (read where we are → skim `git log`/`git status` → run the gates);
- a **Definition of done** section listing the API, tests, gates, inventory,
  plan refresh, and divergence-documentation requirements;
- the commit message convention (`port: <feature>` plus bullets and the pin).

For porting repos, also install `docs/resuming.md` from
`templates.resuming.md` and track the plan with
`cross-language-crystal-parity` (its `templates/parity_plan.md` provides the
**Where we are** block). For a non-port repo, drop the parity-specific bullets
and keep the resume/gates/definition-of-done structure.

### 2b. Template placeholders

`templates.AGENTS.md` and `templates.resuming.md` use `{{TOKEN}}` placeholders.
Substitute all of them; the names vary per repo, so never inherit another
project's values:

| Token | Meaning | Example |
| --- | --- | --- |
| `{{PROJECT_NAME}}` | repo/port name | `parquet-cr` |
| `{{UPSTREAM_PROJECT}}` | upstream component | `parquet` crate |
| `{{UPSTREAM_LANGUAGE}}` | upstream language | `Rust` |
| `{{UPSTREAM_REPO}}` | upstream `owner/name` | `apache/arrow-rs` |
| `{{UPSTREAM_URL}}` | upstream URL | `https://github.com/apache/arrow-rs` |
| `{{UPSTREAM_RELEASE}}` | pinned release/tag | `60.0.0` |
| `{{UPSTREAM_COMMIT}}` | pinned commit SHA | `ef1fa157...` |
| `{{VENDOR_PATH}}` | upstream checkout path | `vendor/arrow-rs` |
| `{{SOURCE_LANGUAGE}}` | inventory language prefix | `rust` |
| `{{PARITY_PLAN}}` | curated plan path | `plans/parity.md` |
| `{{PARITY_PLAN_DIR}}` | plan split directory | `plans` |
| `{{INVENTORY_DIR}}` | ledger directory | `plans/inventory` |
| `{{LINT_COMMAND}}` / `{{TEST_COMMAND}}` | real gates | `make lint` / `make test` |
| `{{INSTALL_HINT}}`, `{{UPDATE_HINT}}`, `{{FORMAT_HINT}}`, `{{LINT_HINT}}`, `{{TEST_HINT}}`, `{{CLEAN_HINT}}` | what each make target does | `shards install` |

The `parity_plan.md` template also carries content placeholders
(`{{CURRENT_FEATURE}}`, `{{NEXT_FEATURE_*}}`, `{{AREA_*}}`, `{{STATUS}}`,
`{{GOTCHA}}`, `{{LAST_COMMIT}}`, `{{LINT_RESULT}}`, `{{TEST_RESULT}}`,
`{{PHASE_NAME}}`, `{{FEATURE_*}}`, `{{DIVERGENCE}}`, `{{RATIONALE}}`); fill them
from the real repo state and delete any section that does not apply.

### 3. Sync the entrypoint names

Different tools look for different filenames (`AGENTS.md`, `CLAUDE.md`), so
keep one real file and symlink the other:

```bash
ln -sf CLAUDE.md AGENTS.md
```

Either direction works; make the real file the one the team edits, and never
maintain two diverging copies.

### 4. Ensure core docs exist

Create concise starter docs only for missing files:

- `docs/resuming.md` (porting repos or any repo with multi-session work) —
  start from `templates.resuming.md`
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
- **`docs/resuming.md`** is the operator checklist linked from the **How to
  resume** block. It must not restate the plan; it points at it.

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

1. Commands listed in the entrypoint exist and run.
2. `AGENTS.md` resolves to `CLAUDE.md` (or the reverse).
3. Doc links resolve, including `docs/resuming.md` when the repo has one.
4. Repo policy text is not duplicated across multiple files.
5. `temp/` is ignored and the cleanup path is explicit.
6. The entrypoint has a **How to resume** block, a **Session continuity**
   section, a **Definition of done**, and the commit message convention, and
   every path/command in them is real for this repo.
7. No placeholder tokens (`{{...}}`) remain in `AGENTS.md`/`CLAUDE.md`.
