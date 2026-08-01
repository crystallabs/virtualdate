require "../src/virtualdate"

FAILS = [] of String

def t(h, m = 0)
  Time.utc(2025, 6, 2, h, m, 0)
end

WFROM = Time.utc(2025, 6, 2, 0, 0, 0)
WTO   = Time.utc(2025, 6, 3, 0, 0, 0)

def mk(id, hour, minute = 0, *, dur = 30.minutes, parallel = 1, priority = 0, fixed = false)
  v = VirtualDate.new(id)
  v.due << VirtualTime.new(hour: hour, minute: minute)
  v.duration = dur
  v.parallel = parallel
  v.priority = priority
  v.fixed = fixed
  v
end

def run(vdates, from = WFROM, to = WTO)
  VirtualDate::Scheduler.new(vdates).build(from, to)
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

# Force ordering: l scheduled BEFORE h by making h depend on z (id sorts after l).
z1 = mk("z", 8, dur: 0.minutes)
h1 = mk("h", 10, dur: 1.hour, priority: 5)
h1.depends_on << z1
l1 = mk("l", 10, dur: 1.hour, priority: 0)
# order: l (id l < z? 'l' < 'z' yes) -> l first, then z, then h.
# h prio 5 > l prio 0, l not depended upon -> displace l; l is re-placed after h.
expect "priority displaces earlier lower-prio", run([z1, h1, l1]),
  [{"z", t(8)}, {"h", t(10)}, {"l", t(11)}]

# fixed displaces earlier movable
z2 = mk("z", 8, dur: 0.minutes)
f2 = mk("f", 10, dur: 1.hour, fixed: true)
f2.depends_on << z2
m2 = mk("m", 10, dur: 1.hour)
expect "fixed displaces earlier movable", run([z2, f2, m2]),
  [{"z", t(8)}, {"f", t(10)}, {"m", t(11)}]

# guard: earlier movable that is depended upon is NOT displaced by priority
z3 = mk("z", 8, dur: 0.minutes)
h3 = mk("h", 10, dur: 1.hour, priority: 5)
h3.depends_on << z3
l3 = mk("l", 10, dur: 1.hour, priority: 0)
c3 = mk("c", 15, dur: 10.minutes)
c3.depends_on << l3
# l depended upon -> h yields instead, shifts to 11:00
expect "depended-upon lower-prio survives", run([z3, h3, l3, c3]),
  [{"z", t(8)}, {"l", t(10)}, {"h", t(11)}, {"c", t(15)}]

# guard: fixed cannot displace depended-upon movable -> fixed dropped
z4 = mk("z", 8, dur: 0.minutes)
f4 = mk("f", 10, dur: 1.hour, fixed: true)
f4.depends_on << z4
m4 = mk("m", 10, dur: 1.hour)
c4 = mk("c", 15, dur: 10.minutes)
c4.depends_on << m4
expect "fixed dropped vs depended-upon", run([z4, f4, m4, c4]),
  [{"z", t(8)}, {"m", t(10)}, {"c", t(15)}]

# displaced vdate as dependency anchor sanity: h displaces l AFTER l's dependent
# was already scheduled? Not possible (dependents come after l AND after h? no --
# c depends only on l so c can come before h if ids sort so). Try: c depends on l,
# h depends on z; order: c? indegree c=1 until l done. ready={l, z}: l first, then
# ready={z, c}: c first (id c<z), c scheduled against l's finish. then z, then h.
# h conflicts l -> l depended upon -> h yields. good; covered above by c3 case.

# Zero-duration pair at same instant, parallel=1 (documented: no overlap)
a5 = mk("a", 10, dur: 0.minutes)
b5 = mk("b", 10, dur: 0.minutes)
expect "zero-duration coexist", run([a5, b5]),
  [{"a", t(10)}, {"b", t(10)}]

# on_in_schedule?
s = VirtualDate::Scheduler.new([mk("a", 10, dur: 1.hour)])
sch = s.build(WFROM, WTO)
ok = s.on_in_schedule?(sch, sch.first.vdate, t(10)) &&
     s.on_in_schedule?(sch, sch.first.vdate, t(10, 59)) &&
     !s.on_in_schedule?(sch, sch.first.vdate, t(11)) &&
     !s.on_in_schedule?(sch, sch.first.vdate, t(9, 59))
