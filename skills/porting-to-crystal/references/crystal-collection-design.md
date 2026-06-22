# Crystal Collection Design for Concurrent Data Structures

Lessons from porting Go's `sync.Map` (HashTrieMap) and `xsync.Map` (CLHT)
to Crystal. Collected June 2026. Crystal 1.20.2.

## Core Insight: Unified Node Type

Do NOT port Go/Rust tagged-pointer patterns directly. Use a **single node type**
with a discriminator field instead of separate `Entry`/`Indirect` class
hierarchies with tagged `Pointer(Void)`.

### Wrong (3 attempts, all failed)
```
Tagged pointers (low bit 0=indirect, 1=entry):
  Pointer(Void).as(Entry(K,V))  +  Pointer(Void).as(Indirect)
  → 2 type casts × 30 methods × 2 generic instantiations = 120 compiler passes
  → 86 seconds to compile 1 spec, timed out

Class hierarchy (is_a? dispatch):
  Node(K,V) → Entry(K,V) | Indirect(K,V)
  ptr.as(Node(K,V)).is_a?(Entry(K,V))
  → vtable overhead + 3 types to instantiate
  → compiler bug/crash with recursive is_a?

Type-erased internals (store K,V as Void*):
  HtmEntry with Void* keys, reify only at API boundary
  → key comparison broken (Void* == Void* compares addresses, not values)
  → reify at API boundary requires .as(K) which re-triggers instantiation
```

### Right: Unified Node (from `lucaong/immutable`)
```crystal
class Node(K, V)
  property levels : Int32   # 0 = leaf, >0 = internal
  property entries : Array({K, V})          # leaf entries
  @children : Pointer(Atomic(Pointer(Void)))  # child slots (lazy alloc)
end
```

- ONE type: `Node(K,V)` for both roles
- Leaf detection: `@levels == 0`
- Tree descent in 3 lines with ONE `.as(Node(K,V))` call:

```crystal
private def walk_to_leaf(node : Node(K, V), h : UInt64) : Node(K, V)
  cur = node
  while cur.levels > 0
    shift = (cur.levels * BITS).to_u32
    idx = ((h >> (shift - BITS)) & MASK).to_i
    child = cur.load_child(idx)
    break if child.address == 0
    cur = child.as(Node(K, V))    # <-- only ONE .as() call in entire method
  end
  cur
end
```

Result: **3.4 seconds for 11 specs** (27x faster than tagged-pointer approach).

## Minimize Initial API Surface

Start with the core concurrent surface first instead of porting Crystal
Hash parity immediately:

```
Essential first:        Defer until core behavior is stable:
  load, store            select, reject, merge, transform, compact, invert,
  delete, clear          dig, fetch variants, key_for, has_value?, shift,
  swap                   first_key, last_key, each_key, each_value, dup, clone,
  load_or_store          put_if_absent, update, values_at, to_a, to_h,
  load_and_delete        select!, reject!, transform_keys!, transform_values!,
  compare_and_swap       merge!, compact!, Enumerable inclusion, ...
  compare_and_delete
  each, size
```

A wider API increases maintenance cost and can increase compile time once those
methods are exercised by specs, examples, macros, or callers. Crystal does
*not* eagerly instantiate every generic method on a type just because the type
exists; unused methods can remain untyped until referenced. Keep the first port
small anyway so compile-time and correctness problems stay localized.

## Pointer(Void).as(GenericClass): Supported but Expensive

The Crystal compiler **explicitly supports** `Pointer(Void).as(ReferenceType)`:

```crystal
# codegen/types.cr:56-59 — Void is treated as having inner pointers
# so GC.malloc (not malloc_atomic) is used for Pointer(Void).malloc
```

Used in stdlib: `WeakRef` (`@target.as(T?)`), `Hash` (`@indices.as(UInt16*)`),
`Arena` (`GC.malloc(...).as(Pointer(Entry(T)))`).

BUT: repeated `.as(GenericClass(K,V))` sites inside generic helpers can
materially increase semantic/codegen work in practice. In this port, dozens of
cast-heavy call sites correlated with unusable compile times.

**Rule of thumb:** Keep `.as()` calls to 1-2 per generic method. Each public
method + each private helper contributes.

## Recursive Block Yield: Use Explicit Stacks

Crystal inlines blocks, so recursive methods that yield to caller blocks
cause infinite inlining:

```crystal
# WRONG — compiler error: "recursive block expansion"
def walk(node, &)
  walk(node.child) { |k, v| yield(k, v) }  # recursive yield
end

# RIGHT — explicit stack
def walk(root, &)
  stack = [root]
  while node = stack.pop?
    yield node.key, node.value
    stack.push(node.child) if node.child
  end
end
```

## Reference: lucaong/immutable

The Crystal library `lucaong/immutable` (200+ stars, 2019-2024) implements
a hash trie with exactly this unified-node design:

- `Immutable::Map(K, V)` — persistent hash trie
- `Trie(K, V)` — single node type for internal + leaf
- 5 bits/level = 32-way branching
- `@children : Array(Trie(K, V))` — fully typed (no pointers)
- `@bitmap : UInt64` — sparse child indexing
- Leaf entries via `Values(K, V)` struct
- Persistence via structural sharing (dup on write)

Our concurrent adaptation uses `StaticArray(Atomic(Pointer(Void)), 32)`
for child slots (inline, no heap allocation) plus per-node `Sync::Mutex`.

## Atomic with StaticArray: Value Copy Trap

Crystal's `StaticArray#[]` returns a VALUE copy for struct types. This means:

```crystal
# WRONG — writes to stack copy, heap unchanged:
sa[idx].set(ptr, :release)

# RIGHT — uses indexed assignment (Pointer#[]=), writes to heap:
sa[idx] = Atomic(T).new(ptr)

# RIGHT — raw pointer assignment, also writes to heap:
(sa.to_unsafe + idx).value = Atomic(T).new(ptr)
```

Reads work through copies because `Atomic#get` reads `self.@value` —
the copy was initialized from the correct heap location, so the value
is correct and the acquire barrier is applied.

**Rule:** Use `sa[idx] = val` assignment for atomic writes through
StaticArray. Use `sa[idx].get(ordering)` for atomic reads.

## Compilation Time as a Design Constraint

In Crystal, generic type instantiation time is a real factor when choosing
data structures. A design that compiles in 3 seconds vs 86 seconds is the
difference between usable and abandoned.

Factors that increase compilation time:
- Number of `.as(GenericClass(K,V))` calls per generic type
- Number of public methods on the generic type
- Class hierarchy depth (virtual dispatch tables)
- Loop body complexity (32-iteration loops × methods = many IR nodes)

Factors that don't:
- `Atomic(Pointer(Void))` operations themselves (simple atomic intrinsics)
- Pointer arithmetic (cheap at the IR level)
- Number of instances at runtime (runtime concern, not compile-time)

## Porting Checklist

When porting a concurrent data structure to Crystal:

- [ ] Study existing Crystal-native implementations first (lucaong/immutable)
- [ ] Use unified node type, not tagged pointers
- [ ] Keep API to <15 methods
- [ ] Count `.as(GenericType)` calls — target <15 total across all methods
- [ ] Use explicit stacks for tree iteration, not recursive yields
- [ ] Test compilation time early — if >10s for 10 specs, redesign
- [ ] Verify with `-Dpreview_mt -Dexecution_context`
