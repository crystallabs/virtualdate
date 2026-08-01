require "../src/virtualdate"

# Brute-force oracle for Scheduler occurrence scanning.
# All rules used here are minute-resolution or coarser, so sampling every
# minute exactly captures the matching stretches of continuous time.
# A "run" is a maximal set of matching minutes where consecutive matching
# minutes are <= granularity apart (this equals the scheduler's continuous-time
# merge criterion for minute-resolution rules, see analysis).

UTC = Time::Location::UTC

def brute_starts(vd : VirtualDate, from : Time, to : Time, granularity : Time::Span) : Array(Time)
  starts = [] of Time
  prev_match : Time? = nil
  t = from
  step = 1.minute
  while t < to
    if vd.due_on?(t) == true
      pm = prev_match
      if pm.nil? || (t - pm) > granularity
        starts << t
      end
      prev_match = t
    end
    t += step
  end
  starts
end

def sched_starts(vd : VirtualDate, from : Time, to : Time, granularity : Time::Span, maxc = 10000) : Array(Time)
  s = VirtualDate::Scheduler.new([vd])
  s.build(from, to, granularity: granularity, max_candidates: maxc).map(&.start)
end

FAILS = [] of String

def check(name : String, vd : VirtualDate, from : Time, to : Time, granularity : Time::Span = 1.minute)
  exp = brute_starts(vd, from, to, granularity)
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
    missing = exp - act
    extra = act - exp
    puts "  expected #{exp.size}, actual #{act.size}"
    puts "  first expected: #{exp.first(6)}"
    puts "  first actual:   #{act.first(6)}"
    puts "  missing: #{missing.first(8)}"
    puts "  extra:   #{extra.first(8)}"
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

f = Time.utc(2025, 6, 2, 0, 0, 0) # Monday
d1 = 1.day
d3 = 3.days

