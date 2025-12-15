require "spec"
require "../src/virtualdate"

describe VirtualDate do
  it "honors begin/end dates" do
    vd = VirtualDate.new
    vd.begin = Time.parse_local("2017-1-1", "%F")
    vd.end = Time.parse_local("2017-2-28", "%F")
    date = Time.parse_local("2017-3-15", "%F")
    vd.on?(date).should be_nil
    date = Time.parse_local("2017-2-1", "%F")
    vd.due_on?(date).should be_true

    vd = VirtualDate.new
    vd.begin = Time.parse_local("2017-6-1", "%F")
    vd.end = Time.parse_local("2017-9-1", "%F")
    date = Time.parse_local("2017-3-15", "%F")
    vd.on?(date).should be_nil

    vd = VirtualDate.new
    vd.begin = Time.parse_local("2017-1-1", "%F")
    vd.end = Time.parse_local("2017-9-1", "%F")
    date = Time.parse_local("2017-3-15 10:10:10", "%F %X")
    vd.on?(date).should be_true
  end

  it "honors begin/end as VirtualTime" do
    vd = VirtualDate.new
    vd.begin = VirtualTime.new(day: 10..20)
    vd.on?(Time.local(2023, 5, 9)).should be_nil
    vd.on?(Time.local(2023, 5, 14)).should be_true
    vd.on?(Time.local(2023, 5, 21)).should be_nil
  end

  it "on override takes precedence over begin/end" do
    vd = VirtualDate.new
    vd.begin = Time.local(2023, 1, 1)
    vd.end = Time.local(2023, 1, 2)

    vd.on = true
    vd.on?(Time.local(2024, 1, 1)).should be_true

    vd.on = false
    vd.on?(Time.local(2023, 1, 1)).should be_false
  end

  it "honors due dates" do
    date = Time.parse_local("2017-3-15 10:10:10", "%F %X")

    vd = VirtualDate.new
    vd.begin = Time.parse_local("2017-1-1", "%F")
    vd.end = Time.parse_local("2017-9-1", "%F")

    vd.due_on?(date).should be_true

    vt = VirtualTime.new
    vd.due << vt

    vd.due_on?(date).should be_true

    # Year tests:

    vt.year = 2016
    vd.due_on?(date).should be_nil

    vt.year = 2018
    vd.due_on?(date).should be_nil

    vt.year = 2017
    vd.due_on?(date).should be_true

    # Month tests:

    vt.month = 2
    vd.due_on?(date).should be_nil

    vt.month = 4
    vd.due_on?(date).should be_nil

    vt.month = 3
    vd.due_on?(date).should be_true

    # Day tests:

    vt.day = 2
    vd.due_on?(date).should be_nil

    vt.day = 16
    vd.due_on?(date).should be_nil

    vt.day = 15
    vd.due_on?(date).should be_true

    # Weekday tests:

    vt.year = nil
    vt.month = nil
    vt.day = nil
    vd.due_on?(date).should be_true
    vt.day_of_week = 0
    vd.due_on?(date).should be_nil
    vt.day_of_week = 2
    vd.due_on?(date).should be_nil
    vt.day_of_week = 4
    vd.due_on?(date).should be_nil
    vt.day_of_week = 3

    date = Time.parse_local("2017-3-15 10:10:10", "%F %X")
    vd.due_on?(date).should be_true

    # Test with more than one due date:

    vt2 = VirtualTime.new
    vd.due << vt2
    # This matches because both vt and vt2 would match:
    vd.due_on?(date).should be_true

    vt.day = 15
    vd.due_on?(date).should be_true

    vt2.month = 3
    # Again both vt and vt2 now match:
    vd.due_on?(date).should be_true

    vt.day = 3
    # vt is out, but vt2 should still be matching:
    vd.due_on?(date).should be_true

    vt2.month = 9
    # Now it no longer matches:
    vd.due_on?(date).should be_nil
  end

  # Identical copy of the above, but testing omit dates instead of due dates
  it "honors omit dates" do
    date = Time.parse_local("2017-3-15", "%F")

    vd = VirtualDate.new
    vd.begin = Time.parse_local("2017-1-1", "%F")
    vd.end = Time.parse_local("2017-9-1", "%F")

    vd.omit_on?(date).should be_nil

    vt = VirtualTime.new
    vd.omit << vt

    vd.omit_on?(date).should be_true

    # Year tests:

    vt.year = 2016
    vd.omit_on?(date).should be_nil

    vt.year = 2018
    vd.omit_on?(date).should be_nil

    vt.year = 2017
    vd.omit_on?(date).should be_true

    # Month tests:

    vt.month = 2
    vd.omit_on?(date).should be_nil

    vt.month = 4
    vd.omit_on?(date).should be_nil

    vt.month = 3
    vd.omit_on?(date).should be_true

    # Day tests:

    vt.day = 2
    vd.omit_on?(date).should be_nil

    vt.day = 16
    vd.omit_on?(date).should be_nil

    vt.day = 15
    vd.omit_on?(date).should be_true

    # Weekday tests:

    vt.year = nil
    vt.month = nil
    vt.day = nil
    vd.omit_on?(date).should be_true
    vt.day_of_week = 0
    vd.omit_on?(date).should be_nil
    vt.day_of_week = 2
    vd.omit_on?(date).should be_nil
    vt.day_of_week = 4
    vd.omit_on?(date).should be_nil
    vt.day_of_week = 3
    vd.omit_on?(date).should be_true

    # Test with more than one omit date:

    vt2 = VirtualTime.new
    vd.omit << vt2
    # This matches because both vd and vt2 would match:
    vd.omit_on?(date).should be_true

    vt.day = 15
    # vd matches:
    vd.omit_on?(date).should be_true

    vt2.month = 3
    # Again both vd and vt2 now match:
    vd.omit_on?(date).should be_true

    vt.day = 3
    # vd is out, but vt2 should still be matching:
    vd.omit_on?(date).should be_true

    vt.month = 9
    # Now it no longer matches:
    vd.omit_on?(date).should be_true
    vd.on?(date).should be_false
  end

  it "shift = true ignores omit rules" do
    vd = VirtualDate.new
    due = VirtualTime.new(day: 15)
    omit = VirtualTime.new(day: 15)

    vd.due << due
    vd.omit << omit
    vd.shift = true

    vd.on?(Time.local(2023, 3, 15)).should be_true
  end

  it "shift = nil treats omitted date as not applicable" do
    vd = VirtualDate.new
    due = VirtualTime.new(day: 15)
    omit = VirtualTime.new(day: 15)

    vd.due << due
    vd.omit << omit
    vd.shift = nil

    vd.on?(Time.local(2023, 3, 15)).should be_nil
  end

  it "handles DST transitions when shifting" do
    loc = Time::Location.load("Europe/Berlin")
    date = Time.local(2023, 3, 26, 1, 30, location: loc)

    vd = VirtualDate.new
    vd.shift = 1.hour

    omit = VirtualTime.from_time(date)
    vd.omit << omit

    vd.on?(date).should eq 1.hour
  end

  it "omit requires both date and time to match" do
    vd = VirtualDate.new
    omit = VirtualTime.new
    omit.day = 15
    vd.omit << omit

    vd.omit_on?(Time.local(2023, 3, 15, 10, 0)).should be_true

    omit.hour = 9
    vd.omit_on?(Time.local(2023, 3, 15, 10, 0)).should be_nil
  end

  it "supports ranges" do
    date = Time.parse_local("2017-3-15", "%F")

    vd = VirtualDate.new

    vd.due_on?(date).should be_true

    vt = VirtualTime.new
    vd.due << vt

    vd.due_on?(date).should be_true

    vt.day = 14
    vd.due_on?(date).should be_nil
    vt.day = 15
    vd.due_on?(date).should be_true
    vt.day = 10..14
    vd.due_on?(date).should be_nil
    vt.day = 13..19
    vd.due_on?(date).should be_true
  end

  it "supports procs" do
    date = Time.parse_local("2017-3-15", "%F")

    vd = VirtualDate.new

    vt = VirtualTime.new
    vd.due << vt

    vd.due_on?(date).should be_true

    vt.day = ->(_val : Int32) { true }
    vd.due_on?(date).should be_true
    vt.day = ->(_val : Int32) { false }
    vd.due_on?(date).should be_nil
  end

  it "returns 'on? # => true' on non-omitted due days" do
    date = Time.parse_local("2017-3-15", "%F")

    vd = VirtualDate.new

    vt = VirtualTime.new
    vt.year = 2017
    vt.month = 3
    vt.day = 15

    vd.on?(date).should be_true
    vd.due << vt
    vd.on?(date).should be_true
    vd.omit << vt
    vd.on?(date).should be_false
  end

  it "reports shift amount on omitted due days" do
    date = Time.parse_local("2017-3-15", "%F")

    vd = VirtualDate.new

    vd.on?(date).should be_true

    vt = VirtualTime.new
    vt.year = 2017
    vt.month = 3
    vt.day = 15
    vd.due << vt

    vd.on?(date).should be_true

    vt2 = VirtualTime.new
    vt2.year = 2017
    vt2.month = 3
    vt2.day = 15

    vd3 = VirtualTime.new
    vd3.year = 2017
    vd3.month = 3
    vd3.day = 16

    vd.omit << vt2
    vd.on?(date).should be_false

    vd.shift = -1.day
    vd.on?(date).should eq -1.day
    vd.shift = 4.days
    vd.on?(date).should eq 4.days

    vd.omit << vd3
    vd.shift = 1.day
    vd.on?(date).should eq 2.days
  end

  it "reports false when effective omit larger than allowed boundaries" do
    date = Time.parse_local("2017-3-15", "%F")

    vd = VirtualDate.new

    vd.on?(date).should be_true

    vd3 = VirtualTime.new
    vd3.year = 2017
    vd3.month = 3
    vd3.day = 15..16

    limit_1day = 1.day

    vd.omit << vd3
    vd.shift = 1.day
    vd.on?(date, max_shift: limit_1day).should be_false
  end

  it "can check due/omit date/time separately" do
    date = Time.parse_local("2017-3-15 12:13:14", "%F %X")

    vd = VirtualDate.new

    vd3 = VirtualTime.from_time Time.parse_local("2017-3-15 12:0:0", "%F %X")
    vd.due << vd3
    vd.due_on?(date).should be_nil
    vd.due_on_any_date?(date).should be_true
    vd.due_on_any_time?(date).should be_nil

    vd4 = VirtualTime.from_time(Time.parse_local("2017-3-15", "%F")).clear_time!
    vd.due << vd4
    vd.due_on?(date).should be_true

    vd5 = VirtualTime.from_time(Time.parse_local("12:13:14", "%X")).clear_date!
    vd.due = [vd5]
    vd.due_on?(date).should be_true

    vd6 = VirtualTime.from_time(Time.parse_local("12:13:15", "%X")).clear_date!
    vd.due = [vd6]
    vd.due_on?(date).should be_nil

    date = Time.parse_local("2017-3-15 1:2:3", "%F %X")
    vd7 = VirtualTime.from_time(Time.parse_local("2017-3-18", "%F")).clear_time!
    vd.due_on?(date).should be_nil
    vd.due_on_any_date?(date).should be_true
    vd.due = [vd7]
    vd.due_on_any_date?(date).should be_nil
    vd.due = [vd6]
    vd.due_on_any_time?(date).should be_nil
    vd.due = [vd7]
    vd.due_on_any_time?(date).should be_true
  end

  it "can reschedule with higher granularity than days" do
    date = Time.parse_local("2017-3-15 12:13:14", "%F %X")

    vd = VirtualDate.new

    vd.due_on?(date).should be_true

    vd3 = VirtualTime.new
    vd3.hour = 12
    vd.omit << vd3

    vd.on?(date).should be_false

    vd.shift = -3.minutes
    vd.on?(date).should eq -15.minutes
  end

  it "can match virtual dates" do
    item = VirtualDate.new

    vt = VirtualTime.new year: 2017, month: 3, day: 15
    item.due << vt

    date = vt.dup
    item.due_on_any_date?(date).should be_true
    date.year = nil
    date.month = nil
    date.day = nil
    item.due_on_any_date?(date).should be_true
    date.month = 3
    item.due_on_any_date?(date).should be_true
    date.month = 4
    item.due_on_any_date?(date).should be_nil

    date = VirtualTime.new
    date.month = nil
    date.day = 15
    item.due_on_any_date?(date).should be_true
    date.day = 1
    item.due_on_any_date?(date).should be_nil
    date.day = 13..18
    item.due_on_any_date?(date).should be_true
    vt.day = 10..20
    item.due_on_any_date?(date).should be_true
    vt.day = 15
    date.day = 15
    item.due_on_any_date?(date).should be_true
    date.day = nil
    item.due_on_any_date?(date).should be_true
    date.month = 2
    item.due_on_any_date?(date).should be_nil
    date.month = 3
    item.due_on_any_date?(date).should be_true
    date.day = 13..18
    item.due_on_any_date?(date).should be_true

    vt2 = VirtualTime.new
    vt2.month = 3
    item.due = [vt2]
    date = VirtualTime.new
    date.day = 13..18
    item.due_on_any_date?(date).should be_true
    date.month = 2
    item.due_on_any_date?(date).should be_nil
    date.month = 2..4
    item.due_on_any_date?(date).should be_true
    date.month = nil
    vt2.month = nil
    vt2.day = 15..18
    date.day = 15..18
    item.due_on_any_date?(date).should be_true
    date.day = 15..19
    item.due_on_any_date?(date).should be_true
  end

  it "can shift on simple rules" do
    item = VirtualDate.new
    due = VirtualTime.new year: 2017, month: 3, day: 15
    date = VirtualTime.new year: 2017, month: 3, day: 15
    omit = VirtualTime.new year: 2017, month: 3, day: 15
    omit2 = VirtualTime.new year: 2017, month: 3, day: 14
    shift = -1.day

    item.due = [due]
    item.on?(date).should be_true
    item.omit = [omit]
    item.on?(date).should be_false
    item.shift = shift

    item.on?(date).should eq -1.day
    item.omit << omit2
    item.on?(date).should eq -2.days

    item = VirtualDate.new
    due = VirtualTime.new year: 2017, month: 3, day: 15, hour: 1, minute: 34, second: 0
    date = VirtualTime.new year: 2017, month: 3, day: 15, hour: 1, minute: 34, second: 0
    item.shift = 3.minutes
    omit = VirtualTime.new
    omit.hour = 1
    item.due = [due]
    item.omit = [omit]
    item.on?(date).should eq 27.minutes
  end

  it "can shift on complex rules" do
    item = VirtualDate.new
    due = VirtualTime.new
    due.day = 4
    date = VirtualTime.new
    date.day = 4
    item.shift = Time::Span.new days: 7, hours: 10, minutes: 20, seconds: 30
    omit = VirtualTime.new
    omit.day = 4
    item.due = [due]
    item.omit = [omit]
    item.on?(date).should eq Time::Span.new days: 7, hours: 10, minutes: 20, seconds: 30

    item = VirtualDate.new
    due = VirtualTime.new
    due.day = 4
    date = VirtualTime.new
    date.day = 4
    item.shift = Time::Span.new days: 7, hours: 10, minutes: 20, seconds: 30
    omit = VirtualTime.new
    omit.day = 3..14
    item.due = [due]
    item.omit = [omit]
    item.on?(date).should eq Time::Span.new days: 14, hours: 20, minutes: 41, seconds: 0

    item = VirtualDate.new
    tl = Time.local.at_beginning_of_month
    item.due = [VirtualTime.new day: tl.day]
    item.omit = [VirtualTime.new(day: tl.day..((tl + 9.days).day))]
    item.shift = Time::Span.new days: 7, hours: 10, minutes: 20, seconds: 30
    date = VirtualTime.from_time tl.at_beginning_of_day
    item.on?(date).should eq Time::Span.new days: 14, hours: 20, minutes: 41, seconds: 0
  end

  it "can check due_on_any_dates with ranges" do
    item = VirtualDate.new
    due = VirtualTime.new
    due.day = 4..12
    # item.shift= VirtualTime::Span.new 7,10,20,30
    omit = VirtualTime.new
    omit.day = 12
    item.due = [due]
    item.omit = [omit]

    date = VirtualTime.new
    date.day = 8..11
    # puts date.inspect

    item.on?(date).should be_true

    date.day = 8..14

    dates = date.expand
    r = dates.map { |d| item.on? d }
    r.should eq [true, true, true, true, false, nil, nil]

    # And another form of saying it:
    dates.map { |d| item.on? d }.any? { |x| x }.should be_true
  end

  it "can shift til !due_on?( @omit) && due_on?( @due)" do
    vd = VirtualDate.new
    vd.shift = 1.day

    due = VirtualTime.new
    due.day = 3..15
    vd.due = [due]

    omit = VirtualTime.new
    omit.day = 2..14
    vd.omit = [omit]

    date = Time.local.at_beginning_of_month + 2.days

    vd.on?(date).should eq 12.days
  end

  it "respects max_shifts" do
    vd = VirtualDate.new

    due = VirtualTime.new
    due.second = 10
    vd.due = [due]

    omit = VirtualTime.new
    omit.second = 10..12
    vd.omit = [omit]

    date = Time.unix 10
    vd.on?(date, max_shifts: 30).should eq false

    vd.shift = 1.second
    vd.on?(date, max_shifts: 30).should eq 3.seconds

    vd.shift = 500.milliseconds
    vd.on?(date, max_shifts: 3).should eq false
  end

  it "can match against Time objects" do
    vd = VirtualDate.new
    due = VirtualTime.new
    due.month = 5
    due.day = 1..15
    vd.due << due

    vd.on?(Time.local(2018, 5, 5)).should be_true
    vd.on?(Time.local(2018, 5, 15)).should be_true
    vd.on?(Time.local(2018, 5, 16)).should be_nil
  end

  it "works correctly with wrap (negative values counting from the end)" do
    vd = VirtualDate.new
    due = VirtualTime.new
    due.month = 5
    due.day = -2
    vd.due << due
    vd.on?(Time.local(2018, 5, 30)).should be_true
    vd.on?(Time.local(2018, 5, 31)).should be_nil
  end

  it "uses negative numbers to count from end of month" do
    i = VirtualDate.new
    due = VirtualTime.new
    due.year = 2017
    due.month = 2
    due.day = -1
    i.due << due
    date = Time.local year: 2017, month: 2, day: 28
    i.due_on?(date).should eq true
  end
