require "../src/virtualdate"

# Fuzz: hour-granularity rules over a few days; compare on?(t) with ground truth
# computed from resolve() over all bases in window.
rng = Random.new(42)
fails = 0

100.times do |trial|
  vd = VirtualDate.new "f#{trial}"

  # due: 1-2 rules constraining hour
  rng.rand(1..2).times do
    v = VirtualTime.new
    v.hour = rng.rand(0..23)
    v.day = rng.rand(10..12) if rng.next_bool
    vd.due << v
  end
  # omit: 0-2 rules
  rng.rand(0..2).times do
    v = VirtualTime.new
    case rng.rand(3)
    when 0 then v.hour = rng.rand(0..23)
    when 1 then v.hour = rng.rand(0..20)..rng.rand(21..23)
    else        v.day = rng.rand(10..12)
    end
    vd.omit << v
  end

  vd.shift = case rng.rand(4)
             when 0 then 1.hour
             when 1 then -1.hour
             when 2 then 3.hours
             else        false
             end
  vd.max_shifts = rng.rand(1..30)
  vd.max_shift = rng.next_bool ? rng.rand(1..10).hours : nil
  if rng.next_bool
    vd.begin = Time.utc(2024, 5, 10, rng.rand(0..5))
  end
  if rng.next_bool
    vd.end = Time.utc(2024, 5, 12, rng.rand(18..23))
  end

  window = (0...72).map { |h| Time.utc(2024, 5, 10) + h.hours }

  # ground truth: t is "on" iff resolve(t) == true, or some base in a wide window resolves to t
  wide = (-96...168).map { |h| Time.utc(2024, 5, 10) + h.hours }
  reachable = Set(Time).new
  wide.each do |base|
    r = vd.resolve(base)
    case r
    when true then reachable << base
    when Time then reachable << r
    end
  end

  window.each do |t|
    expected = reachable.includes?(t)
    actual = vd.on?(t)
    if expected != actual
      fails += 1
      if fails <= 5
        puts "MISMATCH trial=#{trial} t=#{t} expected=#{expected} actual=#{actual}"
        puts "  due=#{vd.due.inspect}"
        puts "  omit=#{vd.omit.inspect}"
        puts "  shift=#{vd.shift.inspect} max_shifts=#{vd.max_shifts} max_shift=#{vd.max_shift.inspect} begin=#{vd.begin.inspect} end=#{vd.end.inspect}"
        puts "  strict_on?(t)=#{vd.strict_on?(t).inspect} resolve(t)=#{vd.resolve(t).inspect}"
      end
    end
  end
end
puts "fuzz fails: #{fails}"
