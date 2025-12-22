require "../src/virtualdate"

puts "VirtualDate::Scheduler benchmarks"
puts "Crystal #{Crystal::VERSION}"
puts

def measure(label : String, &block)
  start = Time.monotonic
  yield
  elapsed = Time.monotonic - start
  puts "%-45s %8.2f ms" % [label, elapsed.total_milliseconds]
end

scheduler = VirtualDate::Scheduler.new
loc = Time::Location.load("Europe/Berlin")

from = Time.local(2023, 5, 10, 0, 0, 0, location: loc)
to = Time.local(2023, 5, 11, 0, 0, 0, location: loc)

# --------------------------------------------------
# 1. Many simple tasks
# --------------------------------------------------

100.times do |i|
  t = VirtualDate.new("simple-#{i}")
  t.duration = 15.minutes
  t.due << VirtualTime.new(hour: 9)
  scheduler.tasks << t
end

measure("100 simple non-conflicting tasks") do
  scheduler.build(from, to)
end

# --------------------------------------------------
# 2. Heavy conflict / rescheduling
# --------------------------------------------------

scheduler = VirtualDate::Scheduler.new

50.times do |i|
  t = VirtualDate.new("conflict-#{i}")
  t.duration = 30.minutes
  t.shift = 5.minutes
  t.flags << "work"
  t.parallel = 1
  t.priority = i
  t.due << VirtualTime.new(hour: 9)
  scheduler.tasks << t
end

measure("50 conflicting tasks with shifts") do
  scheduler.build(from, to)
end

# --------------------------------------------------
# 3. Dependencies chain
# --------------------------------------------------

scheduler = VirtualDate::Scheduler.new
prev = nil

20.times do |i|
  t = VirtualDate.new("chain-#{i}")
  t.duration = 10.minutes
  t.due << VirtualTime.new(hour: 9)
  t.depends_on << prev if prev
  scheduler.tasks << t
  prev = t
end

measure("20-task dependency chain") do
  scheduler.build(from, to)
end

# --------------------------------------------------
# 4. Staggered parallel tasks
# --------------------------------------------------

scheduler = VirtualDate::Scheduler.new

t = VirtualDate.new("staggered")
t.parallel = 10
t.stagger = 5.minutes
t.duration = 10.minutes
t.due << VirtualTime.new(hour: 10)
scheduler.tasks << t

measure("Staggered parallel scheduling (10)") do
  scheduler.build(from, to)
end

puts
puts "Done."
