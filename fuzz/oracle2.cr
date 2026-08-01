require "../src/virtualdate"

# Randomized fuzzing of Scheduler occurrence scanning against a
# minute-sampled brute-force oracle. Minute-resolution-or-coarser rules only.

def brute_starts(vd : VirtualDate, from : Time, to : Time, granularity : Time::Span) : Array(Time)
  starts = [] of Time
  prev_match : Time? = nil
  t = from
  step = 1.minute
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

def sched_starts(vd : VirtualDate, from : Time, to : Time, granularity : Time::Span, maxc : Int32) : Array(Time)
  s = VirtualDate::Scheduler.new([vd])
  s.build(from, to, granularity: granularity, max_candidates: maxc).map(&.start)
end

R = Random.new(20250801)

def rand_field(size : Int32, sparse : Bool) : VirtualTime::Virtual
  lo = sparse ? 0 : 0
  case R.rand(6)
  when 0 # single value
    R.rand(size)
  when 1 # array of 1..5 values
    Array.new(R.rand(5) + 1) { R.rand(size) }.uniq
  when 2 # range
    a = R.rand(size)
    b = a + R.rand(size - a)
    R.rand(2) == 0 ? (a..b) : (a...(b + 1))
  when 3 # stepped range
    a = R.rand(size)
    b = a + R.rand(size - a)
    (a..b).step(R.rand(4) + 1)
  when 4 # contiguous small range
    a = R.rand(size - 3)
    (a..(a + R.rand(3)))
  else # nil (unconstrained)
    nil
  end
end

fails = 0
tests = 0

400.times do |i|
  vt_count = R.rand(3) + 1
  v = VirtualDate.new("f#{i}")
  vt_count.times do
    kw_hour = rand_field(24, false)
    kw_min = rand_field(60, false)
    # sometimes constrain day or dow
    day = R.rand(4) == 0 ? (R.rand(28) + 1) : nil
    dow = R.rand(5) == 0 ? (R.rand(7) + 1) : nil
    vt = VirtualTime.new(hour: kw_hour, minute: kw_min, day: day, day_of_week: dow)
    v.due << vt
  end

  from = Time.utc(2025, 1 + R.rand(12), 1 + R.rand(27), R.rand(24), R.rand(60))
  window = (R.rand(3 * 24 * 60) + 60).minutes # 1h .. 3d
  to = from + window
  g = [1, 1, 1, 2, 5, 7, 30][R.rand(7)].minutes
  maxc = 100000

  exp = brute_starts(v, from, to, g)
  act = begin
    sched_starts(v, from, to, g, maxc)
  rescue e
    puts "ERR case #{i}: #{e.class}: #{e.message}"
    puts "  rules: #{v.due.map(&.to_s)}"
    puts "  from=#{from} to=#{to} g=#{g}"
    fails += 1
    next
  end
  tests += 1
  next if exp == act

  fails += 1
  puts "FAIL case #{i}: from=#{from} to=#{to} g=#{g}"
  v.due.each { |vt| puts "  rule: hour=#{vt.hour.inspect} minute=#{vt.minute.inspect} day=#{vt.day.inspect} dow=#{vt.day_of_week.inspect}" }
  puts "  expected #{exp.size}: #{exp.first(8)}"
  puts "  actual   #{act.size}: #{act.first(8)}"
  puts "  missing: #{(exp - act).first(8)}"
  puts "  extra:   #{(act - exp).first(8)}"
  break if fails > 6
end

puts "fuzz done: #{tests} compared, #{fails} failures"

# --- max_candidates cut logic: expected = first N of full oracle ---
puts
cut_fails = 0
60.times do |i|
  v = VirtualDate.new("c#{i}")
  v.due << VirtualTime.new(minute: [0, 30])                # dense: every half hour
  v.due << VirtualTime.new(hour: R.rand(24), minute: R.rand(60)) # sparse
  v.due << VirtualTime.new(day: 1 + R.rand(28), hour: R.rand(24)) if R.rand(2) == 0

  from = Time.utc(2025, 1 + R.rand(12), 1 + R.rand(27), R.rand(24), 0)
  to = from + (2 + R.rand(5)).days
  g = 1.minute
  maxc = 1 + R.rand(9) # small cap

  full = brute_starts(v, from, to, g)
  exp = full.first(maxc)
  act = begin
    sched_starts(v, from, to, g, maxc)
  rescue e
    puts "ERR cut case #{i}: #{e.message}"
    cut_fails += 1
    next
  end
  next if exp == act
  cut_fails += 1
  puts "FAIL cut case #{i}: from=#{from} to=#{to} maxc=#{maxc}"
  v.due.each { |vt| puts "  rule: day=#{vt.day.inspect} hour=#{vt.hour.inspect} minute=#{vt.minute.inspect}" }
  puts "  expected: #{exp}"
  puts "  actual:   #{act}"
  break if cut_fails > 4
end
puts "cut-logic fuzz done, #{cut_fails} failures"
