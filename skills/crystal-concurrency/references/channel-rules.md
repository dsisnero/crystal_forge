# Crystal Channel Rules

## Closed Channel Behavior

- `ch.send(v)` on closed → raises `Channel::ClosedError`
- `ch.receive` on closed → raises `Channel::ClosedError`
- `ch.receive?` on closed → returns `nil`
- Buffered channel drains remaining values before returning `nil`
- `ch.close` on already-closed → **silently succeeds** (Go panics)

## receive vs receive?

- `receive` — blocks until value; raises `ClosedError` on close
- `receive?` — blocks until value; returns `nil` on close

Use `receive?` when the channel might close. Use `receive` when you want
the exception to propagate.

**In select**: always use `receive?` for channels that may close:

```crystal
# BROKEN when channels may close concurrently — raises ClosedError
select
when val = ch.receive    # BAD
when done.receive        # BAD
end

# CORRECT — returns nil on close
select
when val = ch.receive?   # GOOD
when done.receive?       # GOOD
end
```

## Channel(Nil) Ambiguity

`Channel(Nil)` compiles and works, but `receive?` is ambiguous:

```crystal
ch = Channel(Nil).new
spawn { ch.send nil }
got_value = ch.receive?   # => nil (value)

ch.close
got_closed = ch.receive?  # => nil (closed)

got_value == got_closed   # => true — indistinguishable
```

**Rule**: use `Channel(Bool)` for all signal channels (done, quit, semaphore).

```crystal
done = Channel(Bool).new
spawn { done.send true }
done.receive?  # => true (value) or nil (closed) — unambiguous
```

## Nil Channels (Crystal vs Go)

Go allows nil channel variables. Operations on nil channels block forever.
Crystal's type system prevents this entirely:

```crystal
ch : Channel(Int32)? = nil
# ch.send(1)    — compile error
# ch.receive    — compile error

if ch  # narrows to Channel(Int32)
  ch.send(1)  # compiles
end
```

Go uses nil channels in `select` to dynamically disable cases. Crystal cannot
express this — use `if/else` branching around separate `select` blocks.

## select/else (Non-blocking)

Crystal's `select ... else ... end` = Go's `select { default: }`:

```crystal
select
when ch.send(val)
  # sent
else
  # channel full or no receiver ready
end
```

Works correctly for unbuffered channels. Has a scheduling quirk with buffered
channel sends (off-by-one possible) — test with specs.

## Concurrent Fan-Out Fix

When fan-out workers close output channels concurrently, a bare `select` can
observe a closed channel.
Bare `select when ch.receive` raises `ClosedError`.

**Before (breaks when output channels close concurrently):**

```crystal
8.times do
  select
  when val = out1.receive   # raises if closed
  when val = out2.receive
  end
end
```

**After (works under both modes):**

```crystal
merged = Channel(Int32).new(8)
wg = WaitGroup.new(4)
[out1, out2, out3, out4].each do |output|
  spawn do
    while val = output.receive?
      merged.send(val)
    end
    wg.done
  end
end
spawn do
  wg.wait
  merged.close
end
while val = merged.receive?
  results << val
end
```

**Rule**: when consuming from multiple channels that may close, use the
merge-with-WaitGroup pattern.
