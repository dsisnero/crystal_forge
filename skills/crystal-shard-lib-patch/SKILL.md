---
name: crystal-shard-lib-patch
description: Use this skill in Crystal projects whenever code under ./lib (installed shards) is modified to preserve Go parity or fix shard behavior. Forks upstream repo to ./temp, implements TDD fix, pushes to fork, asks user to review before creating PR. Creates or updates upstream shard issues with reproducible failures, failing specs, environment details, and the local patch that fixes it.
---

# Crystal Shard Lib Patch

## Overview

Use this workflow when a Crystal port requires changing dependency code under `./lib/**`.
Goal: keep local progress unblocked while producing a high-quality upstream bug report and patch for shard maintainers.

This skill follows TDD: write failing tests first, then implement the fix, then push to a fork and ask user to review before creating PR.

## Trigger Conditions

Run this skill when all are true:

- Project is Crystal.
- You changed or plan to change files under `./lib/<shard_name>/`.
- The change restores expected behavior/parity, fixes a bug, or adds missing compatibility used by this repo.

Do not use this skill for changes only in `src/`, `spec/`, or app code that does not patch a shard.

## Workflow

### Step 1: Identify shard and canonical upstream

- Determine shard name from changed path: `lib/<shard_name>/...`.
- Resolve upstream in this order:
  - `lib/<shard_name>/shard.yml` (`github`, `git`, or source URL fields).
  - `lib/<shard_name>/.git/config` remote URL.
  - Local shard cache metadata (for example `~/.cache/shards/**/<shard>.git/config` / refs).
  - Shard docs/README as last fallback.
- If local shard remote points to the host repo or another non-canonical origin, ignore it and continue fallback lookup.
- Record shard commit/version used for reproduction.

### Step 2: Create temp directory and prepare for fork work

- Create temp directory: `mkdir -p ./temp`
- Ensure `.gitignore` includes `/temp/` to keep temporary work out of main repo
- Verify temp directory is empty or can be overwritten

### Step 3: Reproduce and isolate failure in the fork

- First fork and clone the upstream repository to `./temp/<shard_name>/`
- Run the smallest failing command in the fork to confirm the issue exists
- Capture exact command, error, and stack trace
- Create at least one non-interactive minimal repro (for example `crystal eval` or a tiny standalone snippet)
- Confirm failure occurs before patch and passes after patch

### Step 4: Fork and clone the upstream repository

**If you own the shard** (upstream owner matches current user/organization):

- Clone the repo directly into temp directory:

  ```text
  mkdir -p ./temp
  cd ./temp
  git clone https://github.com/<your-username>/<repo>.git <shard_name>
  ```

- Create feature branch:

  ```text
  cd ./temp/<shard_name>
  git checkout -b feat/<descriptive-branch-name>
  ```

**If you don't own the shard** (need to fork):

- Fork the upstream repo using `gh repo fork <owner>/<repo> --clone=false`.
- Clone fork into `./temp/<shard_name>`:

  ```text
  cd ./temp
  git clone https://github.com/<your-username>/<repo>.git <shard_name>
  ```

- Create feature branch:

  ```text
  cd ./temp/<shard_name>
  git checkout -b feat/<descriptive-branch-name>
  ```

**In both cases:**

- Install shards: `shards install`
- Run existing tests to ensure baseline passes: `crystal spec`

### Step 5: Write TDD tests FIRST (that will fail)

**This is critical - write tests BEFORE implementing the fix.**

- Create spec file: `spec/<feature_name>_spec.cr`
- Write tests that demonstrate:
  - The method/function should exist
  - The expected behavior
  - Error handling
  - Null safety where applicable
- **Practical TDD patterns:**
  - For missing methods: Test that method exists and has correct signature
  - For null safety: Test that methods return optional types (`Type?`) where appropriate
  - For bug fixes: Test the failing case before fix, should pass after fix
- Run tests to confirm they FAIL:

  ```text
  crystal spec spec/<feature_name>_spec.cr
  ```

- If tests fail to compile due to missing dependencies, create simpler compile-time tests:

  ```crystal
  # Example: Test method signature by checking source code
  it "has safe parent method" do
    source = File.read("src/shard_name/file.cr")
    source.should contain("def parent : Node?")
  end
  ```

- Verify tests fail with the expected error (e.g., "undefined method" or wrong return type)

### Step 6: Implement the fix (that makes tests pass)

