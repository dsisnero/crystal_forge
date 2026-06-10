# Crystal Performance Patterns

## FFI Call Minimization (C binding libraries)

When wrapping a C library, **C function call overhead dominates** Crystal method
dispatch. LLVM inlines trivial Crystal method calls in release mode, but each
`LibFoo.function(...)` call crosses the FFI boundary. Reducing the FFI call
count is the single highest-leverage optimization.

### Pattern: Eliminate redundant FFI bounds checks

Public wrapper methods often validate their arguments with FFI calls (e.g.
checking `child_count` before fetching a child). When called from a tight
loop that already knows the bounds, this doubles the FFI call count.

**Fix:** Inline the raw `LibFoo.*` calls directly in the iterator body, cache
the count once before the loop, and skip the public method's defensive checks.

```crystal
# BEFORE — public method calls child_count on every iteration
def each_child(& : Node ->)
  count = child_count
  i = 0
  while i < count
    yield child(i)   # child(i) internally calls child_count FFI again
    i += 1
  end
end

# AFTER — raw LibFoo calls, count cached, no redundant checks
def each_child(& : Node ->)
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

Expected gain: **15–20%** on multi-child iterations.

### Pattern: Skip redundant null checks in cursor iterators

Cursor-based iterators commonly call `current_node` which validates non-null
via `ts_node_is_null`. After a successful `goto_next_sibling`, the cursor is
guaranteed to be at a valid node — the null check is pure overhead.

**Fix:** Call `ts_tree_cursor_current_node` directly in iterator internals.
Add a `protected def unsafe_cursor_ptr` accessor on the cursor class.

```crystal
# BEFORE — null check every step via current_node wrapper
def next
  loop do
    node = @cursor.current_node   # calls ts_node_is_null internally
    return stop if node.nil?
    # ...
  end
end

# AFTER — skip null check, cursor guaranteed valid after goto_*
def next
  cursor_ptr = @cursor.unsafe_cursor_ptr
  loop do
    raw = LibFoo.foo_tree_cursor_current_node(cursor_ptr)
    # ...
  end
end
```

Expected gain: **7–13%** on cursor-based iteration.

### Pattern: Inline goto_next_sibling in cursor iterators

Cursor iterators call `@cursor.goto_next_sibling` which is a one-line wrapper
around `LibFoo.foo_tree_cursor_goto_next_sibling(pointerof(@cursor))`. In the
hot loop, this method dispatch adds measurable overhead per step.

**Fix:** Call the lib function directly using the cached cursor pointer.

Expected gain: **7–11%** on cursor-based iteration (cumulative with above).

### When to stop: C-dominated paths

If >95% of benchmark time is inside C library calls (e.g. parsing, query
execution), Crystal-side optimizations produce **negligible** results.
Identify these by comparing per-iteration Crystal overhead against total time.
Cancel the experiment — write the finding and move on.

### StringPool for deduplicating C strings

C APIs frequently return `const char*` without a length. Calling `String.new(ptr)`
allocates a new String each time — wasteful when the same C string is returned
repeatedly (e.g. node type names, symbol names).

```crystal
# BEFORE — allocates new String every call (528B/op for ~10 symbols)
ptr = LibFoo.foo_iterator_current_symbol_name(@iter)
String.new(ptr)

# AFTER — deduplicates via StringPool (192B/op)
ptr = LibFoo.foo_iterator_current_symbol_name(@iter)
TreeSitter.string_pool.get(ptr, LibC.strlen(ptr))
```

Expected gain: **~7% speed, ~64% fewer allocations** for symbol name iteration.

### Block methods vs Iterator classes — allocation tradeoff

Crystal's `Iterator(T)` requires a **heap-allocated class** (typically 32–64B).
Block-based methods can be **zero-allocation** if they inline FFI calls directly.

| Approach | Allocation | Use case |
|---|---|---|
| `each_child { \|x\| ... }` | 0B | Hot paths, single-pass iteration |
| `children.each { \|x\| ... }` | 64B | Chainable, lazy, composable |
| `named_children(cursor).each` | 416B | Multi-pass with cursor reuse |

**Guideline:** Provide both the Iterator (for API completeness) and the block
method (for hot paths). Document the tradeoff in comments.

### Class with finalizer = unavoidable heap alloc

Any Crystal class with a `finalize` method (to free C resources) must be
heap-allocated. There is no way to make these stack-allocated.

Examples: `TreeCursor`, `QueryCursor`, `LookaheadIterator`, `Parser`, `Tree`.

**Mitigations:**
- Add **reuse patterns** (pass existing cursor as a parameter): `named_children(cursor)`
- Provide **block-based alternatives** that avoid class allocation: `each_child`, `each_named_child`
- Accept the allocation when the class is created once and reused many times

### Beware of Crystal benchmark noise

Crystal's `Benchmark.ips` results vary ±10–20% between runs due to GC timing,
CPU frequency scaling, and OS scheduling. Strategies:

1. **Run at least 3 times** and average the results
2. **Discard the first run** (cold caches, JIT warmup)
3. **Only trust differences >10%** as real changes — smaller shifts are noise
4. **Check unaffected benchmarks** in the same run to verify it's not a systemic
   slowdown from background load

---

## Minimize Memory Allocations

Heap allocations are expensive and increase GC pressure. Prefer stack allocations when possible.

### Key Strategies

- **Use structs instead of classes** for small, immutable types
- **Avoid intermediate strings** when writing to IO
- **Use string interpolation** instead of concatenation
- **Avoid creating temporary objects** in loops
- **Use tuples instead of arrays** for small, fixed collections

---

## IO Operations

Always append directly to IO instead of creating intermediate strings:

**Bad:**

```crystal
puts 123.to_s  # Creates intermediate string
```

**Good:**

```crystal
puts 123  # Directly writes to IO
```

### Custom types should implement `to_s(io : IO)` not `to_s`

```crystal
class MyClass
  # Good
  def to_s(io)
    io << x << ", " << y
  end

  # Bad
  def to_s(io)
    io << "#{x}, #{y}"  # Creates intermediate string
  end
