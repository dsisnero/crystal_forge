# Cancellation Patterns

Stopping fibers cleanly. The unifying rule: **closing a channel is a broadcast** —
every fiber blocked on `done.receive?` wakes at once. Use `Channel(Bool)` for
signals and `receive?` (not `receive`) inside `select`, because a closed channel
makes `receive` raise `ClosedError` while `receive?` returns `nil`.

Crystal fibers are not garbage collected — a fiber with no way to exit leaks. Always
give long-lived fibers a `done` channel.

Verified against `dsisnero/crystal-concurrency-patterns`.

Patterns: Done Channel · Quit Signal · Or-Channel · Or-Done · Errgroup ·
Graceful Shutdown · Select Timeout · Context

---

## Done Channel (broadcast cancellation)

One `done` channel cancels an unknown number of workers at once. Send a value to
cancel *one* waiter; **close** to cancel *all* of them.

```crystal
done = Channel(Bool).new

# In each worker — race the real work against cancellation:
spawn do
  loop do
    select
    when done.receive?
      break                       # cancelled
    when ch.send(val)             # or made progress
    end
  end
end

done.close                        # cancel everyone, no fiber leaks
```

`done.close` is preferred over sending N values: you rarely know N, and close wakes
them all simultaneously.

Source: `opcito_patterns_spec.cr` ("3. Preventing Goroutine Leaks"), doc
`pipelines-and-cancellation.adoc`. Example: `examples/pipeline_cancel.cr`.

---

## Quit Signal (request + acknowledge)

Two-way shutdown: the caller asks a fiber to stop and waits for confirmation, so
cleanup is guaranteed to finish before the program moves on.

```crystal
def boring(msg : String, quit : Channel(String)) : Channel(String)
  c = Channel(String).new
  spawn do
    i = 0
    loop do
      select
      when c.send("#{msg} #{i}")
        i += 1
      when quit.receive
        # ... clean up ...
        quit.send("See you!")     # acknowledge
        break
      end
    end
  end
  c
end

quit = Channel(String).new
c = boring("Joe", quit)
5.times { puts c.receive }
quit.send("Bye")                  # request stop
puts quit.receive                 # wait for "See you!"
```

Source: `src/concurrency_patterns/quit_signal.cr`, spec `quit_signal_spec.cr`.

---

## Or-Channel (merge cancellation signals)

Combine several `done`-style channels into one that fires when **any** of them
closes. `merged.close rescue nil` tolerates the race where two inputs close at once
(double-close is a silent no-op in Crystal, but guarding keeps intent explicit).

```crystal
def or_channel(channels : Array(Channel(Bool))) : Channel(Bool)
  merged = Channel(Bool).new
  channels.each do |ch|
    spawn do
      ch.receive?                 # wakes on a value OR on close
      merged.close rescue nil
    end
  end
  merged
end
```

Source: `opcito_patterns_spec.cr` ("4. Or-Channel").

---

## Or-Done (wrap a channel with done)

Wrap a value channel so that reading from it also respects cancellation — the
composable building block other cancellable stages are built from. The `rescue`
covers the input channel closing underneath the `select`.

```crystal
def or_done(done : Channel(Bool), input : Channel(Int32)) : Channel(Int32)
  out = Channel(Int32).new
  spawn do
    loop do
      select
      when done.receive?
        break
      when val = input.receive
        out.send(val)
      end
    rescue Channel::ClosedError
      break
    end
    out.close
  end
  out
end
```

Source: `new_patterns_spec.cr` ("Or-Done"), doc `timing-futures-rate-limiting.adoc`.

---

## Errgroup (cancel on first error)

Run N tasks; the first one to fail closes `done` to cancel the rest, and the first
exception is returned. A buffered error channel sized to the task count means no
worker blocks on `send`.

```crystal
require "wait_group"

def errgroup(done : Channel(Bool), tasks : Array(Proc(Channel(Bool), Nil))) : Exception?
  errc = Channel(Exception?).new(tasks.size)
  wg = WaitGroup.new(tasks.size)
  tasks.each do |task|
    spawn do
      begin
        task.call(done)
        errc.send(nil)
      rescue ex
        errc.send(ex)
        done.close rescue nil     # cancel siblings
      ensure
        wg.done
      end
    end
  end
  spawn { wg.wait; errc.close }

  first_err : Exception? = nil
  while err = errc.receive?
    first_err ||= err
  end
  first_err
end
```

Source: `additional_patterns_spec.cr` ("Errgroup"), doc
`broadcasting-and-cancellation.adoc`. Example: `examples/errgroup.cr`.

---

## Graceful Shutdown

The ordered teardown for a worker pool: stop new work, let in-flight work drain,
then wait. Closing `jobs` makes each worker's `jobs.receive?` return `nil`, so the
loop ends naturally.

```crystal
done.close          # 1. broadcast stop to anything watching `done`
jobs.close          # 2. stop accepting new work (receive? now returns nil)
wg.wait             # 3. block until every worker has drained and called wg.done
```

Source: `final_patterns_spec.cr` ("Graceful Shutdown"), doc
`production-patterns.adoc`.

---

## Select Timeout

Bound a blocking receive with a deadline. Crystal's `select` has a built-in
`timeout(span)` action — the idiomatic Go-`time.After` equivalent for a single
select.

```crystal
c = some_channel
select
when msg = c.receive
  puts msg
when timeout(5.seconds)
  puts "no response, you talk too slow"
end
```

When you need the deadline as a *reusable channel* (e.g. one shared deadline across
several receives — see Scatter-Gather), build it once with a helper instead:

```crystal
def after(span : Time::Span) : Channel(Bool)
  ch = Channel(Bool).new
  spawn { sleep span; ch.send(true) }
  ch
end
```

Source: `src/concurrency_patterns/select_timeout.cr` (example only — no spec).
Example: `examples/06_select_timeout.cr` (upstream).

---

## Context (channel-based cancellation + timeout)

Crystal has no `context.Context`; a `done` channel plus a `cancel` proc covers
`context.WithCancel`, and adding a `timeout` arm covers `context.WithTimeout`. A
worker selects on its own step timer against `done`.

```crystal
def with_cancel : {Channel(Bool), Proc(Nil)}
  done = Channel(Bool).new
  cancel = -> { done.close rescue nil; nil }
  {done, cancel}
end

done, cancel = with_cancel
spawn do
  loop do
    select
    when done.receive?
      break                       # cancelled by caller or deadline
    when timeout(100.milliseconds)
      do_step
    end
  end
end

# cancel.call            # WithCancel
# spawn { sleep 1.second; cancel.call }   # WithTimeout
```

Source: `src/concurrency_patterns/context.cr`, `opcito_patterns_spec.cr`
("13. Context"). Example: `examples/16_context.cr` (upstream).
