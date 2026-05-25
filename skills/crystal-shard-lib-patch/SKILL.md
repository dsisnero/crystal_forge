---
name: crystal-shard-lib-patch
description: Use this skill whenever fixing behavior in installed Crystal shard code under `./lib/`. It preserves local progress, requires failing tests first, and pushes the fix toward an upstream issue or PR instead of leaving an untracked local patch.
---

# Crystal Shard Lib Patch

Use this workflow when the required fix lives under `lib/<shard_name>/...`.
The goal is to unblock the host project while producing an upstreamable patch.

## Trigger

Use this skill when all are true:

1. The project is Crystal.
2. The fix requires editing installed shard code under `./lib/`.
3. The change restores expected behavior, parity, or compatibility.

Do not use it for app-only changes in `src/` or `spec/`.

## Standard flow

### 1. Identify the shard and upstream

- Derive the shard name from `lib/<shard_name>/...`.
- Resolve the canonical upstream from `lib/<shard_name>/shard.yml`, local git
  metadata, or shard documentation.
- Record the exact shard version or commit used for reproduction.

### 2. Prepare temporary fork workspace

- Work in `./temp/<shard_name>/`.
- Ensure `temp/` is ignored by the host repo.
- Treat the temp clone as disposable fork work, not as the host repo source of
  truth.

### 3. Reproduce the failure before fixing

- Create a minimal deterministic repro.
- Confirm the failure in the fork workspace before editing.
- Capture the exact command, error, and scope of the bug.

### 4. Fork or clone upstream

- If you already control upstream, clone it directly.
- Otherwise fork with `gh repo fork` and clone the fork into `./temp`.
- Create a feature branch.
- Install dependencies and run the smallest useful baseline test command.

### 5. Write the failing test first

Add or update the smallest spec that proves the bug. Confirm it fails before
implementing the fix. If runtime testing is blocked by missing native
dependencies, fall back to the smallest compile-time or source-shape proof that
still captures the intended contract.

### 6. Implement the minimal fix

- Touch only the files needed for the behavior change.
- Prefer compatibility fixes over broad refactors.
- Run the focused new spec, then the shard's broader test/build command.

### 7. Verify in the host project

- Point the host project's `shard.yml` at the local patched path.
- Refresh the installed dependency if required.
- Run the host project's focused failing case and then its broader gate.
- Confirm the original project-level problem is actually fixed.

### 8. Push the fork and stop for review

- Commit the shard fix in the fork.
- Push the branch.
- Show the user what changed, the tests that prove it, and the branch or diff
  URL.
- Ask before creating an upstream PR.

### 9. Create upstream issue or PR only with approval

- If the user approves, create the PR with clear repro steps and test evidence.
- If sandbox or network blocks `gh`, rerun with escalation.
- If GitHub actions still fail, write an offline-ready issue or PR draft in the
  host repo so the work remains actionable.

### 10. Switch the host repo to the forked dependency

After the fork exists:

- update `shard.yml` to the fork URL or branch
- reinstall dependencies
- make sure `lib/` stays ignored
- keep the upstream issue or PR URL in host-project notes

## Quality bar

Do not call shard patching complete unless all are true:

1. A failing-before proof exists.
2. The fix passes in the shard repo.
3. The triggering host-project case also passes.
4. The fork branch is pushed.
5. The user has reviewed the summary before PR creation.
6. The upstream issue or PR path is documented, or an offline draft exists.

## Special cases

- Tree-sitter shards may need parser directories pointed back at the host
  project's grammar checkout during spec runs.
- Pre-existing upstream spec failures do not block the patch if the shard still
  builds, the new focused proof passes, and the host project is fixed. Document
  that clearly in the patch summary.
