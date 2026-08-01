require "../src/virtualdate"

# Multi-vdate scheduling fuzzer with invariant checks.

R = Random.new(424242)

WFROM = Time.utc(2025, 6, 2, 0, 0, 0)

def overlaps?(a_s, a_e, b_s, b_e)
  a_s < b_e && b_s < a_e
end

def shares?(a : VirtualDate, b : VirtualDate)
  a.flags.empty? ? b.flags.empty? : a.flags.any? { |fl| b.flags.includes?(fl) }
end

failures = 0
runs = 0

500.times do |iter|
  n = 2 + R.rand(4)
  vdates = [] of VirtualDate
  n.times do |i|
    v = VirtualDate.new("v#{i}")
    # due: one or two rules, hour+minute
    (1 + R.rand(2)).times do
      hour = R.rand(3) == 0 ? (R.rand(20)..(R.rand(4) + 20)) : R.rand(24)
      minute = [nil, 0, [0, 30], (0..59).step(20)][R.rand(4)]
      case minute
      when Nil then v.due << VirtualTime.new(hour: hour)
      else          v.due << VirtualTime.new(hour: hour, minute: minute)
      end
    end
    v.duration = [0, 10, 30, 45, 90, 150][R.rand(6)].minutes
    v.parallel = 1 + R.rand(3)
    v.priority = R.rand(3)
    v.fixed = R.rand(4) == 0
    case R.rand(3)
    when 0 then v.flags << "x"
    when 1 then v.flags << "y"
    end
    v.flags << "z" if R.rand(4) == 0
    if R.rand(3) == 0
      v.omit << VirtualTime.new(hour: R.rand(24))
      v.shift = [false, true, 30.minutes, 2.hours][R.rand(4)].as(Bool | Time::Span)
    end
    if R.rand(4) == 0
      v.deadline = WFROM + (R.rand(30) + 6).hours
    end
    if R.rand(5) == 0 && v.parallel > 1
      v.stagger = (5 + R.rand(30)).minutes
    end
    # acyclic deps: only on earlier-created vdates
    if i > 0 && R.rand(3) == 0
      v.depends_on << vdates[R.rand(i)]
    end
    vdates << v
  end

  wto = WFROM + (12 + R.rand(36)).hours

  sched = begin
    VirtualDate::Scheduler.new(vdates).build(WFROM, wto)
  rescue e : ArgumentError
    msg = e.message.to_s
    if msg.starts_with?("Failed to schedule vdate")
      next # legitimate documented outcome
    end
    puts "ERR iter #{iter}: #{e.message}"
    failures += 1
    next
  end
  runs += 1

  problems = [] of String

  # I1: no same vdate twice at same start
  sched.group_by { |s| {s.vdate.id, s.start} }.each do |k, g|
    problems << "duplicate #{k}" if g.size > 1
  end

  # I2: window bounds
  sched.each do |s|
    problems << "#{s.vdate.id} start #{s.start} outside window" if s.start < WFROM || s.start >= wto
    problems << "#{s.vdate.id} finish #{s.finish} past horizon" if s.finish > wto
  end

  # I3: parallelism (skip deliberate over-subscription)
  oversub = sched.select { |s| s.explanation.lines.any?(&.includes?("despite conflicts")) }
  sched.each do |s|
    next if oversub.includes?(s)
    cnt = 1
    sched.each do |o|
      next if o.same?(s)
      next unless shares?(s.vdate, o.vdate)
      next unless overlaps?(s.start, s.finish, o.start, o.finish)
      cnt += 1 unless oversub.includes?(o)
    end
    if cnt > s.vdate.parallel
      problems << "#{s.vdate.id}@#{s.start} parallelism #{cnt} > #{s.vdate.parallel}"
    end
  end

  # I4: no start on omitted time (unless shift==true or on override)
  sched.each do |s|
    v = s.vdate
    next unless v.on.nil?
    next if v.shift == true
    if v.omit_on?(s.start) == true
      problems << "#{v.id}@#{s.start} starts on omitted time"
    end
  end

  # I5: deadline respected
  sched.each do |s|
    if (dl = s.vdate.deadline).is_a?(Time)
      problems << "#{s.vdate.id}@#{s.start} finish #{s.finish} > deadline #{dl}" if s.finish > dl
    end
  end

  # I6: dependency floor (weak form: after the earliest scheduled finish of each dep)
  sched.each do |s|
    s.vdate.depends_on.each do |dep|
      dep_occ = sched.select { |o| o.vdate.same?(dep) }
      if dep_occ.empty?
        problems << "#{s.vdate.id} scheduled but dependency #{dep.id} absent"
      elsif s.start < dep_occ.min_of(&.finish)
        problems << "#{s.vdate.id}@#{s.start} starts before dep #{dep.id} earliest finish #{dep_occ.min_of(&.finish)}"
      end
    end
  end

  unless problems.empty?
    failures += 1
    puts "FAIL iter #{iter}:"
    problems.each { |p| puts "  #{p}" }
    vdates.each do |v|
      puts "  vdate #{v.id}: due=#{v.due.map { |d| {d.hour, d.minute} }} dur=#{v.duration} par=#{v.parallel} prio=#{v.priority} fixed=#{v.fixed?} flags=#{v.flags.to_a} omit=#{v.omit.map(&.hour)} shift=#{v.shift} deadline=#{v.deadline} stagger=#{v.stagger} deps=#{v.depends_on.map(&.id)}"
    end
    sched.each { |s| puts "  sched #{s.vdate.id} #{s.start}..#{s.finish}" }
    if failures > 5
      puts "too many failures, stopping"
      exit 1
    end
  end
end

puts "fuzz complete: #{runs} schedules checked, #{failures} failures"
