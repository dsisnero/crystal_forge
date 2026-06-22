# Coordination Patterns

Controlling *how many* fibers run and *in what order* they hand off work.

Verified against `dsisnero/crystal-concurrency-patterns`. "spec" = characterized by
an assertion; "example only" = runnable program, no assertion.

Patterns: Worker Pool · Bounded Parallelism · Queuing (Semaphore) · Daisy Chain ·
Restore Sequence · Ping-Pong

---

## Worker Pool

A fixed number of workers pull jobs from one channel and push to a results channel.
Close `jobs` to tell workers to stop; a `WaitGroup` fiber closes `results` once all
workers have drained, so the consumer's `receive?` loop terminates cleanly.

```crystal
require "wait_group"

def worker(id : Int32, jobs : Channel(Int32), results : Channel(Int32))
  while job = jobs.receive?
    results.send(job * 2)
  end
end

num_workers = 3
num_jobs = 8
jobs = Channel(Int32).new(num_jobs)
results = Channel(Int32).new(num_jobs)

wg = WaitGroup.new(num_workers)
num_workers.times do |id|
  spawn { worker(id, jobs, results); wg.done }
end

1.upto(num_jobs) { |j| jobs.send(j) }
jobs.close                      # signal "no more work"
spawn { wg.wait; results.close }

while r = results.receive?
  puts r
end
```

This is the template for any bounded producer→workers→results flow.

Source: `src/concurrency_patterns/worker_pool.cr`, spec `worker_pool_spec.cr`,
`opcito_patterns_spec.cr` ("9. Worker Pool").
Example: `examples/worker_pool.cr` (includes a `spawn` vs `ctx.spawn` benchmark).

---

## Bounded Parallelism

A worker-pool specialization for walking a tree and processing files, with a `done`
channel for cancellation propagated into every blocking `send`. Keeps the number of
in-flight fibers fixed regardless of how many files exist.

```crystal
require "wait_group"
require "digest/md5"

record DigestResult, path : String, sum : String, err : Exception?

def walk_files(done : Channel(Bool), root : String) : {Channel(String), Channel(Exception?)}
  paths = Channel(String).new
  errc = Channel(Exception?).new(1)
  spawn do
    err = nil
    begin
      Dir.glob(File.join(root, "**", "*")) do |path|
        next unless File.file?(path)
        select
        when paths.send(path)
        when done.receive?
          err = Exception.new("walk canceled")
          break
        end
      end
    rescue ex
      err = ex
    end
    paths.close
    errc.send(err)
  end
  {paths, errc}
end

def digester(done : Channel(Bool), paths : Channel(String), c : Channel(DigestResult))
  while path = paths.receive?
    sum = Digest::MD5.hexdigest(File.read(path))
    select
    when c.send(DigestResult.new(path, sum, nil))
    when done.receive?
      return
    end
  end
end

def md5_all(root : String) : Hash(String, String)
  done = Channel(Bool).new
  paths, errc = walk_files(done, root)
  c = Channel(DigestResult).new
  wg = WaitGroup.new(20)                 # exactly 20 digesters, no matter the file count
  20.times { spawn { digester(done, paths, c); wg.done } }
  spawn { wg.wait; c.close }

  m = {} of String => String
  while r = c.receive?
    raise r.err.not_nil! if r.err
    m[r.path] = r.sum
  end
  walk_err = errc.receive
  raise walk_err.not_nil! if walk_err
  m
end
```

For CPU-bound hashing, swap `spawn` for `ctx.spawn` on a
`Fiber::ExecutionContext::Parallel` — measured **8.76x** on 1014 files (8 threads).
See `references/execution-contexts.md`.

Source: `src/concurrency_patterns/bounded_parallelism.cr`, doc
`pipelines-and-cancellation.adoc` (example only — no characterization spec).
Example: `examples/parallel_digest.cr`.

---

## Queuing (Semaphore)

A buffered `Channel(Bool)` is a counting semaphore: its capacity is the max number
of concurrent slots. `send` to acquire (blocks when full), `receive` to release.
Use `Channel(Bool)`, never `Channel(Nil)` — a `Nil` payload is indistinguishable
from "closed" on `receive?`.

```crystal
limit = 3
sem = Channel(Bool).new(limit)

10.times do |i|
  sem.send(true)       # acquire — blocks once 3 are in flight
  spawn do
    do_work(i)
    sem.receive        # release
  end
end
```

Source: `opcito_patterns_spec.cr` ("12. Queuing — Buffered Channel as Semaphore").

---

## Daisy Chain

N fibers wired in a line, each adding 1 and passing the value along. A stress test
of cheap fiber creation — 1000 fibers relay a token and the result is 1001.

```crystal
def f(left : Channel(Int32), right : Channel(Int32))
  left.send(1 + right.receive)
end

n = 1000
leftmost = Channel(Int32).new
left = right = leftmost
n.times do
  right = Channel(Int32).new
  spawn f(left, right)
  left = right
end
spawn { right.send(1) }
leftmost.receive    # => 1001
```

Source: `src/concurrency_patterns/daisy_chain.cr`, spec `daisy_chain_spec.cr`.
Example: `examples/08_daisy_chain.cr` (upstream).

---

## Restore Sequence

Fan-in normally interleaves producers unpredictably. To restore strict ordering,
each message carries its own `wait` channel; a producer blocks on `wait.receive`
after sending, and the consumer releases producers in the order it wants.

```crystal
record Message, str : String, wait : Channel(Bool)

def boring(msg : String) : Channel(Message)
  c = Channel(Message).new
  wait_for_it = Channel(Bool).new      # shared by every message from this producer
  spawn do
    i = 0
    loop do
      c.send(Message.new("#{msg} #{i}", wait_for_it))
      i += 1
      wait_for_it.receive              # block until the consumer says "go"
    end
  end
  c
end

# Consumer alternates two producers in lockstep:
c1, c2 = boring("Joe"), boring("Ann")
5.times do
  msg1 = c1.receive; puts msg1.str
  msg2 = c2.receive; puts msg2.str
  msg1.wait.send(true)                 # release each producer for its next turn
  msg2.wait.send(true)
end
```

Source: `src/concurrency_patterns/restore_sequence.cr`, spec
`restore_sequence_spec.cr`. Example: `examples/05_restore_sequence.cr` (upstream).

---

## Ping-Pong

Two fibers volley a single mutable object back and forth over one channel. Safe
because the object is only ever touched by whichever fiber currently holds it —
ownership transfers with the channel send (a confinement variant).

```crystal
class Ball
  property hits : Int32 = 0
end

def player(name : String, table : Channel(Ball))
  loop do
    ball = table.receive
    ball.hits += 1
    puts "#{name} #{ball.hits}"
    sleep 100.milliseconds
    table.send(ball)
  end
end

table = Channel(Ball).new
spawn player("ping", table)
spawn player("pong", table)
table.send(Ball.new)        # serve
sleep 1.second
```

Source: `src/concurrency_patterns/pingpong.cr` (example only — no spec).
Example: `examples/13_pingpong.cr` (upstream).