- Modify only necessary files in the fork.
- Prefer behavior-compatible fixes over broad refactors.
- Keep public API changes minimal and documented if unavoidable.
- **Common fixes to implement for any shard:**
  - Change return types from `Type` to `Type?` for methods that can return null/nil
  - Add missing methods that exist in underlying API but aren't wrapped
  - Add convenience methods/iterators for better ergonomics
  - Fix bounds checking for array/collection access
  - Add proper error handling for edge cases
  - Fix memory safety issues (null checks, buffer overflows)
- Run tests to confirm they PASS:

  ```text
  crystal spec spec/<feature_name>_spec.cr
  ```

- Run ALL tests to verify no regressions:

  ```text
  crystal spec
  ```

- **Handle test failures in existing specs:**
  - If existing tests fail due to API changes (e.g., `Type` → `Type?`), update them
  - Use `.not_nil!` in tests where you know the value shouldn't be nil
  - Update type annotations in tests to match new API
  - Fix method calls to match new signatures
- Fix any trailing whitespace issues before committing:

  ```text
  find src spec -name "*.cr" -type f -exec sed -i '' 's/[[:space:]]*$//' {} \;
  ```

### Step 7: Test the fix in the host project

- Temporarily update the host project's `shard.yml` to use the local patched version:

  ```yaml
  dependencies:
    <shard_name>:
      path: ./temp/<shard_name>/
  ```

- **Remove the existing lib/<shard_name>/ directory AND the shard cache**, then install:

  ```text
  rm -rf lib/<shard_name> ~/.cache/shards/<shard_name>
  shards install
  ```

  *This is critical:* `shards install` alone may not pick up a branch or path change
  if the old version is cached. Removing both the lib directory and the cache
  forces a fresh fetch. Alternatively, use `shards update <shard_name>`.
- Run host project tests to verify the fix works:

  ```text
  crystal spec
  ```

- **Also test the specific issue that triggered the patch:**
  - Create a minimal test in the host project that reproduces the original issue
  - Verify the test now passes with the patched shard
  - Example: If fixing null safety, test that accessing parent of root doesn't segfault
- If tests pass, proceed to commit and push
- **Clean up test files** created during debugging before committing

#### Tree-sitter grammar dependencies

When patching shards that depend on tree-sitter grammars (e.g., `tree_sitter`, grammar bindings):

- The fork's `spec/` may fail because the temp clone doesn't have grammars in `vendor/grammars/`.
- In spec files, add the host project's grammar directory to `TreeSitter::Config.parser_directories`:

  ```crystal
  TreeSitter::Config.parser_directories << Path.new(
    File.expand_path("../../../vendor/grammars", __DIR__)
  )
  ```

- Adjust the relative path based on `__DIR__` location of the spec file relative to the host project root.
- Use the simplest grammar available (e.g., "go") rather than adding a dependency on less common grammars.

### Step 8: Commit and push to fork

- **Clean macOS resource forks first** (critical on macOS/exFAT volumes):

  ```text
  find . -name "._*" -not -path "./.git/*" -delete 2>/dev/null
  find .git -name "._*" -delete 2>/dev/null
  ```

  These `._*` sidecar files cause `non-monotonic index` errors and git assertion failures.
- Stage changes:

  ```text
  git add src/ spec/
  ```

- Commit with descriptive message following conventional commits:

  ```text
  git commit -m "feat: <description>

  <detailed body explaining what and why>

  Closes #<issue-number>"
  ```

- Push to fork:

  ```text
  git push origin <branch-name>
  ```

### Step 9: Show changes to user and ASK before creating PR

**DO NOT create PR without explicit user permission.**

Show the user a comprehensive summary:

1. **What was fixed:** Brief description of the issue
2. **Changes made:** Summary of code changes
3. **Test results:**
   - TDD tests written and passing
   - Existing tests still pass (no regressions)
   - Host project tests pass with patched shard
4. **Links:**
   - Fork branch URL
   - Diff view (upstream vs fork)
   - PR creation link
5. **Key improvements:**
   - Safety improvements (null checks, bounds checking)
   - Missing API methods added
   - Convenience features
   - Bug fixes

**General summary format (adapt to specific shard):**

