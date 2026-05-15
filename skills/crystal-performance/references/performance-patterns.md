# Crystal Performance Patterns

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
