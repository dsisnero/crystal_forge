# {{PROJECT_NAME}}

> **How to resume:** read `{{PARITY_PLAN}}` first and use its **Where we are**
> block (current focus + ordered "Next up"), then run `{{LINT_COMMAND}}` and
> `{{TEST_COMMAND}}`. Details: [docs/resuming.md](docs/resuming.md). Do not
> re-derive state from git.

Crystal port of {{UPSTREAM_PROJECT}} ({{UPSTREAM_LANGUAGE}}) from
[{{UPSTREAM_REPO}}]({{UPSTREAM_URL}}), vendored at `{{VENDOR_PATH}}` (release
`{{UPSTREAM_RELEASE}}`, commit `{{UPSTREAM_COMMIT}}`).

## Commands

```bash
make install   # {{INSTALL_HINT}}
make update    # {{UPDATE_HINT}}
make format    # {{FORMAT_HINT}}
make lint      # {{LINT_HINT}}
make test      # {{TEST_HINT}}
make clean     # {{CLEAN_HINT}}
```

If the repository has no `Makefile`, list the real commands instead of inventing
targets, and keep the placeholder names above out of the file.

## Docs

- [Resuming work](docs/resuming.md)
- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [Coding Guidelines](docs/coding-guidelines.md)
- [Testing](docs/testing.md)
- [PR Workflow](docs/pr-workflow.md)

## Principles

1. Upstream behavior is the source of truth; `{{VENDOR_PATH}}` wins over local
   preference.
2. Port behavior, not style.
3. Port upstream tests early and never weaken assertions.
4. Track parity in `{{PARITY_PLAN}}` and `{{INVENTORY_DIR}}/`.
5. Commit one completed feature at a time.

## Session continuity (read this first)

`{{PARITY_PLAN}}` is the single source of truth for where we are. At the start
of every session:

1. Read `{{PARITY_PLAN}}` and use its **Where we are** block to find the current
   focus, the ordered "Next up" list, and per-area chunk status. Do not
   re-derive state from git history.
2. Skim `git log --oneline -10` and `git status` to confirm the working tree.
3. Run `{{LINT_COMMAND}}` and `{{TEST_COMMAND}}` before changes to confirm a
   clean baseline.

See [docs/resuming.md](docs/resuming.md) for the full resume checklist.

### Keeping `{{PARITY_PLAN}}` resumable

- `{{PARITY_PLAN}}` starts with a **Where we are** block (`Current focus`,
  `Next up`, chunk status by area). Keep it accurate after every feature.
- Work items are feature-sized (roughly one branch/commit). Per-symbol state
  lives in `{{INVENTORY_DIR}}/{{SOURCE_LANGUAGE}}_port_inventory.tsv`, not in
  the plan.
- If `{{PARITY_PLAN}}` grows too large, split it into `{{PARITY_PLAN_DIR}}/<area>.md`
  files, link each from `{{PARITY_PLAN}}`, and mark each split file
  complete/in-progress plus the file being worked on next.

### Definition of done for every feature (required)

A feature is complete only when all of the following are true, and all of it
must be committed as **one** atomic commit before starting the next feature:

1. the API surface is implemented;
2. upstream tests (or equivalent characterization specs) exist and pass;
3. gates pass: `{{LINT_COMMAND}}` and `{{TEST_COMMAND}}`;
4. parity inventory rows for the feature are updated
   (`{{INVENTORY_DIR}}/{{SOURCE_LANGUAGE}}_port_inventory.tsv`);
5. `{{PARITY_PLAN}}` status is updated and the **Where we are** block refreshed
   (current focus + next up);
6. any intentional divergence is documented (in `{{PARITY_PLAN}}` and/or the
   commit message).

### Commit message

Start with `port:` and a one-line feature name, then bullets for what changed,
then the upstream revision (`{{UPSTREAM_REPO}} {{UPSTREAM_RELEASE}}
({{UPSTREAM_COMMIT}})`). Include new/changed files, divergences, and the gate
results so a new session can resume from the commit alone.