end

require "spec"
require "../src/virtualdate"

describe "VirtualDate – advanced scheduling" do
  describe "#resolve and #effective_on?" do
    it "treats shifted times as effectively on" do
      loc = Time::Location.load("Europe/Berlin")
      date = Time.local(2023, 3, 15, 10, 0, 0, location: loc)

      vd = VirtualDate.new

      due = VirtualTime.from_time(date)
      omit = VirtualTime.from_time(date)

      vd.due << due
      vd.omit << omit
      vd.shift = 2.hours

      # Legacy behavior: on? reports shift
      vd.on?(date).should eq 2.hours

      shifted = date + 2.hours

      # Legacy on? does not consider shifted time "on"
      vd.on?(shifted).should be_nil

      # New semantics
      vd.resolve(date).should eq shifted
      vd.effective_on?(shifted).should be_true
      vd.effective_on?(date).should be_false
    end

    it "returns false when shifted time exceeds max_shift" do
      date = Time.local(2023, 5, 10, 9, 0, 0)

      vd = VirtualDate.new
      vd.due << VirtualTime.from_time(date)
      vd.omit << VirtualTime.from_time(date)
      vd.shift = 1.hour
      vd.max_shift = 30.minutes

      vd.resolve(date).should be_false
      vd.effective_on?(date + 1.hour).should be_false
    end
  end

  describe "Scheduler basic placement" do
    it "schedules a single task with duration" do
      scheduler = VirtualDate::Scheduler.new

      task = VirtualDate.new
      task.duration = 1.hour
      task.due << VirtualTime.new(hour: 10)

      scheduler.tasks << task

      from = Time.local(2023, 5, 10, 0, 0, 0)
      to = Time.local(2023, 5, 10, 23, 59, 59)

      instances = scheduler.build(from, to)

      instances.size.should eq 1
      instances[0].start.hour.should eq 10
      instances[0].finish.should eq instances[0].start + 1.hour
    end
  end

  describe "Scheduler conflict resolution via duration" do
    it "reschedules second task after first when overlapping is not allowed" do
      scheduler = VirtualDate::Scheduler.new

      t1 = VirtualDate.new
      t1.duration = 2.hours
      t1.priority = 10
      t1.flags << "work"
      t1.parallel = 1
      t1.due << VirtualTime.new(hour: 9)

      t2 = VirtualDate.new
      t2.duration = 1.hour
      t2.flags << "work"
      t2.parallel = 1
      t2.shift = 30.minutes
      t2.due << VirtualTime.new(hour: 9)

      scheduler.tasks = [t1, t2]

      from = Time.local(2023, 5, 10)
      to = Time.local(2023, 5, 11)

      instances = scheduler.build(from, to)

      instances.size.should eq 2

      first = instances.find(&.task.==(t1)).not_nil!
      second = instances.find(&.task.==(t2)).not_nil!

      first.start.hour.should eq 9
      first.finish.should eq first.start + 2.hours

      second.start.should be >= first.finish
    end
  end

  describe "Scheduler parallelism rules" do
    it "allows parallel tasks up to parallel limit per flag" do
      scheduler = VirtualDate::Scheduler.new

      a = VirtualDate.new
      a.duration = 1.hour
      a.flags << "meeting"
      a.parallel = 2
      a.due << VirtualTime.new(hour: 10)

      b = VirtualDate.new
      b.duration = 1.hour
      b.flags << "meeting"
      b.parallel = 2
      b.due << VirtualTime.new(hour: 10)

      c = VirtualDate.new
      c.duration = 1.hour
      c.flags << "meeting"
      c.parallel = 2
      c.shift = 30.minutes
      c.due << VirtualTime.new(hour: 10)

      scheduler.tasks = [a, b, c]

      from = Time.local(2023, 5, 10)
      to = Time.local(2023, 5, 11)

      instances = scheduler.build(from, to)

      instances.size.should eq 3

      starts = instances.map(&.start)
      starts.count { |t| t.hour == 10 && t.minute == 0 }.should eq 2
    end
  end

  describe "Scheduler respects fixed tasks" do
    it "does not move fixed tasks even if conflicts occur" do
      scheduler = VirtualDate::Scheduler.new

      fixed = VirtualDate.new
      fixed.duration = 2.hours
      fixed.flags << "focus"
      fixed.parallel = 1
      fixed.fixed = true
      fixed.due << VirtualTime.new(hour: 9)

      movable = VirtualDate.new
      movable.duration = 1.hour
      movable.flags << "focus"
      movable.parallel = 1
      movable.shift = 1.hour
      movable.due << VirtualTime.new(hour: 9)

      scheduler.tasks = [fixed, movable]

      from = Time.local(2023, 5, 10)
      to = Time.local(2023, 5, 11)

      instances = scheduler.build(from, to)

      instances.size.should eq 2

      fixed_i = instances.find(&.task.==(fixed)).not_nil!
      movable_i = instances.find(&.task.==(movable)).not_nil!

      fixed_i.start.hour.should eq 9
      movable_i.start.should be >= fixed_i.finish
    end
  end

  describe "Scheduler dependencies" do
    it "schedules dependent task after its dependency" do
      scheduler = VirtualDate::Scheduler.new

      a = VirtualDate.new
      a.duration = 1.hour
      a.due << VirtualTime.new(hour: 9)

      b = VirtualDate.new
      b.duration = 1.hour
      b.depends_on << a
      b.due << VirtualTime.new(hour: 9)

      scheduler.tasks = [a, b]

      from = Time.local(2023, 5, 10)
      to = Time.local(2023, 5, 11)

      instances = scheduler.build(from, to)

      instances.size.should eq 2

      ia = instances.find(&.task.==(a)).not_nil!
      ib = instances.find(&.task.==(b)).not_nil!

      ib.start.should be >= ia.finish
    end
  end

  describe "Scheduler + effective_on?" do
    it "reports on_in_schedule? correctly" do
      scheduler = VirtualDate::Scheduler.new

      task = VirtualDate.new
      task.duration = 1.hour
      task.due << VirtualTime.new(hour: 10)

      scheduler.tasks << task

      from = Time.local(2023, 5, 10)
      to = Time.local(2023, 5, 11)

      instances = scheduler.build(from, to)

      scheduler.on_in_schedule?(instances, task, Time.local(2023, 5, 10, 10, 30)).should be_true
      scheduler.on_in_schedule?(instances, task, Time.local(2023, 5, 10, 11, 30)).should be_false
    end
  end

  it "staggered scheduler creates multiple staggered instances" do
    scheduler = VirtualDate::Scheduler.new

    task = VirtualDate.new
    task.due << VirtualTime.from_time(Time.local(2023, 5, 10, 10, 0))
    task.duration = 1.hour
    task.parallel = 3
    task.stagger = 30.minutes

    scheduler.tasks << task

    instances = scheduler.build(
      Time.local(2023, 5, 10, 0, 0),
      Time.local(2023, 5, 10, 23, 59)
    )

    starts = instances.map(&.start)

    starts.should contain(Time.local(2023, 5, 10, 10, 0))
    starts.should contain(Time.local(2023, 5, 10, 10, 30))
    starts.should contain(Time.local(2023, 5, 10, 11, 0))
    instances.size.should eq 3
  end

  it "ignores stagger when parallel is 1" do
    scheduler = VirtualDate::Scheduler.new

    task = VirtualDate.new
    task.due << VirtualTime.from_time(Time.local(2023, 5, 10, 9, 0))
    task.duration = 1.hour
    task.parallel = 1
    task.stagger = 15.minutes

    scheduler.tasks << task

    instances = scheduler.build(
      Time.local(2023, 5, 10),
      Time.local(2023, 5, 11)
    )

    instances.size.should eq 1
    instances.first.start.should eq Time.local(2023, 5, 10, 9, 0)
  end

  it "does not create staggered instances past the horizon" do
    scheduler = VirtualDate::Scheduler.new

    task = VirtualDate.new
    task.due << VirtualTime.from_time(Time.local(2023, 5, 10, 10, 0))
    task.parallel = 4
    task.stagger = 30.minutes

    scheduler.tasks << task

    instances = scheduler.build(
      Time.local(2023, 5, 10, 9, 0),
      Time.local(2023, 5, 10, 10, 45)
    )

    instances.map(&.start).should eq [
      Time.local(2023, 5, 10, 10, 0),
      Time.local(2023, 5, 10, 10, 30),
    ]
  end

  it "applies omit rules independently to staggered instances" do
    scheduler = VirtualDate::Scheduler.new

    task = VirtualDate.new
    task.due << VirtualTime.from_time(Time.local(2023, 5, 10, 10, 0))
    task.parallel = 3
    task.stagger = 30.minutes

    omit = VirtualTime.new
    omit.hour = 10
    omit.minute = 30
    task.omit << omit

    scheduler.tasks << task

    instances = scheduler.build(
      Time.local(2023, 5, 10),
      Time.local(2023, 5, 11)
    )

    instances.map(&.start).should eq [
      Time.local(2023, 5, 10, 10, 0),
      Time.local(2023, 5, 10, 11, 0),
    ]
  end

  it "does not reschedule fixed staggered tasks" do
    scheduler = VirtualDate::Scheduler.new

    task = VirtualDate.new
    task.due << VirtualTime.from_time(Time.local(2023, 5, 10, 10, 0))
    task.parallel = 2
    task.stagger = 30.minutes
    task.fixed = true

    scheduler.tasks << task

    instances = scheduler.build(
      Time.local(2023, 5, 10),
      Time.local(2023, 5, 11)
    )

    instances.size.should eq 2
    instances.map(&.start).should eq [
      Time.local(2023, 5, 10, 10, 0),
      Time.local(2023, 5, 10, 10, 30),
    ]
  end

  it "raises when stagger is zero or negative" do
    scheduler = VirtualDate::Scheduler.new

    task = VirtualDate.new
    task.due << VirtualTime.from_time(Time.local(2023, 5, 10, 10, 0))
    task.parallel = 2
    task.stagger = 0.seconds

    scheduler.tasks << task

    expect_raises(ArgumentError) do
      scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))
    end
  end

  describe "Scheduler priority handling" do
    it "prefers higher-priority task when both conflict and are movable" do
      scheduler = VirtualDate::Scheduler.new

      low = VirtualDate.new
      low.priority = 1
      low.duration = 2.hours
      low.flags << "work"
      low.parallel = 1
      low.shift = 30.minutes
      low.due << VirtualTime.new(hour: 9)

      high = VirtualDate.new
      high.priority = 10
      high.duration = 1.hour
      high.flags << "work"
      high.parallel = 1
      high.due << VirtualTime.new(hour: 9)

      scheduler.tasks = [low, high]

      instances = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      hi = instances.find(&.task.==(high)).not_nil!
      lo = instances.find(&.task.==(low)).not_nil!

      hi.start.hour.should eq 9
      lo.start.should be >= hi.finish
    end

    it "does not override fixed with priority" do
      scheduler = VirtualDate::Scheduler.new

      fixed = VirtualDate.new
      fixed.fixed = true
      fixed.priority = 1
      fixed.duration = 2.hours
      fixed.flags << "focus"
      fixed.parallel = 1
      fixed.due << VirtualTime.new(hour: 9)

      movable = VirtualDate.new
      movable.priority = 100
      movable.duration = 1.hour
      movable.flags << "focus"
      movable.parallel = 1
      movable.shift = 30.minutes
      movable.due << VirtualTime.new(hour: 9)

      scheduler.tasks = [movable, fixed]

      instances = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      fi = instances.find(&.task.==(fixed)).not_nil!
      mi = instances.find(&.task.==(movable)).not_nil!

      fi.start.hour.should eq 9
      mi.start.should be >= fi.finish
    end
  end

  describe "Scheduler dependencies with conflicts" do
    it "respects dependency even when it causes conflicts" do
      scheduler = VirtualDate::Scheduler.new

      a = VirtualDate.new
      a.duration = 2.hours
      a.flags << "work"
      a.parallel = 1
      a.due << VirtualTime.new(hour: 9)

      blocker = VirtualDate.new
      blocker.duration = 1.hour
      blocker.flags << "work"
      blocker.parallel = 1
      blocker.fixed = true
      blocker.due << VirtualTime.new(hour: 11)

      b = VirtualDate.new
      b.duration = 1.hour
      b.depends_on << a
      b.flags << "work"
      b.parallel = 1
      b.shift = 30.minutes
      b.due << VirtualTime.new(hour: 9)

      scheduler.tasks = [a, blocker, b]

      instances = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11, 23, 59, 59)
      )

      ia = instances.find(&.task.==(a)).not_nil!
      ib = instances.find(&.task.==(b)).not_nil!
      blocker_i = instances.find(&.task.==(blocker)).not_nil!
      ib.start.should be >= ia.finish
      ib.start.should be >= blocker_i.finish
    end
  end

  describe "Scheduler parallelism across different flags" do
    it "does not restrict tasks with different flags" do
      scheduler = VirtualDate::Scheduler.new

      a = VirtualDate.new
      a.duration = 2.hours
      a.flags << "meeting"
      a.parallel = 1
      a.due << VirtualTime.new(hour: 10)

      b = VirtualDate.new
      b.duration = 2.hours
      b.flags << "focus"
      b.parallel = 1
      b.due << VirtualTime.new(hour: 10)

      scheduler.tasks = [a, b]

      instances = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      instances.size.should eq 2
      instances.all? { |i| i.start.hour == 10 }.should be_true
    end
  end

  describe "Scheduler effective_on? invariant" do
    it "ensures all scheduled instances are effectively on" do
      scheduler = VirtualDate::Scheduler.new

      task = VirtualDate.new
      task.duration = 1.hour
      task.due << VirtualTime.new(hour: 10)
      task.omit << VirtualTime.new(hour: 10)
      task.shift = 1.hour

      scheduler.tasks << task

      instances = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      instances.each do |i|
        task.effective_on?(i.start).should be_true
      end
    end
  end

  describe "Scheduler explanations" do
    it "attaches explanations to task instances" do
      scheduler = VirtualDate::Scheduler.new

      task = VirtualDate.new
      task.duration = 1.hour
      task.shift = 30.minutes
      task.due << VirtualTime.new(hour: 10)
      task.omit << VirtualTime.new(hour: 10)

      scheduler.tasks << task

      instances = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      inst = instances.first
      inst.explanation.should_not be_nil
      inst.explanation.lines.should_not be_empty
    end
  end

  describe "Scheduler determinism" do
    it "produces identical results on repeated runs" do
      scheduler = VirtualDate::Scheduler.new

      task = VirtualDate.new
      task.duration = 1.hour
      task.due << VirtualTime.new(hour: 10)

      scheduler.tasks << task

      from = Time.local(2023, 5, 10)
      to = Time.local(2023, 5, 11)

      a = scheduler.build(from, to)
      b = scheduler.build(from, to)

      a.map(&.start).should eq b.map(&.start)
    end
  end

  describe "Scheduler priority handling" do
    it "prefers higher-priority task when both conflict and are movable" do
      scheduler = VirtualDate::Scheduler.new

      low = VirtualDate.new("low")
      low.duration = 2.hours
      low.priority = 1
      low.flags << "work"
      low.parallel = 1
      low.due << VirtualTime.new(hour: 9)

      high = VirtualDate.new("high")
      high.duration = 1.hour
      high.priority = 10
      high.flags << "work"
      high.parallel = 1
      high.due << VirtualTime.new(hour: 9)

      scheduler.tasks = [low, high]

      instances = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      hi = instances.find(&.task.id.==("high")).not_nil!
      lo = instances.find(&.task.id.==("low")).not_nil!

      hi.start.hour.should eq 9
      lo.start.should be >= hi.finish
    end
  end

  it "does not allow priority to override fixed tasks" do
    scheduler = VirtualDate::Scheduler.new

    fixed = VirtualDate.new("fixed")
    fixed.duration = 2.hours
    fixed.priority = 1
    fixed.fixed = true
    fixed.flags << "focus"
    fixed.parallel = 1
    fixed.due << VirtualTime.new(hour: 9)

    aggressive = VirtualDate.new("aggressive")
    aggressive.duration = 1.hour
    aggressive.priority = 100
    aggressive.flags << "focus"
    aggressive.parallel = 1
    aggressive.shift = 30.minutes
    aggressive.due << VirtualTime.new(hour: 9)

    scheduler.tasks = [fixed, aggressive]

    instances = scheduler.build(
      Time.local(2023, 5, 10),
      Time.local(2023, 5, 11)
    )

    instances.size.should eq 2

    f = instances.find(&.task.id.==("fixed")).not_nil!
    a = instances.find(&.task.id.==("aggressive")).not_nil!

    f.start.hour.should eq 9
    a.start.should be >= f.finish
  end

  describe "Scheduler deadline enforcement" do
    it "rejects scheduling that would finish after deadline" do
      scheduler = VirtualDate::Scheduler.new

      task = VirtualDate.new("deadline-task")
      task.duration = 2.hours
      task.deadline = Time.local(2023, 5, 10, 10, 0)
      task.due << VirtualTime.new(hour: 9)

      scheduler.tasks << task

      instances = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      instances.should be_empty
    end

    it "allows scheduling that finishes exactly at deadline" do
      scheduler = VirtualDate::Scheduler.new

      task = VirtualDate.new("exact")
      task.duration = 1.hour
      task.deadline = Time.local(2023, 5, 10, 10, 0)
      task.due << VirtualTime.new(hour: 9)

      scheduler.tasks << task

      instances = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      instances.size.should eq 1
      instances.first.finish.should eq task.deadline
    end
  end

  it "respects dependency order even if dependent has higher priority" do
    scheduler = VirtualDate::Scheduler.new

    a = VirtualDate.new("a")
    a.duration = 2.hours
    a.priority = 1
    a.due << VirtualTime.new(hour: 9)

    b = VirtualDate.new("b")
    b.duration = 1.hour
    b.priority = 100
    b.depends_on << a
    b.due << VirtualTime.new(hour: 9)

    scheduler.tasks = [b, a]

    instances = scheduler.build(
      Time.local(2023, 5, 10),
      Time.local(2023, 5, 10, 23, 59, 59)
    )

    ia = instances.find(&.task.id.==("a")).not_nil!
    ib = instances.find(&.task.id.==("b")).not_nil!

    ib.start.should be >= ia.finish
  end

  describe "Scheduler explanations" do
    it "attaches explanations to task instances" do
      scheduler = VirtualDate::Scheduler.new

      task = VirtualDate.new("explain")
      task.duration = 1.hour
      task.shift = 30.minutes
      task.due << VirtualTime.new(hour: 9)

      blocker = VirtualDate.new("blocker")
      blocker.duration = 2.hours
      blocker.fixed = true
      blocker.due << VirtualTime.new(hour: 9)

      scheduler.tasks = [blocker, task]

      instances = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      inst = instances.find(&.task.id.==("explain")).not_nil!
      inst.explanation.lines.should_not be_empty
    end
  end

  describe "ICS export" do
    it "exports scheduled tasks as valid iCal events" do
      scheduler = VirtualDate::Scheduler.new

      task = VirtualDate.new("ics-task")
      task.duration = 1.hour
      task.due << VirtualTime.new(hour: 10)

      scheduler.tasks << task

      instances = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      ics = VirtualDate::ICS.export(instances)

      ics.should contain("BEGIN:VCALENDAR")
      ics.should contain("BEGIN:VEVENT")
      ics.should contain("SUMMARY:ics-task")
      ics.should contain("END:VEVENT")
      ics.should contain("END:VCALENDAR")
    end
  end
end
