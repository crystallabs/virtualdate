require "../src/virtualdate"

# Targeted scheduling-semantics tests with hand-computed expectations.

FAILS = [] of String

def t(h, m = 0)
  Time.utc(2025, 6, 2, h, m, 0)
end

WFROM = Time.utc(2025, 6, 2, 0, 0, 0)
WTO   = Time.utc(2025, 6, 3, 0, 0, 0)

def once(hour, minute = 0)
  VirtualTime.new(hour: hour, minute: minute)
end

def mk(id, hour, minute = 0, *, dur = 30.minutes, flags = [] of String, parallel = 1, priority = 0, fixed = false)
  v = VirtualDate.new(id)
  v.due << once(hour, minute)
  v.duration = dur
  flags.each { |fl| v.flags << fl }
  v.parallel = parallel
  v.priority = priority
  v.fixed = fixed
  v
end

def run(vdates, from = WFROM, to = WTO, maxc = 1000)
  VirtualDate::Scheduler.new(vdates).build(from, to, max_candidates: maxc)
end

def expect(name, sched, expected : Array({String, Time}))
  got = sched.map { |s| {s.vdate.id, s.start} }
  if got == expected
    puts "OK   #{name}"
  else
    FAILS << name
    puts "FAIL #{name}"
    puts "  expected: #{expected}"
    puts "  got:      #{got}"
    sched.each { |s| puts "  --- #{s.vdate.id}@#{s.start}:\n#{s.explanation.lines.map { |l| "      " + l }.join("\n")}" }
  end
end

# A. parallel=2, three identical meetings -> 2 at 10:00, third shifted past both
a1 = mk("a", 10, flags: ["m"], parallel: 2)
b1 = mk("b", 10, flags: ["m"], parallel: 2)
c1 = mk("c", 10, flags: ["m"], parallel: 2)
expect "parallel=2 three vdates", run([a1, b1, c1]),
  [{"a", t(10)}, {"b", t(10)}, {"c", t(10, 30)}]

# B. parallel=1 chain
a2 = mk("a", 10)
b2 = mk("b", 10)
c2 = mk("c", 10)
expect "parallel=1 three vdates", run([a2, b2, c2]),
  [{"a", t(10)}, {"b", t(10, 30)}, {"c", t(11)}]

# C. parallel=3 -> all together
a3 = mk("a", 10, flags: ["m"], parallel: 3)
b3 = mk("b", 10, flags: ["m"], parallel: 3)
c3 = mk("c", 10, flags: ["m"], parallel: 3)
expect "parallel=3 three vdates", run([a3, b3, c3]),
  [{"a", t(10)}, {"b", t(10)}, {"c", t(10)}]

# D. middle-vdate limit: A 10:00-11:00, B 10:40-11:40, C would overlap both
a4 = mk("a", 10, 0, dur: 1.hour, flags: ["m"], parallel: 2)
b4 = mk("b", 10, 40, dur: 1.hour, flags: ["m"], parallel: 2)
c4 = mk("c", 10, 50, dur: 30.minutes, flags: ["m"], parallel: 2)
# order: a, b, c (same prio, id order). a@10:00. b@10:40 (2 overlap OK).
# c@10:50 overlaps a+b -> c count 3 >2. shift. any start in [10:50,11:00) overlaps both.
# at 11:00 c overlaps only b, but then b has a(10:40-11:00 overlap) + c -> 3 > 2 -> not OK.
# c must go to 11:40. (a-b overlap ends 11:00 but b remains; b+c 2 <= 2 only when a-b overlap
# no longer counts -- a,b overlap regardless of c; b's count = a + c + b = 3 whenever c overlaps b.
# So c must not overlap b at all -> 11:40.)
expect "third pushes middle over limit", run([a4, b4, c4]),
  [{"a", t(10)}, {"b", t(10, 40)}, {"c", t(11, 40)}]

# E. flag groups: different flags don't compete
a5 = mk("a", 10, flags: ["x"])
b5 = mk("b", 10, flags: ["y"])
expect "disjoint flags coexist", run([a5, b5]),
  [{"a", t(10)}, {"b", t(10)}]