```text
## Summary of changes to <shard_name>

### 1. Safety Improvements:
- Methods now return optional types (Type?) where appropriate
- Added proper bounds/error checking
- Fixed potential crash scenarios

### 2. API Completeness:
- Added missing methods from underlying API
- Improved type signatures for better compile-time checking

### 3. Convenience Features:
- Added higher-level methods for common patterns
- Improved iteration/collection access

### 4. Bug Fixes:
- Fixed specific issue that triggered the patch
- Prevented crashes in edge cases

### 5. Test Results:
- ✅ All new TDD tests pass
- ✅ Existing specs pass (updated for API changes)
- ✅ Host project tests pass with patched shard

### Links:
- Fork: https://github.com/<username>/<repo>/tree/<branch>
- Diff: https://github.com/<upstream-owner>/<repo>/compare/main...<username>:<branch>
- Create PR: https://github.com/<upstream-owner>/<repo>/compare/main...<username>:<branch>?expand=1
```

Ask: "Should I create the PR to upstream?"

Only proceed to Step 10 if user explicitly approves.

### Step 10: Create pull request (only after user approval)

- Create PR using `gh pr create`:

  ```text
  gh pr create \
    --repo <upstream-owner>/<repo> \
    --title "feat: <description>" \
    --body "<pr-body>" \
    --head <your-username>:<branch-name>
  ```

- Link to existing issue if applicable
- Save PR URL in local tracking docs (`lib_issues/<shard>.<number>.md`)

### Step 11: Post-file validation (required)

- Re-open the created PR/issue and validate:
  - commands are copy-paste runnable,
  - required paths/repos are explicitly provided,
  - expected vs actual is unambiguous,
  - maintainers have enough detail to reproduce without asking for missing paths.
- If gaps remain, immediately post a corrective comment with fixed repro steps.

### Step 12: Update host project to use forked version

- Update host project's `shard.yml` to use the GitHub fork URL:

  ```yaml
  dependencies:
    <shard_name>:
      github: <your-username>/<repo>
      branch: <branch-name>
  ```

- Run `shards install` to fetch from GitHub
- Verify host project tests still pass: `crystal spec`
- **Restore `.gitignore` to ignore all `lib/` dependencies:**
  - Remove any special rules added for the patched shard (e.g., `!/lib/<shard_name>/`)
  - Ensure `.gitignore` has `/lib/` to ignore all installed dependencies
  - This is important because:
    1. The forked shard will be installed to `lib/` by shards
    2. We don't want to commit installed dependencies to git
    3. Our changes are in the fork, not in local `lib/<shard_name>/`
- Remove the local `lib/<shard_name>/` directory if it exists:

  ```bash
  rm -rf lib/<shard_name>
  shards install  # Reinstall from forked version
  ```

- Run `make clean` to clean up `./temp/` directory
- Keep shard patch changes documented alongside host changes that depend on them
- If upstream PR is created, link PR URL in tracking issue file

## Quality Bar

Before considering shard patch work complete:

- TDD tests written FIRST and verified to fail before fix
- Fix implemented and all tests pass
- All existing tests still pass (no regressions)
- Repro is deterministic
- At least one failing-before / passing-after proof exists
- Changes pushed to fork
- User has reviewed and approved (or PR created with user permission)
- Issue/PR exists and is accessible in the shard repo
- Issue/PR reproduction instructions are portable and maintainer-runnable
- Local tracker is updated with upstream issue/PR URL

## Practical Examples

### Example 1: Adding null safety to bindings

**Issue:** Method returns concrete type but should return optional type (can be null/nil)
**TDD Test:** Check source code for correct return type signature
**Fix:** Change `def method : Type` to `def method : Type?` and add nil check
**Result:** Prevents crashes, matches behavior of other language bindings

### Example 2: Adding missing API wrappers

**Issue:** Underlying API (C, Rust, etc.) has function but Crystal binding doesn't wrap it
**TDD Test:** Test that method exists and has correct signature
**Fix:** Add method with proper type checking and error handling
**Result:** Completes API coverage, improves functionality

### Example 3: Adding convenience methods

**Issue:** API is low-level and needs higher-level convenience methods
**TDD Test:** Test that convenience method exists and works
**Fix:** Add method that wraps lower-level API with better ergonomics
**Result:** Improves developer experience, matches patterns from other languages

### Example 4: Fixing bounds checking

**Issue:** Method doesn't check bounds before accessing arrays/collections
**TDD Test:** Test that out-of-bounds access raises proper error
**Fix:** Add bounds checking with `IndexError` or similar
**Result:** Prevents crashes, improves safety

### Example 5: Managing .gitignore during shard patching

**Issue:** `.gitignore` has special rules for patched shard (`!/lib/<shard_name>/`)
**Solution:** After forking and updating shard.yml to use forked version:

