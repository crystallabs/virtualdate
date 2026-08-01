require "../src/virtualdate"

FAILS = [] of String

def brute_starts(vd : VirtualDate, from : Time, to : Time, granularity : Time::Span, step : Time::Span) : Array(Time)
  starts = [] of Time
  prev_match : Time? = nil
  t = from
  while t < to
    if vd.due_on?(t) == true
      pm = prev_match
      starts << t if pm.nil? || (t - pm) > granularity
      prev_match = t
    end
    t += step
  end
  starts
end

def sched_starts(vd : VirtualDate, from : Time, to : Time, granularity : Time::Span, maxc = 10000) : Array(Time)
  VirtualDate::Scheduler.new([vd]).build(from, to, granularity: granularity, max_candidates: maxc).map(&.start)
end

def check(name : String, vd : VirtualDate, from : Time, to : Time, granularity = 1.minute, step = 1.minute)
  exp = brute_starts(vd, from, to, granularity, step)
  act = begin
    sched_starts(vd, from, to, granularity)
  rescue e
    puts "ERR  #{name}: #{e.class}: #{e.message}"
    FAILS << name
    return
  end
  if exp == act
    puts "OK   #{name} (#{exp.size} occ)"
  else
    FAILS << name
    puts "FAIL #{name}"
    puts "  expected #{exp.size}: #{exp.first(8)}"
    puts "  actual   #{act.size}: #{act.first(8)}"
    puts "  missing: #{(exp - act).first(8)}"
    puts "  extra:   #{(act - exp).first(8)}"
  end
end

def vd(&) : VirtualDate
  v = VirtualDate.new("t")
  yield v
  v
end

f = Time.utc(2025, 6, 2, 0, 0, 0)

# MAX_RUN_STEPS give-up + carry: 30s-on/30s-off over 12h merges into one run
check "second 0..29 12h g=1m", vd { |v| v.due << VirtualTime.new(second: 0..29) },
  f, f + 12.hours, 1.minute, 1.second

# give-up path inside bounded hours, 2 days
check "hour 9..17 second 0..29 2d g=1m", vd { |v| v.due << VirtualTime.new(hour: 9..17, second: 0..29) },
  f, f + 2.days, 1.minute, 1.second

# day range across months. Oracle sampled at 1 minute: a day-boundary rule
# sampled at 15-minute steps misses the exact run edges and reports a false
# mismatch (the corrected case also lives in oracle5).
check "day 1..27 3mo", vd { |v| v.due << VirtualTime.new(day: 1..27) },
  Time.utc(2025, 5, 15), Time.utc(2025, 8, 15), 1.minute, 1.minute

# window ends exactly at occurrence start
check "to == occurrence start", vd { |v| v.due << VirtualTime.new(hour: 10) },
  f, Time.utc(2025, 6, 2, 10, 0, 0)

# location-carrying rule, UTC window
zg = Time::Location.load("Europe/Zagreb")
check "rule hour 10 @Zagreb, UTC window", vd { |v| v.due << VirtualTime.new(hour: 10, location: zg) },
  f, f + 2.days

# proc field
check "minute proc %7", vd { |v| v.due << VirtualTime.new(minute: ->(m : Int32) { m % 7 == 0 }) },
  f, f + 3.hours

# default_match = false
dm = VirtualTime.new(hour: 10)
dm.default_match = false
check "default_match=false hour 10", vd { |v| v.due << dm }, f, f + 2.days

# begin/end bounds
v1 = vd { |v| v.due << VirtualTime.new(minute: 0); v.begin = Time.utc(2025, 6, 2, 10, 30) }
act1 = sched_starts(v1, f, f + 1.day, 1.minute)
exp1 = (11..23).map { |h| Time.utc(2025, 6, 2, h, 0, 0) }
puts(act1 == exp1 ? "OK   begin bound drops early occurrences (#{act1.size})" : "FAIL begin bound: #{act1.first(5)}")
FAILS << "begin" if act1 != exp1

# begin falling INSIDE a long occurrence: occurrence base is before begin -> dropped whole
v2 = vd { |v| v.due << VirtualTime.new(hour: 8..12); v.begin = Time.utc(2025, 6, 2, 10, 30) }
act2 = sched_starts(v2, f, f + 1.day, 1.minute)
puts "NOTE begin-inside-run: scheduled=#{act2} (occurrence base 08:00 dropped entirely; vdate.on?(11:00)=#{v2.on?(Time.utc(2025, 6, 2, 11, 0))})"

# end bound
v3 = vd { |v| v.due << VirtualTime.new(minute: 0); v.end = Time.utc(2025, 6, 2, 3, 0) }
act3 = sched_starts(v3, f, f + 1.day, 1.minute)
exp3 = (0..3).map { |h| Time.utc(2025, 6, 2, h, 0, 0) }
puts(act3 == exp3 ? "OK   end bound (#{act3.size})" : "FAIL end bound: #{act3}")
FAILS << "end" if act3 != exp3

# negative shift moving occurrence before window start
v4 = vd do |v|
  v.due << VirtualTime.new(hour: 0, minute: 30)
  v.omit << VirtualTime.new(hour: 0, minute: 30)
  v.shift = -1.hour
end
act4 = sched_starts(v4, f, f + 1.day, 1.minute)
puts(act4.empty? ? "OK   negative shift out of window dropped" : "FAIL negative shift: #{act4}")
FAILS << "negshift" if !act4.empty?

# shift=true keeps omitted occurrence
v5 = vd do |v|
  v.due << VirtualTime.new(hour: 10)
  v.omit << VirtualTime.new(hour: 10)
  v.shift = true
end
act5 = sched_starts(v5, f, f + 1.day, 1.minute)
puts(act5 == [Time.utc(2025, 6, 2, 10, 0)] ? "OK   shift=true keeps omitted" : "FAIL shift=true: #{act5}")
FAILS << "shifttrue" if act5 != [Time.utc(2025, 6, 2, 10, 0)]

# shift=false drops omitted occurrence
v6 = vd do |v|
  v.due << VirtualTime.new(hour: 10)
  v.omit << VirtualTime.new(hour: 10)
  v.shift = false
end
act6 = sched_starts(v6, f, f + 1.day, 1.minute)
puts(act6.empty? ? "OK   shift=false drops omitted" : "FAIL shift=false: #{act6}")
FAILS << "shiftfalse" if !act6.empty?

# on = Time::Span override
v7 = vd { |v| v.due << VirtualTime.new(hour: 10); v.on = 1.hour }
act7 = sched_starts(v7, f, f + 1.day, 1.minute)
puts(act7 == [Time.utc(2025, 6, 2, 11, 0)] ? "OK   on=span override" : "FAIL on=span: #{act7}")
FAILS << "onspan" if act7 != [Time.utc(2025, 6, 2, 11, 0)]

# on = false override
v8 = vd { |v| v.due << VirtualTime.new(hour: 10); v.on = false }
act8 = sched_starts(v8, f, f + 1.day, 1.minute)
puts(act8.empty? ? "OK   on=false override" : "FAIL on=false: #{act8}")
FAILS << "onfalse" if !act8.empty?

# empty due -> single candidate at window start
v9 = VirtualDate.new("e")
act9 = sched_starts(v9, f, f + 1.day, 1.minute)
puts(act9 == [f] ? "OK   empty due -> [from]" : "FAIL empty due: #{act9}")
FAILS << "emptydue" if act9 != [f]

puts
puts FAILS.empty? ? "ALL OK" : "FAILURES: #{FAILS.join(",")}"