end
```

---

## String Building

Use `String.build` instead of `IO::Memory` for better performance:

```crystal
# Good
String.build do |io|
  99.times { io << "hello world" }
end

# Slower
io = IO::Memory.new
99.times { io << "hello world" }
io.to_s
```

---

## Efficient String Iteration

Crystal strings are UTF-8 encoded with variable-length characters. Indexing is O(n) for non-ASCII strings.

**Bad:**

```crystal
string = "foo"
while i < string.size
  char = string[i]  # O(n) operation!
  # ...
end
```

**Good:**

```crystal
string = "foo"
string.each_char do |char|  # O(1) per character
  # ...
end
```

---

## Avoiding Temporary Objects in Loops

Move constants outside loops or use tuples:

**Bad:**

```crystal
while line = gets
  if ["crystal", "ruby", "java"].any? { |string| line.includes?(string) }
    # Creates new array on every iteration!
  end
end
```

**Good (using tuple):**

```crystal
while line = gets
  if {"crystal", "ruby", "java"}.any? { |string| line.includes?(string) }
    # Tuple uses stack memory
  end
end
```

**Good (using constant):**

```crystal
LANGS = ["crystal", "ruby", "java"]

while line = gets
  if LANGS.any? { |string| line.includes?(string) }
    # Single array allocation
  end
end
```

---

## Struct vs Class

Use structs for small, value-like types:

```crystal
struct Point  # Stack allocated
  getter x, y

  def initialize(@x : Int32, @y : Int32)
  end
end

class Point  # Heap allocated
  getter x, y

  def initialize(@x : Int32, @y : Int32)
  end
end
```

Benchmark shows structs are ~15x faster for allocation.

---

## Iterator Patterns

Use iterators for lazy evaluation to avoid intermediate arrays and reduce memory usage.

**Eager (creates intermediate arrays):**

```crystal
(1..10_000_000).select(&.even?).map { |x| x * 3 }.first(3)
```

**Lazy (no intermediate arrays):**

```crystal
(1..10_000_000).each.select(&.even?).map { |x| x * 3 }.first(3).to_a
```

### Creating Iterators

Implement `#next` method returning element or `Iterator.stop`:

```crystal
class Zeros
  include Iterator(Int32)

  def initialize(@size : Int32)
    @produced = 0
  end

  def next
    if @produced < @size
      @produced += 1
      0
    else
      stop  # Iterator.stop
    end
  end
end
```

### Common Iterator Methods

- `#select(&block)` — Filter elements
- `#map(&block)` — Transform elements
- `#first(n)` — Take first n elements
- `#skip(n)` — Skip first n elements
- `#take_while(&block)` — Take while condition holds
- `#chain(other)` — Combine iterators
- `#cycle` — Repeat iterator indefinitely
- `#with_index` — Add indices
- `#zip(*others)` — Combine multiple iterators

### Iterator Consumption

Iterators are consumed when used:

```crystal
iter = (0...100).each
iter.size  # => 100 (consumes iterator)
iter.size  # => 0 (already consumed)
```

To reuse, create fresh iterator or convert to array first.

---

## Performance Checklist

When reviewing Crystal code, check for:

### FFI / C Binding Issues

- [ ] Are redundant FFI bounds checks eliminated from hot loops?
- [ ] Are null checks skipped when cursor position guarantees validity?
- [ ] Is `to_unsafe` cached once before the loop?
- [ ] Is `StringPool.get` used instead of `String.new` for C strings?
- [ ] Is the hot path dominated by C library time? If so, stop and record.
- [ ] Are block methods provided alongside Iterator classes for zero-allocation paths?

### Memory Allocation Issues

- [ ] Are structs used instead of classes where appropriate?
- [ ] Are intermediate strings avoided in IO operations?
- [ ] Is string interpolation used instead of concatenation?
- [ ] Are temporary objects created inside loops?
- [ ] Are tuples used for small fixed collections?

### Iterator Usage

- [ ] Are iterators used for lazy evaluation with large datasets?
- [ ] Is `each_char` used instead of indexing for string iteration?
- [ ] Are iterator methods chained properly without intermediate arrays?
- [ ] Is the iterator consumed only once?

### General Performance

- [ ] Is code compiled with `--release` flag for profiling?
- [ ] Are appropriate data structures used (Array vs Deque vs Set)?
- [ ] Are expensive operations memoized or cached?
- [ ] Are algorithms with appropriate time complexity used?

---

## Common Performance Pitfalls

1. **String indexing in loops** — Use `each_char`, `each_byte`, or `Char::Reader`
2. **Array literals in loops** — Use tuples or constants
3. **Intermediate IO allocations** — Use `String.build` or direct IO appending
4. **Unnecessary class allocations** — Use structs for small types
5. **Eager evaluation of large collections** — Use iterators for lazy evaluation
6. **Redundant FFI bounds checks** — Inline raw lib calls in hot loops, cache counts
7. **Repeated C string allocation** — Use `StringPool.get` to deduplicate
8. **Per-step method dispatch in cursor loops** — Inline `goto_next_sibling` and `current_node` calls
9. **Optimizing C-dominated paths** — If >95% time is in C, Crystal changes are wasted effort
10. **Single-run benchmarks** — Always run 3+ times, discard cold run, average the rest