puts ok ? "OK   on_in_schedule? boundaries" : (FAILS << "onin"; "FAIL on_in_schedule? boundaries").to_s

# zero-duration on_in_schedule?
s2 = VirtualDate::Scheduler.new([mk("a", 10, dur: 0.minutes)])
sch2 = s2.build(WFROM, WTO)
ok2 = s2.on_in_schedule?(sch2, sch2.first.vdate, t(10)) && !s2.on_in_schedule?(sch2, sch2.first.vdate, t(10, 1))
puts ok2 ? "OK   on_in_schedule? zero-dur" : (FAILS << "onin0"; "FAIL on_in_schedule? zero-dur").to_s

# cycle detection
c6 = VirtualDate.new("x")
d6 = VirtualDate.new("y")
c6.due << VirtualTime.new(hour: 10)
d6.due << VirtualTime.new(hour: 11)
c6.depends_on << d6
d6.depends_on << c6
begin
  VirtualDate::Scheduler.new([c6, d6])
  puts "FAIL cycle not detected"
  FAILS << "cycle"
rescue e : ArgumentError
  puts "OK   cycle detected (#{e.message})"
end

# self-cycle
e7 = VirtualDate.new("e")
e7.due << VirtualTime.new(hour: 10)
e7.depends_on << e7
begin
  VirtualDate::Scheduler.new([e7])
  puts "FAIL self-cycle not detected"
  FAILS << "selfcycle"
rescue e : ArgumentError
  puts "OK   self-cycle detected"
end

# dependency on vdate missing from scheduler list must raise
a8 = mk("a", 10)
ghost = mk("g", 9)
a8.depends_on << ghost
begin
  VirtualDate::Scheduler.new([a8]).build(WFROM, WTO)
  puts "FAIL dependency-on-outside-vdate did not raise"
  FAILS << "outside-dep"
rescue e : ArgumentError
  puts "OK   dependency-on-outside-vdate raises (#{e.message})"
end

# === DST checks ===
ny = Time::Location.load("America/New_York")

def brute_starts(vd : VirtualDate, from : Time, to : Time, granularity : Time::Span) : Array(Time)
  starts = [] of Time
  prev_match : Time? = nil
  t = from
  while t < to
    if vd.due_on?(t) == true
      pm = prev_match
      starts << t if pm.nil? || (t - pm) > granularity
      prev_match = t
    end
    t += 1.minute
  end
  starts
end

def dst_check(name, vd, from, to)
  exp = brute_starts(vd, from, to, 1.minute)
  act = VirtualDate::Scheduler.new([vd]).build(from, to).map(&.start)
  if exp == act
    puts "OK   #{name} (#{exp.size})"
  else
    FAILS << name
    puts "FAIL #{name}"
    puts "  expected: #{exp}"
    puts "  actual:   #{act}"
  end
end

# fall-back 2025-11-02 in NY: 1:00-1:59 happens twice
vfb = VirtualDate.new("fb")
vfb.due << VirtualTime.new(hour: 1)
dst_check "DST fall-back hour 1", vfb, Time.local(2025, 11, 1, 22, 0, 0, location: ny), Time.local(2025, 11, 2, 6, 0, 0, location: ny)

# spring-forward 2025-03-09 in NY: hour 2 missing
vsf = VirtualDate.new("sf")
vsf.due << VirtualTime.new(hour: 2)
dst_check "DST gap hour 2", vsf, Time.local(2025, 3, 8, 22, 0, 0, location: ny), Time.local(2025, 3, 9, 6, 0, 0, location: ny)

# spring-forward: hour 1..3 -> one contiguous run across the gap
vsf2 = VirtualDate.new("sf2")
vsf2.due << VirtualTime.new(hour: 1..3)
dst_check "DST gap hour 1..3", vsf2, Time.local(2025, 3, 8, 22, 0, 0, location: ny), Time.local(2025, 3, 9, 6, 0, 0, location: ny)

# fall-back: minute rule around the fold
vfb2 = VirtualDate.new("fb2")
vfb2.due << VirtualTime.new(hour: 1, minute: 30)
dst_check "DST fall-back 1:30", vfb2, Time.local(2025, 11, 2, 0, 0, 0, location: ny), Time.local(2025, 11, 2, 4, 0, 0, location: ny)

puts
puts FAILS.empty? ? "ALL OK" : "FAILURES: #{FAILS.size}"