# F. no flags = shared implicit group
a6 = mk("a", 10)
b6 = mk("b", 10, flags: ["y"])
expect "empty vs flagged don't compete", run([a6, b6]),
  [{"a", t(10)}, {"b", t(10)}]

# G. fixed vs movable: movable yields to fixed
a7 = mk("a", 10, dur: 1.hour, fixed: true)
b7 = mk("b", 10, 30, dur: 1.hour)
expect "movable yields to fixed", run([a7, b7]),
  [{"a", t(10)}, {"b", t(11)}]

# H. fixed vs fixed: second fixed dropped
a8 = mk("a", 10, dur: 1.hour, fixed: true)
b8 = mk("b", 10, 30, dur: 1.hour, fixed: true)
expect "fixed vs fixed drops later", run([a8, b8]),
  [{"a", t(10)}]

# I. fixed displaces movable scheduled earlier (via dependency ordering)
d9 = mk("d", 8, dur: 0.minutes)
f9 = mk("f", 10, dur: 1.hour, fixed: true)
f9.depends_on << d9
m9 = mk("m", 10, dur: 1.hour) # movable, scheduled before f (f waits on d)
# order: d,m (movable, id order d<m) then f. m@10:00. f fixed conflicts m ->
# displace m, which is then re-placed right after f.
expect "fixed displaces earlier movable", run([d9, f9, m9]),
  [{"d", t(8)}, {"f", t(10)}, {"m", t(11)}]

# J. priority displacement via dependency ordering
d10 = mk("d", 8, dur: 0.minutes)
h10 = mk("h", 10, dur: 1.hour, priority: 5)
h10.depends_on << d10
l10 = mk("l", 10, dur: 1.hour, priority: 0)
# order: d, l, then h. l@10. h prio 5 > 0, l not depended upon -> displace l,
# then l is re-placed right after h.
expect "priority displaces earlier lower-prio", run([d10, h10, l10]),
  [{"d", t(8)}, {"h", t(10)}, {"l", t(11)}]

# K. lower priority yields (scheduled later, conflicts with higher prio)
a11 = mk("a", 10, dur: 1.hour, priority: 5)
b11 = mk("b", 10, 30, dur: 30.minutes, priority: 1)
expect "low prio yields to high", run([a11, b11]),
  [{"a", t(10)}, {"b", t(11)}]

# L. dependency floor shifts candidate
a12 = mk("a", 10, dur: 1.hour)
b12 = mk("b", 9, dur: 30.minutes)
b12.depends_on << a12
expect "dependency floor", run([a12, b12]),
  [{"b", t(11)}, {"a", t(10)}].sort_by! { |x| x[1] }

# M. multiple candidates below floor collapse to one
a13 = mk("a", 10, dur: 1.hour)
b13 = VirtualDate.new("b")
b13.due << VirtualTime.new(minute: 0) # hourly
b13.duration = 10.minutes
b13.depends_on << a13
s13 = run([a13, b13], Time.utc(2025, 6, 2, 9), Time.utc(2025, 6, 2, 13))
expect "floor collapses dups", s13,
  [{"a", t(10)}, {"b", t(11)}, {"b", t(12)}]

# N. deadline reject
a14 = mk("a", 10, dur: 2.hours)
a14.deadline = t(11)
expect "hard deadline reject", run([a14]), [] of {String, Time}

# O. deadline exact fit
a15 = mk("a", 10, dur: 2.hours)
a15.deadline = t(12)
expect "deadline exact ok", run([a15]), [{"a", t(10)}]

# P. VirtualTime deadline resolved once
a16 = mk("a", 10, dur: 1.hour)
a16.deadline = VirtualTime.new(hour: 12, minute: 0)
b16 = mk("b", 10, dur: 2.hours, fixed: true)
# a movable: order fixed-first -> b@10:00-12:00. a conflicts -> yield to fixed, start=12:00,
# finish 13:00 > deadline 12:00 -> rejected.
expect "vt deadline blocks shifted", run([a16, b16]), [{"b", t(10)}]