# 1. contiguous hour block
check "hour 9..17", vd { |v| v.due << rule(hour: 9..17) }, f, f + d3
# 2. exclusive range
check "hour 9...17", vd { |v| v.due << rule(hour: 9...17) }, f, f + d3
# 3. minute list
check "minute [0,15,30,45]", vd { |v| v.due << rule(minute: [0, 15, 30, 45]) }, f, f + 4.hours
# 4. contiguous minute set pieces
check "minute [0,1,2,3,10,11,20]", vd { |v| v.due << rule(minute: [0, 1, 2, 3, 10, 11, 20]) }, f, f + 3.hours
# 5. Set
check "minute Set{5,6,7,20}", vd { |v| v.due << rule(minute: Set{5, 6, 7, 20}) }, f, f + 3.hours
# 6. stepped minutes
check "minute (0..59).step(5)", vd { |v| v.due << rule(minute: (0..59).step(5)) }, f, f + 3.hours
# 7. step 1 iterator
check "minute (0..30).step(1)", vd { |v| v.due << rule(minute: (0..30).step(1)) }, f, f + 3.hours
# 8. exclusive step iterator
check "minute (0...30).step(1)", vd { |v| v.due << rule(minute: (0...30).step(1)) }, f, f + 3.hours
# 9. day+hour combo
check "day [1,15] hour 10", vd { |v| v.due << rule(day: [1, 15], hour: 10) }, f, f + 60.days
# 10. hour range + minute range
check "hour 10..12 minute 0..29", vd { |v| v.due << rule(hour: 10..12, minute: 0..29) }, f, f + 2.days
# 11. day_of_week
check "dow [1,3] hour 9", vd { |v| v.due << rule(day_of_week: [1, 3], hour: 9) }, f, f + 14.days
# 12. midnight wrap
check "hour [23,0]", vd { |v| v.due << rule(hour: [23, 0]) }, f + 12.hours, f + 12.hours + d3
# 13. two rules adjacent -> merge
check "hour 9..12 OR 13..17", vd { |v| v.due << rule(hour: 9..12); v.due << rule(hour: 13..17) }, f, f + d3
# 14. two rules non-adjacent
check "min 0..10 OR 12..20", vd { |v| v.due << rule(minute: 0..10); v.due << rule(minute: 12..20) }, f, f + 3.hours
# 15. full minute range + hour
check "hour 10 minute 0..59", vd { |v| v.due << rule(hour: 10, minute: 0..59) }, f, f + d3
# 16. full minute array + hour range
check "hour 10..11 minute all-array", vd { |v| v.due << rule(hour: 10..11, minute: (0..59).to_a) }, f, f + d3
# 17. bool true field
check "hour true minute [10]", vd { |v| v.due << rule(hour: true, minute: [10]) }, f, f + 3.hours
# 18. month only
check "month 6", vd { |v| v.due << rule(month: 6) }, Time.utc(2025, 5, 15), Time.utc(2025, 8, 15)
# 19. impossible day/month
check "day 31 month 2", vd { |v| v.due << rule(month: 2, day: 31) }, f, f + 30.days
# 20. negative minute range
check "minute -10..-1", vd { |v| v.due << rule(minute: -10..-1) }, f, f + 3.hours
# 21. minute wrap across hour
check "minute [55..59,0]", vd { |v| v.due << rule(minute: [55, 56, 57, 58, 59, 0]) }, f, f + 3.hours
# 22. granularity 5min with sparse minutes
check "minute [0,2,4,6] g=5m", vd { |v| v.due << rule(minute: [0, 2, 4, 6]) }, f, f + 3.hours, 5.minutes
# 23. granularity 5min, run not sampled at whole minutes
check "minute [2,3] g=5m", vd { |v| v.due << rule(minute: [2, 3]) }, f, f + 3.hours, 5.minutes
# 24. granularity 2min even minutes merge
check "even minutes g=2m", vd { |v| v.due << rule(minute: (0..58).step(2)) }, f, f + 3.hours, 2.minutes
# 25. window starting mid-run
check "hour 9..17 from 10:30", vd { |v| v.due << rule(hour: 9..17) }, f + 10.hours + 30.minutes, f + 2.days
# 26. sparse: two runs overshoot bait (month list + day list)
check "month [6,8] day [1,20]", vd { |v| v.due << rule(month: [6, 8], day: [1, 20]) }, Time.utc(2025, 5, 1), Time.utc(2025, 10, 1)
# 27. minute range 0..59 alone (always on within each minute -> one run whole window)
check "minute 0..59", vd { |v| v.due << rule(minute: 0..59) }, f, f + d1
# 28. hour 0..23 (full range)
check "hour 0..23", vd { |v| v.due << rule(hour: 0..23) }, f, f + d1
# 29. day_of_week weekend all day
check "dow [6,7]", vd { |v| v.due << rule(day_of_week: [6, 7]) }, f, f + 14.days
# 30. hour 9..17 with granularity 30min
check "hour 9..17 g=30m", vd { |v| v.due << rule(hour: 9..17) }, f, f + d3, 30.minutes
# 31. two rules: dense + sparse
check "min [0] OR day 15 hour 3", vd { |v| v.due << rule(minute: [0]); v.due << rule(day: 15, hour: 3) }, f, f + 20.days
# 32. year-pinned rule
check "year 2025 month 7 day 4", vd { |v| v.due << rule(year: 2025, month: 7, day: 4) }, f, f + 90.days
# 33. minute list separated by exactly granularity+1
check "minute [10,12] g=1m", vd { |v| v.due << rule(minute: [10, 12]) }, f, f + 3.hours
# 34. minute [10,12] g=2m -> merge
check "minute [10,12] g=2m", vd { |v| v.due << rule(minute: [10, 12]) }, f, f + 3.hours, 2.minutes
# 35. hour [9, 11] separate blocks
check "hour [9,11]", vd { |v| v.due << rule(hour: [9, 11]) }, f, f + d3
# 36. week-based rule
check "week 25 dow 3", vd { |v| v.due << rule(week: 25, day_of_week: 3) }, Time.utc(2025, 6, 1), Time.utc(2025, 7, 15)
# 37. day_of_year rule
check "day_of_year [160,161]", vd { |v| v.due << rule(day_of_year: [160, 161]) }, Time.utc(2025, 6, 1), Time.utc(2025, 6, 20)

puts
if FAILS.empty?
  puts "ALL OK"
else
  puts "FAILURES: #{FAILS.join(", ")}"
end
