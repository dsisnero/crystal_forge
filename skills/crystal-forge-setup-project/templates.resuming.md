# Resuming Work

This is the first thing to read in a new session. It takes a few minutes to get
back to a known-good state.

## 1. Read where we are

- `{{PARITY_PLAN}}` — start at the **Where we are** block. It names the current
  focus, the ordered "Next up" list, per-area chunk status, and any scoping
  notes or gotchas, plus the last commit and current gate results. Do not
  re-derive state from git history.
- `{{INVENTORY_DIR}}/{{SOURCE_LANGUAGE}}_port_inventory.tsv` — the per-symbol
  ledger (status + `crystal_refs`). Use it to see what is left inside the
  current chunk:

  ```bash
  tail -n +2 {{INVENTORY_DIR}}/{{SOURCE_LANGUAGE}}_port_inventory.tsv \
    | cut -f3 | sort | uniq -c
  ```

## 2. Confirm the working tree

```bash
git log --oneline -10
git status
```

The last commit should be the previous feature (`port: ...`), committed
atomically. If the tree is dirty, finish or stash before starting.

## 3. Confirm a clean baseline

```bash
{{LINT_COMMAND}}
{{TEST_COMMAND}}
```

Both must pass before changing anything.

## 4. Pick the next feature

Take the first unchecked item in the **Next up** list (or the next `[ ]` item in
the current phase). For each feature:

1. Read the upstream source under `{{VENDOR_PATH}}` and the nearest upstream
   tests.
2. Port the tests first (red → green); never weaken assertions.
3. Satisfy the **Definition of done** in `AGENTS.md` (API, tests, gates,
   inventory rows, `{{PARITY_PLAN}}` status + **Where we are** refresh,
   divergences).
4. Commit atomically with the `port: ...` message format from `AGENTS.md`.

## If the plan is split

When `{{PARITY_PLAN}}` grows too large it is split into
`{{PARITY_PLAN_DIR}}/<area>.md` files. In that case every split file is linked
from `{{PARITY_PLAN}}`, and `{{PARITY_PLAN}}` marks each file
complete/in-progress and names the file being worked on plus the next
file/phase to start.

## Environment notes (optional)

Keep this section only when the checkout has a real environment quirk. Example:
on an exFAT or network volume, macOS writes AppleDouble `._*` sidecars; a
`._foo_spec.cr` sidecar can break test discovery, so the `Makefile` should strip
them before `format`/`lint`/`test`. If a git pack operation prints
`non-monotonic index .../._pack-*.idx`, delete the sidecars with
`find .git -name '._*' -delete`.
