require "wait_group"

# Worker pool: producer sends jobs to a channel, N workers process them.
# Shows both default spawn and ExecutionContext::Parallel with timing.
#
# Build:
#   crystal run examples/worker_pool.cr

def cpu_work(val : Int32, iterations : Int32) : Int64
  result = 0_i64
  iterations.times do |i|
    result &+= (val.to_i64 &* i) &+ (i &* i)
  end
  result
end

record Job, id : Int32, val : Int32
record Result, job_id : Int32, output : Int64

def run_pool(num_workers : Int32, jobs_data : Array(Int32), &spawner : (-> Nil) -> Nil) : {Array(Result), Time::Span}
  jobs = Channel(Job).new(32)
  results = Channel(Result).new(jobs_data.size)
  wg = WaitGroup.new(num_workers)

  start = Time.instant

  # Workers: pull from jobs, compute, send result
  num_workers.times do
    spawner.call(-> {
      while job = jobs.receive?
        output = cpu_work(job.val, 500_000)
        results.send(Result.new(job.id, output))
      end
      wg.done
    })
  end

  # Producer: send jobs
  spawn do
    jobs_data.each_with_index do |val, idx|
      jobs.send(Job.new(idx, val))
    end
    jobs.close
  end

  # Closer: wait for all workers, then close results
  spawn do
    wg.wait
    results.close
  end

  # Collector
  collected = [] of Result
  while result = results.receive?
    collected << result
  end

  elapsed = Time.instant - start
  {collected, elapsed}
end

num_workers = 4
data = (1..20).to_a

puts "Jobs:    #{data.size}"
puts "Workers: #{num_workers}"
puts ""

puts "=== Default spawn ==="
results_default, time_default = run_pool(num_workers, data) do |work|
  spawn { work.call }
end
puts "  Results: #{results_default.size}"
puts "  Time:    #{time_default}"

puts ""
puts "=== ExecutionContext::Parallel ==="
ctx = Fiber::ExecutionContext::Parallel.new("pool", maximum: num_workers)
results_parallel, time_parallel = run_pool(num_workers, data) do |work|
  ctx.spawn { work.call }
end
puts "  Results: #{results_parallel.size}"
puts "  Time:    #{time_parallel}"
puts ""
speedup = time_default.total_milliseconds / time_parallel.total_milliseconds
puts "=== Speedup: #{speedup.round(2)}x ==="
