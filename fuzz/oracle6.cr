require "../src/virtualdate"

# Adversarial: odd granularities, second-level combos, odd window starts.
# Oracle at 1-second sampling.

R = Random.new(777)

def brute(vd : VirtualDate, from : Time, to : Time, g : Time::Span) : Array(Time)
  starts = [] of Time
  prev : Time? = nil
  t = from
  while t < to
    if vd.due_on?(t) == true
      p = prev
      starts << t if p.nil? || (t - p) > g
      prev = t
    end
    t += 1.second
  end
  starts
end

def sched(vd : VirtualDate, from : Time, to : Time, g : Time::Span) : Array(Time)
  VirtualDate::Scheduler.new([vd]).build(from, to, granularity: g, max_candidates: 100000).map(&.start)
end

fails = 0
tested = 0

def rf(size : Int32, r : Random) : VirtualTime::Virtual
  case r.rand(5)
  when 0 then r.rand(size)
  when 1 then Array.new(r.rand(4) + 1) { r.rand(size) }.uniq
  when 2
    a = r.rand(size)
    (a..(a + r.rand(size - a)))
  when 3
    a = r.rand(size)
    (a..(a + r.rand(size - a))).step(r.rand(3) + 1)
  else
    nil
  end
end

250.times do |i|
  v = VirtualDate.new("t#{i}")
  (1 + R.rand(2)).times do
    v.due << VirtualTime.new(
      hour: R.rand(3) == 0 ? rf(24, R) : nil,
      minute: rf(60, R),
      second: R.rand(2) == 0 ? rf(60, R) : nil,
    )
  end
  from = Time.utc(2025, 6, 2, R.rand(24), R.rand(60), R.rand(60))
  to = from + (30 + R.rand(150)).minutes
  g = [10.seconds, 30.seconds, 45.seconds, 1.minute, 90.seconds, 7.minutes, 11.minutes, 13.minutes][R.rand(8)]

  exp = brute(v, from, to, g)
  act = begin
    sched(v, from, to, g)
  rescue e
    puts "ERR #{i}: #{e.class} #{e.message}"
    v.due.each { |d| puts "  rule h=#{d.hour.inspect} m=#{d.minute.inspect} s=#{d.second.inspect}" }
    puts "  from=#{from} to=#{to} g=#{g}"
    fails += 1
    next
  end
  tested += 1
  next if exp == act
  fails += 1
  puts "FAIL #{i}: from=#{from} to=#{to} g=#{g}"
  v.due.each { |d| puts "  rule h=#{d.hour.inspect} m=#{d.minute.inspect} s=#{d.second.inspect}" }
  puts "  exp #{exp.size}: #{exp.first(10)}"
  puts "  act #{act.size}: #{act.first(10)}"
  puts "  missing: #{(exp - act).first(6)}"
  puts "  extra: #{(act - exp).first(6)}"
  break if fails > 5
end

puts "done: #{tested} compared, #{fails} failures"
