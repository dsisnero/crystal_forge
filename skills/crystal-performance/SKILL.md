---
name: crystal-performance
description: Optimize Crystal code with measurement, not guesswork. Use when users report slow code, high allocations, hot-path regressions, or when a Crystal benchmark or profile needs action.
---

# Crystal Performance

Use this skill for measured optimization work only.

Read the bundled references only as needed:

- `references/profiling-tools.md`
- `references/performance-patterns.md`
- `references/alys.md`

## Rules

1. Identify the hot path before changing code.
2. Fix a broken benchmark harness before optimizing runtime code.
3. Capture a clear baseline and compare against it.
4. Treat each optimization as a separate experiment.
5. Keep failed or flat results; they are part of the deliverable.
6. Revert or discard changes without a measured win.
7. Re-run correctness gates after every kept change.

## Workflow

### 1. Find the measurement entrypoint

Prefer the repo's own benchmark, profile, or performance plan. If the documented
command is stale, repair the harness first.

### 2. Capture a baseline

Use release mode for timing unless you specifically need a debug-friendly call
tree. Write down the exact command and the number you will compare against.

**Run at least 3 times.** Crystal benchmark noise is high — single-run results
can appear ±20% from the mean. Discard the first (cold) run and average the
rest.

### 3. Name the hot path

Target one concrete cost such as allocation churn, duplicate scans, string
building, closure creation, or expensive decoding.

### 4. Apply the smallest plausible change

Prefer less allocation, less copying, simpler data movement, and less repeated
work. Avoid broad refactors while the signal is still unclear.

### 5. Re-measure and decide

Keep a change only if it measurably improves the targeted benchmark or
allocation profile. Otherwise revert it and record the result.

### 6. Re-run correctness gates

Run focused specs first, then broader gates if the repo has them.

## FFI Hot Paths (C binding libraries)

When optimizing Crystal code that wraps a C library, the dominant cost is
almost always **C function call overhead**, not Crystal method dispatch or
object allocation. LLVM inlines trivial Crystal methods in release mode.

### Pattern: Redundant FFI bounds checks

Public methods often do bounds-checking FFI calls (e.g. `child_count`) that
are redundant when called from a tight loop that already knows the bounds.

**Fix:** Inline the raw `LibFoo.function(...)` call directly in the iterator
body, bypassing the public method's defensive FFI calls. Cache the bounds
count once before the loop.

```crystal
# BEFORE — 3 FFI calls per child (count + child + isnull)
def each_child(&)
  count = child_count
  i = 0
  while i < count
    yield child(i)   # child(i) calls child_count again!
    i += 1
  end
end

# AFTER — 2 FFI calls per child, count cached once
def each_child(&)
  unsafe = to_unsafe
  count = LibFoo.foo_node_child_count(unsafe)
  i = 0u32
  while i < count
    node = LibFoo.foo_node_child(unsafe, i)
    yield Node.new_unsafe(node) unless LibFoo.foo_node_is_null(node)
    i += 1
  end
end
```

### Pattern: Redundant null checks after cursor move

Cursor-based iterators call `current_node` which does a `ts_node_is_null`
FFI call. After a successful `goto_next_sibling` / `goto_first_child`, the
cursor is guaranteed to be at a valid node.

**Fix:** Call `ts_tree_cursor_current_node` directly and skip the null check
in iterator internals. Add a `protected def unsafe_cursor_ptr` on the cursor
class for access.

### When to stop: C-dominated paths

If a benchmark spends >95% of its time inside C library calls (e.g. query
execution, parsing), optimizing the Crystal wrapper produces negligible
gains. Identify these early by comparing total time against the per-iteration
overhead. Cancel the experiment and record the finding.

### Block methods vs Iterator classes

Crystal `Iterator`-based iterators require a **heap-allocated class** instance
(typically 32–64B). Block-based methods (`each_foo { |x| ... }`) can be
**zero-allocation** if they inline the FFI calls directly.

Provide both: the Iterator for chainable/lazy use, and the block method for
hot paths. Document the tradeoff in comments.

### StringPool for C strings

C APIs often return `const char*` without a length. Use `StringPool.get(ptr,
LibC.strlen(ptr))` instead of `String.new(ptr)` to deduplicate strings across
repeated calls. This avoids allocating new String objects for the same C string
returned repeatedly by the library.

### Class with finalizer = unavoidable heap alloc

`TreeCursor`, `QueryCursor`, `LookaheadIterator` — any Crystal class with a
`finalize` method to free C resources must be heap-allocated. There is no way
to make these stack-allocated. If the allocation dominates a benchmark, the
fix is to add a **reuse pattern** (pass an existing cursor as a parameter) or
a **block-based alternative** that avoids the class entirely.

## Deliverable

Report:

- the exact measurement command
- the named hot path
- the baseline used
- each experiment and what changed
- before/after numbers for kept changes
- flat or regressed numbers for discarded changes
- the correctness gates that ran

## Notes

- Use `alys` only when allocation tracing is the actual question.
- If `alys` is not already present in `shard.yml`, ask before adding it.
