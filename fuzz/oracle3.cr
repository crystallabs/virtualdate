require "../src/virtualdate"

# Second-resolution oracle for second-level rules and non-aligned windows.

def brute_starts_sec(vd : VirtualDate, from : Time, to : Time, granularity : Time::Span) : Array(Time)
  starts = [] of Time
  prev_match : Time? = nil
  t = from
  step = 1.second
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

def sched_starts(vd : VirtualDate, from : Time, to : Time, granularity : Time::Span, maxc = 100000) : Array(Time)
  s = VirtualDate::Scheduler.new([vd])
  s.build(from, to, granularity: granularity, max_candidates: maxc).map(&.start)
end

FAILS = [] of String

def check(name : String, vd : VirtualDate, from : Time, to : Time, granularity : Time::Span)
  exp = brute_starts_sec(vd, from, to, granularity)
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

def rule(**kw) : VirtualTime
  VirtualTime.new(**kw)
end

f = Time.utc(2025, 6, 2, 10, 0, 0)

# second-level rules, granularity in seconds
check "second 0..29 g=10s", vd { |v| v.due << rule(second: 0..29) }, f, f + 20.minutes, 10.seconds
check "second [0,30] g=10s", vd { |v| v.due << rule(second: [0, 30]) }, f, f + 20.minutes, 10.seconds
check "second [0,30] g=30s", vd { |v| v.due << rule(second: [0, 30]) }, f, f + 20.minutes, 30.seconds
check "second (0..59).step(15) g=5s", vd { |v| v.due << rule(second: (0..59).step(15)) }, f, f + 15.minutes, 5.seconds
check "minute [5] second 10..20 g=1m", vd { |v| v.due << rule(minute: [5, 6], second: 10..20) }, f, f + 3.hours, 1.minute
check "second 30..59 g=1m", vd { |v| v.due << rule(second: 30..59) }, f, f + 30.minutes, 1.minute
check "second 0..59 minute [7] g=30s", vd { |v| v.due << rule(minute: [7], second: 0..59) }, f, f + 3.hours, 30.seconds
check "sec full-range-excl 0...60 min [7]", vd { |v| v.due << rule(minute: [7], second: 0...60) }, f, f + 3.hours, 1.minute
check "second [59,0] wrap g=2s", vd { |v| v.due << rule(second: [59, 0]) }, f, f + 10.minutes, 2.seconds
check "g=90s minute [0,2]", vd { |v| v.due << rule(minute: [0, 2, 10]) }, f, f + 3.hours, 90.seconds

# non-aligned window starts (from mid-minute / odd seconds)
f2 = Time.utc(2025, 6, 2, 10, 0, 37)
check "hour 10..11 from :37s", vd { |v| v.due << rule(hour: 10..11) }, f2, f2 + 5.hours, 1.minute
check "minute [15] from :37s", vd { |v| v.due << rule(minute: [15]) }, f2, f2 + 2.hours, 1.minute
f3 = Time.utc(2025, 6, 2, 10, 15, 30) # inside the minute-15 stretch
check "minute [15,16] from inside", vd { |v| v.due << rule(minute: [15, 16]) }, f3, f3 + 2.hours, 1.minute

# millisecond / nanosecond constrained rules (tiny windows, oracle at 100ms)
def brute_starts_ms(vd : VirtualDate, from : Time, to : Time, granularity : Time::Span, step : Time::Span) : Array(Time)
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

vmilli = vd { |v| v.due << rule(millisecond: 0..499) }
exp = brute_starts_ms(vmilli, f, f + 30.seconds, 1.second, 100.milliseconds)
act = sched_starts(vmilli, f, f + 30.seconds, 1.second)
puts(exp == act ? "OK   millisecond 0..499 g=1s (#{exp.size})" : "FAIL millisecond 0..499 g=1s\n  exp #{exp.first(6)}\n  act #{act.first(6)}")
FAILS << "ms" if exp != act

puts
puts FAILS.empty? ? "ALL OK" : "FAILURES: #{FAILS.join(", ")}"
