require "wait_group"
require "digest/md5"

record DigestEntry, path : String, digest : String

def walk_and_send(root : String, jobs : Channel(String))
  Dir.glob(File.join(root, "**", "*")) do |path|
    next unless File.file?(path)
    jobs.send(path)
  end
  jobs.close
end

def digest_worker(jobs : Channel(String), results : Channel(DigestEntry), wg : WaitGroup)
  while path = jobs.receive?
    data = File.read(path)
    sum = Digest::MD5.hexdigest(data)
    results.send(DigestEntry.new(path, sum))
  end
  wg.done
end

def run_digest(root : String, num_workers : Int32, &spawner : (-> Nil) -> Nil) : {Array(DigestEntry), Time::Span}
  jobs = Channel(String).new(64)
  results = Channel(DigestEntry).new(256)
  wg = WaitGroup.new(num_workers)

  start = Time.instant

  spawn { walk_and_send(root, jobs) }

  num_workers.times do
    spawner.call(-> {
      digest_worker(jobs, results, wg)
    })
  end

  spawn do
    wg.wait
    results.close
  end

  entries = [] of DigestEntry
  while entry = results.receive?
    entries << entry
  end

  elapsed = Time.instant - start
  {entries, elapsed}
end

root = ARGV[0]? || "."
num_workers = (ARGV[1]? || "8").to_i

puts "Directory: #{root}"
puts "Workers:   #{num_workers}"
puts ""

puts "=== Default spawn (concurrent, single-threaded) ==="
entries_default, time_default = run_digest(root, num_workers) do |work|
  spawn { work.call }
end
puts "  Files:   #{entries_default.size}"
puts "  Time:    #{time_default}"
puts ""

{% if flag?(:execution_context) %}
  puts "=== ExecutionContext::Parallel (truly parallel) ==="
  ctx = Fiber::ExecutionContext::Parallel.new("digesters", num_workers)
  entries_parallel, time_parallel = run_digest(root, num_workers) do |work|
    ctx.spawn { work.call }
  end
  puts "  Files:   #{entries_parallel.size}"
  puts "  Time:    #{time_parallel}"
  puts ""

  speedup = time_default.total_milliseconds / time_parallel.total_milliseconds
  puts "=== Speedup: #{speedup.round(2)}x ==="
  puts ""

  entries_parallel.sort_by!(&.path)
  entries_parallel.each do |entry|
    puts "#{entry.digest}  #{entry.path}"
  end
{% else %}
  puts "(compile with -Dpreview_mt -Dexecution_context to benchmark parallel mode)"
  puts ""

  entries_default.sort_by!(&.path)
  entries_default.each do |entry|
    puts "#{entry.digest}  #{entry.path}"
  end
{% end %}