1. Remove special `.gitignore` rules for the shard
2. Ensure `.gitignore` has `/lib/` to ignore all dependencies
3. Remove local `lib/<shard_name>/` directory
4. Run `shards install` to get forked version
**Result:** Clean git state, dependencies managed by shards, changes in fork

### Example 6: Wrapping C API array/struct returns with Crystal types

**Issue:** The underlying C API returns raw struct arrays (e.g., `TSQueryPredicateStep*`)
that need parsing into idiomatic Crystal types for downstream consumers.
**TDD Test:** Write tests that create a query with known predicates, call the
new method, and verify the parsed predicate objects match expectations.
**Fix:** Add a method that calls the C binding, iterates the raw array, resolves
string/capture IDs using existing binding functions, and returns an `Array`
of structured `Predicate` objects with typed `Arg` variants.
**Result:** Downstream code can evaluate custom query predicates without
touching raw C pointers or manual ID resolution loops.

## Troubleshooting Common Issues

### 1. Tests fail to compile due to missing dependencies

- Create simpler "source code checking" tests instead of runtime tests
- Skip tests that require specific grammars/languages
- Use `begin/rescue` to handle missing dependencies gracefully

### 2. Existing tests fail after API changes

- Update tests to handle optional return types (use `.not_nil!` where appropriate)
- Fix type annotations in tests
- Update method calls to match new signatures

### 3. Can't run `crystal spec` due to linking issues

- Try building the shard directly: `crystal build src/shard_name.cr`
- Check if pkg-config can find libraries: `pkg-config --libs library-name`
- The shard might build fine even if tests have linking issues

### 4. Host project doesn't compile with patched shard

- Verify shard.yml points to correct path
- Run `shards update` to refresh dependencies
- Check for API incompatibilities between shard versions
- Ensure all required files are committed in the fork
- **Check `.gitignore` rules:** If `lib/` has special rules for the patched shard, remove them and reinstall

### 5. Git operations fail (auth, network)

- Use `gh` CLI with proper authentication
- If `gh` fails, manually fork on GitHub and clone
- Create offline issue/PR drafts in `lib_issues/` directory

### 6. Pre-existing spec failures in the fork

- Some forks may have pre-existing test failures (e.g., linking issues with system libraries like `ts_language_version` mismatch with installed tree-sitter version)
- **These do NOT block the patch** as long as:
  - The shard compiles cleanly: `crystal build src/<shard_name>.cr`
  - The new TDD tests pass in isolation: `crystal spec spec/<feature>_spec.cr`
  - The host project's full test suite passes with the patched shard
- Document any known pre-existing failures in the patch summary for the reviewer

## Directory Structure

All fork work happens in `./temp/<shard_name>/`:

```text
./temp/<shard_name>/
├── src/
│   └── <shard_name>/
│       └── <modified_files>.cr
├── spec/
│   └── <feature_name>_spec.cr  # TDD tests
├── shard.yml
└── shard.lock
```

The `./temp/` directory is temporary and can be deleted after PR is merged. The host project temporarily references this path in `shard.yml` during testing.

## Quick Reference Checklist

### Before starting

- [ ] Shard identified and upstream located
- [ ] `./temp/` directory created and in `.gitignore`
- [ ] Fork created and cloned

### TDD Phase

- [ ] Failing tests written FIRST
- [ ] Tests verify the exact issue/feature
- [ ] Tests fail as expected before fix

### Implementation

- [ ] Fix implements the required behavior
- [ ] All new tests pass
- [ ] Existing tests still pass (updated if needed)
- [ ] No trailing whitespace in changed files

### Integration

- [ ] Host project `shard.yml` updated to use local path
- [ ] Host project tests pass with patched shard
- [ ] Original issue is resolved in host project

### Completion

- [ ] Changes committed with descriptive message
- [ ] Changes pushed to fork
- [ ] User shown summary and asked about PR
- [ ] PR created only after user approval
- [ ] `.gitignore` restored to ignore all `lib/` dependencies
- [ ] Local `lib/<shard_name>/` directory removed (if existed)
- [ ] Host project uses forked version from GitHub

## GH Escalation Notes

- If `gh repo fork`/`gh pr create` fails due sandbox/network restrictions, immediately rerun with command escalation enabled.
- Use the escalation request instead of asking in plain chat first, so the user can approve directly from the command prompt.
- If escalated GH still fails (auth/network), continue the workflow by writing an offline-ready draft in `lib_issues/*.md` with the exact failed command and error output.
