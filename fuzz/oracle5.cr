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

def sched_starts(vd : VirtualDate, from : Time, to : Time, granularity = 1.minute, maxc = 10000)
  VirtualDate::Scheduler.new([vd]).build(from, to, granularity: granularity, max_candidates: maxc).map(&.start)
end

# corrected: 1-minute sampling for day-range rule
v = VirtualDate.new("t")
v.due << VirtualTime.new(day: 1..27)
exp = brute_starts(v, Time.utc(2025, 5, 15), Time.utc(2025, 8, 15), 1.minute, 1.minute)
act = sched_starts(v, Time.utc(2025, 5, 15), Time.utc(2025, 8, 15))
puts(exp == act ? "OK   day 1..27 3mo corrected (#{act.size})" : "FAIL day 1..27: exp #{exp.size} #{exp.first(5)} vs act #{act.size} #{act.first(5)}")
FAILS << "day" if exp != act

# minute rules with sub-minute granularity
v2 = VirtualDate.new("t")
v2.due << VirtualTime.new(minute: [10, 11, 13])
exp2 = brute_starts(v2, Time.utc(2025, 6, 2), Time.utc(2025, 6, 2, 3), 10.seconds, 1.second)
act2 = sched_starts(v2, Time.utc(2025, 6, 2), Time.utc(2025, 6, 2, 3), 10.seconds)
puts(exp2 == act2 ? "OK   minute [10,11,13] g=10s (#{act2.size})" : "FAIL g=10s: exp #{exp2} vs act #{act2}")
FAILS << "g10s" if exp2 != act2

# empty / degenerate windows
v3 = VirtualDate.new("t")
v3.due << VirtualTime.new(hour: 10)
r = sched_starts(v3, Time.utc(2025, 6, 2, 10), Time.utc(2025, 6, 2, 10))
puts(r.empty? ? "OK   from==to empty" : "FAIL from==to: #{r}")
FAILS << "empty" if !r.empty?

v4 = VirtualDate.new("t")
r4 = VirtualDate::Scheduler.new([v4]).build(Time.utc(2025, 6, 2), Time.utc(2025, 6, 2)).map(&.start)
puts(r4.empty? ? "OK   empty-due degenerate window" : "FAIL: #{r4}")
FAILS << "empty2" if !r4.empty?

# max_shifts exact counting on conflict shifts
def fixed_at(id, h, dur)
  a = VirtualDate.new(id)
  a.due << VirtualTime.new(hour: h, minute: 0)
  a.duration = dur
  a.fixed = true
  a
end

# b needs exactly 1 shift (10:00 -> 11:00)
a = fixed_at("a", 10, 1.hour)
b = VirtualDate.new("b")
b.due << VirtualTime.new(hour: 10, minute: 0)
b.duration = 30.minutes
b.max_shifts = 1
sch = VirtualDate::Scheduler.new([a, b]).build(Time.utc(2025, 6, 2), Time.utc(2025, 6, 3))
got = sch.map { |s| {s.vdate.id, s.start} }
expd = [{"a", Time.utc(2025, 6, 2, 10)}, {"b", Time.utc(2025, 6, 2, 11)}]
puts(got == expd ? "OK   max_shifts=1 allows 1 shift" : "FAIL max_shifts=1: #{got}")
FAILS << "ms1" if got != expd

# b needs 2 moves (fixed until 11:00, omit 11:00-11:29) with max_shifts=1 -> rejected
a2 = fixed_at("a", 10, 1.hour)
b2 = VirtualDate.new("b")
b2.due << VirtualTime.new(hour: 10, minute: 0)
b2.duration = 30.minutes
b2.max_shifts = 1
b2.omit << VirtualTime.new(hour: 11, minute: 0..29)
b2.shift = 1.minute # keep span policy but conflict shifting counts
sch2 = VirtualDate::Scheduler.new([a2, b2]).build(Time.utc(2025, 6, 2), Time.utc(2025, 6, 3))
got2 = sch2.map { |s| {s.vdate.id, s.start} }
# NOTE: with shift=1.minute, shift_span=1min; omitted skip steps 1min at a time,
# each counted -> exceeds max_shifts=1 -> only a scheduled
puts(got2 == [{"a", Time.utc(2025, 6, 2, 10)}] ? "OK   max_shifts=1 rejects 2+ shifts" : "FAIL: #{got2}")
FAILS << "ms2" if got2 != [{"a", Time.utc(2025, 6, 2, 10)}]

# max_shift equality boundary: exactly 1 hour move allowed
a3 = fixed_at("a", 10, 1.hour)
b3 = VirtualDate.new("b")
b3.due << VirtualTime.new(hour: 10, minute: 0)
b3.duration = 30.minutes
b3.max_shift = 1.hour
sch3 = VirtualDate::Scheduler.new([a3, b3]).build(Time.utc(2025, 6, 2), Time.utc(2025, 6, 3))
got3 = sch3.map { |s| {s.vdate.id, s.start} }
expd3 = [{"a", Time.utc(2025, 6, 2, 10)}, {"b", Time.utc(2025, 6, 2, 11)}]
puts(got3 == expd3 ? "OK   max_shift equality allowed" : "FAIL max_shift eq: #{got3}")
FAILS << "mseq" if got3 != expd3

# negative stagger raises
v5 = VirtualDate.new("t")
v5.due << VirtualTime.new(hour: 10)
v5.parallel = 2
v5.stagger = -5.minutes
begin
  VirtualDate::Scheduler.new([v5]).build(Time.utc(2025, 6, 2), Time.utc(2025, 6, 3))
  puts "FAIL negative stagger accepted"
  FAILS << "stagneg"
rescue e : ArgumentError
  puts "OK   negative stagger raises"
end

# invalid durations / parallel raise
v6 = VirtualDate.new("t")
v6.duration = -1.minute
begin
  VirtualDate::Scheduler.new([v6]).build(Time.utc(2025, 6, 2), Time.utc(2025, 6, 3))
  puts "FAIL negative duration accepted"
  FAILS << "negdur"
rescue e : ArgumentError
  puts "OK   negative duration raises"
end

puts
puts FAILS.empty? ? "ALL OK" : "FAILURES: #{FAILS.join(",")}"