# Q. stagger
a17 = mk("a", 10, dur: 30.minutes, parallel: 3)
a17.stagger = 10.minutes
expect "stagger 3", run([a17]),
  [{"a", t(10)}, {"a", t(10, 10)}, {"a", t(10, 20)}]

# R. stagger with parallel too low for overlap? parallel=2, stagger 10m, dur 30m:
# candidates 10:00, 10:10; both overlap; 2 <= 2 OK.
a18 = mk("a", 10, dur: 30.minutes, parallel: 2)
a18.stagger = 10.minutes
expect "stagger 2 overlapping", run([a18]),
  [{"a", t(10)}, {"a", t(10, 10)}]

# S. same-vdate consecutive occurrences overlap, parallel=1
a19 = VirtualDate.new("a")
a19.due << VirtualTime.new(hour: 10, minute: [0, 30])
a19.duration = 1.hour
s19 = run([a19])
expect "self overlap parallel=1", s19,
  [{"a", t(10)}, {"a", t(11)}]

# T. horizon: duration doesn't fit window
a20 = mk("a", 10, dur: 2.hours)
expect "horizon reject", run([a20], WFROM, t(11)), [] of {String, Time}
a21 = mk("a", 10, dur: 1.hour)
expect "horizon exact fit", run([a21], WFROM, t(11)), [{"a", t(10)}]

# U. depended-upon vdate scheduled over fixed conflict
a22 = mk("a", 10, dur: 1.hour, fixed: true)
b22 = mk("b", 10, dur: 1.hour)
c22 = mk("c", 13, dur: 30.minutes)
c22.depends_on << b22
expect "depended-upon overlaps fixed", run([a22, b22, c22]),
  [{"a", t(10)}, {"b", t(10)}, {"c", t(13)}]

# V. depended-upon unschedulable raises
a23 = mk("a", 10, dur: 2.hours)
a23.deadline = t(11)
c23 = mk("c", 13)
c23.depends_on << a23
begin
  run([a23, c23])
  puts "FAIL depended-upon unschedulable should raise"
  FAILS << "raise"
rescue e : ArgumentError
  puts "OK   depended-upon unschedulable raises (#{e.message})"
end

# W. build idempotency with step-iterator rules (mutation check)
a24 = VirtualDate.new("a")
a24.due << VirtualTime.new(minute: (0..59).step(15))
r1 = run([a24], WFROM, WFROM + 2.hours).map(&.start)
r2 = run([a24], WFROM, WFROM + 2.hours).map(&.start)
if r1 == r2
  puts "OK   build idempotent with step iterators (#{r1.size} occ)"
else
  puts "FAIL build not idempotent: #{r1.size} vs #{r2.size}: #{r1.first(5)} vs #{r2.first(5)}"
  FAILS << "idempotency"
end

# X. omit + shift span resolution
a25 = mk("a", 10, dur: 30.minutes)
a25.omit << VirtualTime.new(hour: 10)
a25.shift = 1.hour
expect "omit shift span", run([a25]), [{"a", t(11)}]

# Y. conflict shift lands on omitted time -> skipped further
a26 = mk("a", 10, dur: 1.hour, fixed: true)
b26 = mk("b", 10, dur: 30.minutes)
b26.omit << VirtualTime.new(hour: 11, minute: 0..29)
# b yields to a -> 11:00, omitted 11:00-11:29 -> stepped to 11:30
expect "post-conflict omit skip", run([a26, b26]),
  [{"a", t(10)}, {"b", t(11, 30)}]

# Z. max_shift bounds conflict shifting
a27 = mk("a", 10, dur: 2.hours, fixed: true)
b27 = mk("b", 10, dur: 30.minutes)
b27.max_shift = 1.hour
# b would need to move to 12:00 = 2h > 1h max_shift -> rejected
expect "max_shift bounds conflict shift", run([a27, b27]), [{"a", t(10)}]

puts
puts FAILS.empty? ? "ALL OK" : "FAILURES: #{FAILS.size}"
