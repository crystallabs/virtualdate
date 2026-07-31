require "spec"
require "../src/virtualdate"

# Reverses RFC 5545 line folding: a CRLF followed by a single space is a
# continuation of the preceding content line.
def unfold_ics(ics : String) : Array(String)
  ics.gsub("\r\n ", "").split("\r\n", remove_empty: true)
end

describe VirtualDate do
  it "honors begin/end dates" do
    vd = VirtualDate.new
    vd.begin = Time.parse_local("2017-1-1", "%F")
    vd.end = Time.parse_local("2017-2-28", "%F")
    date = Time.parse_local("2017-3-15", "%F")
    vd.strict_on?(date).should be_nil
    date = Time.parse_local("2017-2-1", "%F")
    vd.due_on?(date).should be_true

    vd = VirtualDate.new
    vd.begin = Time.parse_local("2017-6-1", "%F")
    vd.end = Time.parse_local("2017-9-1", "%F")
    date = Time.parse_local("2017-3-15", "%F")
    vd.strict_on?(date).should be_nil

    vd = VirtualDate.new
    vd.begin = Time.parse_local("2017-1-1", "%F")
    vd.end = Time.parse_local("2017-9-1", "%F")
    date = Time.parse_local("2017-3-15 10:10:10", "%F %X")
    vd.strict_on?(date).should be_true
  end

  it "honors begin/end as VirtualTime" do
    vd = VirtualDate.new
    vd.begin = VirtualTime.new(day: 10..20)
    vd.strict_on?(Time.local(2023, 5, 9)).should be_nil
    vd.strict_on?(Time.local(2023, 5, 14)).should be_true
    vd.strict_on?(Time.local(2023, 5, 21)).should be_nil
  end

  it "compares an absolute begin/end against the instant, however it was asked for" do
    vd = VirtualDate.new
    vd.begin = Time.local(2023, 5, 10, 9, 0, 0)
    vd.end = Time.local(2023, 8, 1)
    vd.due << VirtualTime.new(hour: 10)

    moment = Time.local(2023, 6, 1, 10, 0, 0)
    asked = VirtualTime.new(year: 2023, month: 6, day: 1, hour: 10, minute: 0, second: 0, nanosecond: 0)

    # Regression: an absolute bound was matched *against* a VirtualTime query
    # rather than against the moment it stands for, so the very same instant
    # came back "not applicable" as a pattern and "on" as a Time
    vd.strict_on?(moment).should be_true
    vd.strict_on?(asked, hint: moment).should be_true

    outside = VirtualTime.new(year: 2023, month: 1, day: 1, hour: 10, minute: 0, second: 0, nanosecond: 0)
    vd.strict_on?(outside, hint: Time.local(2023, 1, 1)).should be_nil
  end

  it "on override takes precedence over begin/end" do
    vd = VirtualDate.new
    vd.begin = Time.local(2023, 1, 1)
    vd.end = Time.local(2023, 1, 2)

    vd.on = true
    vd.strict_on?(Time.local(2024, 1, 1)).should be_true

    vd.on = false
    vd.strict_on?(Time.local(2023, 1, 1)).should be_false
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
    vd.strict_on?(date).should be_false
  end

  it "shift = true ignores omit rules" do
    vd = VirtualDate.new
    due = VirtualTime.new(day: 15)
    omit = VirtualTime.new(day: 15)

    vd.due << due
    vd.omit << omit
    vd.shift = true

    vd.strict_on?(Time.local(2023, 3, 15)).should be_true
  end

  it "shift = nil treats omitted date as not applicable" do
    vd = VirtualDate.new
    due = VirtualTime.new(day: 15)
    omit = VirtualTime.new(day: 15)

    vd.due << due
    vd.omit << omit
    vd.shift = nil

    vd.strict_on?(Time.local(2023, 3, 15)).should be_nil
  end

  it "handles DST transitions when shifting" do
    loc = Time::Location.load("Europe/Berlin")
    date = Time.local(2023, 3, 26, 1, 30, location: loc)

    vd = VirtualDate.new
    vd.shift = 1.hour

    omit = VirtualTime.from_time(date)
    vd.omit << omit

    vd.strict_on?(date).should eq 1.hour
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

  it "requires a single rule to match, not a date from one and a time from another" do
    # "Omit Christmas Day, and omit the lunch hour."
    #
    # Regression: `omit_on?` was `omit_on_dates? && omit_on_times?` over the
    # whole list, so the first rule (which constrains no time) satisfied the
    # time half and the second (which constrains no date) the date half --
    # every instant of the year came out omitted.
    vd = VirtualDate.new
    vd.due << VirtualTime.new(hour: 9, minute: 0, second: 0, nanosecond: 0)
    vd.omit << VirtualTime.new(month: 12, day: 25)
    vd.omit << VirtualTime.new(hour: 12)

    vd.omit_on?(Time.local(2023, 12, 25, 9, 0)).should be_true
    vd.omit_on?(Time.local(2023, 6, 1, 12, 0)).should be_true
    vd.omit_on?(Time.local(2023, 6, 1, 9, 0)).should be_nil
    vd.strict_on?(Time.local(2023, 6, 1, 9, 0)).should be_true

    # Likewise for `due`: a time no single rule covers is not due
    vd = VirtualDate.new
    vd.due << VirtualTime.new(day: 15, hour: 9)
    vd.due << VirtualTime.new(day: 20, hour: 14)

    vd.due_on?(Time.local(2023, 3, 15, 14, 0)).should be_nil
    vd.due_on?(Time.local(2023, 3, 15, 9, 0)).should be_true
    vd.due_on?(Time.local(2023, 3, 20, 14, 0)).should be_true

    # The date-only and time-only halves stay available on their own
    vd.due_on_any_date?(Time.local(2023, 3, 15, 14, 0)).should be_true
    vd.due_on_any_time?(Time.local(2023, 3, 15, 14, 0)).should be_true
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

    vd.strict_on?(date).should be_true
    vd.due << vt
    vd.strict_on?(date).should be_true
    vd.omit << vt
    vd.strict_on?(date).should be_false
  end

  it "reports shift amount on omitted due days" do
    date = Time.parse_local("2017-3-15", "%F")

    vd = VirtualDate.new

    vd.strict_on?(date).should be_true

    vt = VirtualTime.new
    vt.year = 2017
    vt.month = 3
    vt.day = 15
    vd.due << vt

    vd.strict_on?(date).should be_true

    vt2 = VirtualTime.new
    vt2.year = 2017
    vt2.month = 3
    vt2.day = 15

    vd3 = VirtualTime.new
    vd3.year = 2017
    vd3.month = 3
    vd3.day = 16

    vd.omit << vt2
    vd.strict_on?(date).should be_false

    vd.shift = -1.day
    vd.strict_on?(date).should eq -1.day
    vd.shift = 4.days
    vd.strict_on?(date).should eq 4.days

    vd.omit << vd3
    vd.shift = 1.day
    vd.strict_on?(date).should eq 2.days
  end

  it "reports false when effective omit larger than allowed boundaries" do
    date = Time.parse_local("2017-3-15", "%F")

    vd = VirtualDate.new

    vd.strict_on?(date).should be_true

    vd3 = VirtualTime.new
    vd3.year = 2017
    vd3.month = 3
    vd3.day = 15..16

    limit_1day = 1.day

    vd.omit << vd3
    vd.shift = 1.day
    vd.strict_on?(date, max_shift: limit_1day).should be_false
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

    vd.strict_on?(date).should be_false

    vd.shift = -3.minutes
    vd.strict_on?(date).should eq -15.minutes
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
    item.strict_on?(date).should be_true
    item.omit = [omit]
    item.strict_on?(date).should be_false
    item.shift = shift

    item.strict_on?(date).should eq -1.day
    item.omit << omit2
    item.strict_on?(date).should eq -2.days

    item = VirtualDate.new
    due = VirtualTime.new year: 2017, month: 3, day: 15, hour: 1, minute: 34, second: 0
    date = VirtualTime.new year: 2017, month: 3, day: 15, hour: 1, minute: 34, second: 0
    item.shift = 3.minutes
    omit = VirtualTime.new
    omit.hour = 1
    item.due = [due]
    item.omit = [omit]
    item.strict_on?(date).should eq 27.minutes
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
    item.strict_on?(date).should eq Time::Span.new days: 7, hours: 10, minutes: 20, seconds: 30

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
    item.strict_on?(date).should eq Time::Span.new days: 14, hours: 20, minutes: 41, seconds: 0

    item = VirtualDate.new
    tl = Time.local.at_beginning_of_month
    item.due = [VirtualTime.new day: tl.day]
    item.omit = [VirtualTime.new(day: tl.day..((tl + 9.days).day))]
    item.shift = Time::Span.new days: 7, hours: 10, minutes: 20, seconds: 30
    date = VirtualTime.from_time tl.at_beginning_of_day
    item.strict_on?(date).should eq Time::Span.new days: 14, hours: 20, minutes: 41, seconds: 0
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

    item.strict_on?(date).should be_true

    date.day = 8..14

    dates = date.expand
    r = dates.map { |expanded| item.strict_on? expanded }
    r.should eq [true, true, true, true, false, nil, nil]

    # And another form of saying it:
    dates.map { |expanded| item.strict_on? expanded }.any? { |x| x }.should be_true
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

    vd.strict_on?(date).should eq 12.days
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
    vd.strict_on?(date, max_shifts: 30).should be_false

    vd.shift = 1.second
    vd.strict_on?(date, max_shifts: 30).should eq 3.seconds

    vd.shift = 500.milliseconds
    vd.strict_on?(date, max_shifts: 3).should be_false
  end

  it "can match against Time objects" do
    vd = VirtualDate.new
    due = VirtualTime.new
    due.month = 5
    due.day = 1..15
    vd.due << due

    vd.strict_on?(Time.local(2018, 5, 5)).should be_true
    vd.strict_on?(Time.local(2018, 5, 15)).should be_true
    vd.strict_on?(Time.local(2018, 5, 16)).should be_nil
  end

  it "works correctly with wrap (negative values counting from the end)" do
    vd = VirtualDate.new
    due = VirtualTime.new
    due.month = 5
    due.day = -2
    vd.due << due
    vd.strict_on?(Time.local(2018, 5, 30)).should be_true
    vd.strict_on?(Time.local(2018, 5, 31)).should be_nil
  end

  it "uses negative numbers to count from end of month" do
    i = VirtualDate.new
    due = VirtualTime.new
    due.year = 2017
    due.month = 2
    due.day = -1
    i.due << due
    date = Time.local year: 2017, month: 2, day: 28
    i.due_on?(date).should be_true
  end
end

describe "VirtualDate – advanced scheduling" do
  describe "#resolve and #on?" do
    it "treats shifted times as effectively on" do
      loc = Time::Location.load("Europe/Berlin")
      date = Time.local(2023, 3, 15, 10, 0, 0, location: loc)

      vd = VirtualDate.new

      due = VirtualTime.from_time(date)
      omit = VirtualTime.from_time(date)

      vd.due << due
      vd.omit << omit
      vd.shift = 2.hours

      vd.strict_on?(date).should eq 2.hours

      shifted = date + 2.hours

      vd.strict_on?(shifted).should be_nil

      # New semantics
      vd.resolve(date).should eq shifted
      vd.on?(shifted).should be_true
      vd.on?(date).should be_false
    end

    it "returns false when shifted time exceeds max_shift" do
      date = Time.local(2023, 5, 10, 9, 0, 0)

      vd = VirtualDate.new
      vd.due << VirtualTime.from_time(date)
      vd.omit << VirtualTime.from_time(date)
      vd.shift = 1.hour
      vd.max_shift = 30.minutes

      vd.resolve(date).should be_false
      vd.on?(date + 1.hour).should be_false
    end
  end

  describe "Scheduler basic scheduling" do
    it "schedules a single vdate with duration" do
      scheduler = VirtualDate::Scheduler.new

      vdate = VirtualDate.new
      vdate.duration = 1.hour
      vdate.due << VirtualTime.new(hour: 10)

      scheduler.vdates << vdate

      from = Time.local(2023, 5, 10, 0, 0, 0)
      to = Time.local(2023, 5, 10, 23, 59, 59)

      scheduled_vdates = scheduler.build(from, to)

      scheduled_vdates.size.should eq 1
      scheduled_vdates[0].start.hour.should eq 10
      scheduled_vdates[0].finish.should eq scheduled_vdates[0].start + 1.hour
    end
  end

  describe "Scheduler conflict resolution via duration" do
    it "reschedules second vdate after first when overlapping is not allowed" do
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

      scheduler.vdates = [t1, t2]

      from = Time.local(2023, 5, 10)
      to = Time.local(2023, 5, 11)

      scheduled_vdates = scheduler.build(from, to)

      scheduled_vdates.size.should eq 2

      first = scheduled_vdates.find!(&.vdate.==(t1))
      second = scheduled_vdates.find!(&.vdate.==(t2))

      first.start.hour.should eq 9
      first.finish.should eq first.start + 2.hours

      second.start.should be >= first.finish
    end
  end

  describe "Scheduler parallelism rules" do
    it "allows parallel vdates up to parallel limit per flag" do
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

      scheduler.vdates = [a, b, c]

      from = Time.local(2023, 5, 10)
      to = Time.local(2023, 5, 11)

      scheduled_vdates = scheduler.build(from, to)

      scheduled_vdates.size.should eq 3

      starts = scheduled_vdates.map(&.start)
      starts.count { |time| time.hour == 10 && time.minute == 0 }.should eq 2
    end
  end

  describe "Scheduler respects fixed vdates" do
    it "does not move fixed vdates even if conflicts occur" do
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

      scheduler.vdates = [fixed, movable]

      from = Time.local(2023, 5, 10)
      to = Time.local(2023, 5, 11)

      scheduled_vdates = scheduler.build(from, to)

      scheduled_vdates.size.should eq 2

      fixed_i = scheduled_vdates.find!(&.vdate.==(fixed))
      movable_i = scheduled_vdates.find!(&.vdate.==(movable))

      fixed_i.start.hour.should eq 9
      movable_i.start.should be >= fixed_i.finish
    end
  end

  describe "Scheduler dependencies" do
    it "schedules dependent vdate after its dependency" do
      scheduler = VirtualDate::Scheduler.new

      a = VirtualDate.new
      a.duration = 1.hour
      a.due << VirtualTime.new(hour: 9)

      b = VirtualDate.new
      b.duration = 1.hour
      b.depends_on << a
      b.due << VirtualTime.new(hour: 9)

      scheduler.vdates = [a, b]

      from = Time.local(2023, 5, 10)
      to = Time.local(2023, 5, 11)

      scheduled_vdates = scheduler.build(from, to)

      scheduled_vdates.size.should eq 2

      ia = scheduled_vdates.find!(&.vdate.==(a))
      ib = scheduled_vdates.find!(&.vdate.==(b))

      ib.start.should be >= ia.finish
    end
  end

  describe "Scheduler + on?" do
    it "reports on_in_schedule? correctly" do
      scheduler = VirtualDate::Scheduler.new

      vdate = VirtualDate.new
      vdate.duration = 1.hour
      vdate.due << VirtualTime.new(hour: 10)

      scheduler.vdates << vdate

      from = Time.local(2023, 5, 10)
      to = Time.local(2023, 5, 11)

      scheduled_vdates = scheduler.build(from, to)

      scheduler.on_in_schedule?(scheduled_vdates, vdate, Time.local(2023, 5, 10, 10, 30)).should be_true
      scheduler.on_in_schedule?(scheduled_vdates, vdate, Time.local(2023, 5, 10, 11, 30)).should be_false
    end
  end

  it "staggered scheduler creates multiple staggered scheduled_vdates" do
    scheduler = VirtualDate::Scheduler.new

    vdate = VirtualDate.new
    vdate.due << VirtualTime.from_time(Time.local(2023, 5, 10, 10, 0))
    vdate.duration = 1.hour
    vdate.parallel = 3
    vdate.stagger = 30.minutes

    scheduler.vdates << vdate

    scheduled_vdates = scheduler.build(
      Time.local(2023, 5, 10, 0, 0),
      Time.local(2023, 5, 10, 23, 59)
    )

    starts = scheduled_vdates.map(&.start)

    starts.should contain(Time.local(2023, 5, 10, 10, 0))
    starts.should contain(Time.local(2023, 5, 10, 10, 30))
    starts.should contain(Time.local(2023, 5, 10, 11, 0))
    scheduled_vdates.size.should eq 3
  end

  it "ignores stagger when parallel is 1" do
    scheduler = VirtualDate::Scheduler.new

    vdate = VirtualDate.new
    vdate.due << VirtualTime.from_time(Time.local(2023, 5, 10, 9, 0))
    vdate.duration = 1.hour
    vdate.parallel = 1
    vdate.stagger = 15.minutes

    scheduler.vdates << vdate

    scheduled_vdates = scheduler.build(
      Time.local(2023, 5, 10),
      Time.local(2023, 5, 11)
    )

    scheduled_vdates.size.should eq 1
    scheduled_vdates.first.start.should eq Time.local(2023, 5, 10, 9, 0)
  end

  it "does not create staggered scheduled_vdates past the horizon" do
    scheduler = VirtualDate::Scheduler.new

    vdate = VirtualDate.new
    vdate.due << VirtualTime.from_time(Time.local(2023, 5, 10, 10, 0))
    vdate.parallel = 4
    vdate.stagger = 30.minutes

    scheduler.vdates << vdate

    scheduled_vdates = scheduler.build(
      Time.local(2023, 5, 10, 9, 0),
      Time.local(2023, 5, 10, 10, 45)
    )

    scheduled_vdates.map(&.start).should eq [
      Time.local(2023, 5, 10, 10, 0),
      Time.local(2023, 5, 10, 10, 30),
    ]
  end

  it "applies omit rules independently to staggered scheduled_vdates" do
    scheduler = VirtualDate::Scheduler.new

    vdate = VirtualDate.new
    vdate.due << VirtualTime.from_time(Time.local(2023, 5, 10, 10, 0))
    vdate.parallel = 3
    vdate.stagger = 30.minutes

    omit = VirtualTime.new
    omit.hour = 10
    omit.minute = 30
    vdate.omit << omit

    scheduler.vdates << vdate

    scheduled_vdates = scheduler.build(
      Time.local(2023, 5, 10),
      Time.local(2023, 5, 11)
    )

    scheduled_vdates.map(&.start).should eq [
      Time.local(2023, 5, 10, 10, 0),
      Time.local(2023, 5, 10, 11, 0),
    ]
  end

  it "does not reschedule fixed staggered vdates" do
    scheduler = VirtualDate::Scheduler.new

    vdate = VirtualDate.new
    vdate.due << VirtualTime.from_time(Time.local(2023, 5, 10, 10, 0))
    vdate.parallel = 2
    vdate.stagger = 30.minutes
    vdate.fixed = true

    scheduler.vdates << vdate

    scheduled_vdates = scheduler.build(
      Time.local(2023, 5, 10),
      Time.local(2023, 5, 11)
    )

    scheduled_vdates.size.should eq 2
    scheduled_vdates.map(&.start).should eq [
      Time.local(2023, 5, 10, 10, 0),
      Time.local(2023, 5, 10, 10, 30),
    ]
  end

  it "raises when stagger is zero or negative" do
    scheduler = VirtualDate::Scheduler.new

    vdate = VirtualDate.new
    vdate.due << VirtualTime.from_time(Time.local(2023, 5, 10, 10, 0))
    vdate.parallel = 2
    vdate.stagger = 0.seconds

    scheduler.vdates << vdate

    expect_raises(ArgumentError) do
      scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))
    end
  end

  describe "Scheduler priority handling" do
    it "prefers higher-priority vdate when both conflict and are movable" do
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

      scheduler.vdates = [low, high]

      scheduled_vdates = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      hi = scheduled_vdates.find!(&.vdate.==(high))
      lo = scheduled_vdates.find!(&.vdate.==(low))

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

      scheduler.vdates = [movable, fixed]

      scheduled_vdates = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      fi = scheduled_vdates.find!(&.vdate.==(fixed))
      mi = scheduled_vdates.find!(&.vdate.==(movable))

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

      scheduler.vdates = [a, blocker, b]

      scheduled_vdates = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11, 23, 59, 59)
      )

      ia = scheduled_vdates.find!(&.vdate.==(a))
      ib = scheduled_vdates.find!(&.vdate.==(b))
      blocker_i = scheduled_vdates.find!(&.vdate.==(blocker))
      ib.start.should be >= ia.finish
      ib.start.should be >= blocker_i.finish
    end
  end

  describe "Scheduler parallelism across different flags" do
    it "does not restrict vdates with different flags" do
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

      scheduler.vdates = [a, b]

      scheduled_vdates = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      scheduled_vdates.size.should eq 2
      scheduled_vdates.all? { |i| i.start.hour == 10 }.should be_true
    end
  end

  describe "Scheduler on? invariant" do
    it "ensures all scheduled scheduled_vdates are effectively on" do
      scheduler = VirtualDate::Scheduler.new

      vdate = VirtualDate.new
      vdate.duration = 1.hour
      vdate.due << VirtualTime.new(hour: 10)
      vdate.omit << VirtualTime.new(hour: 10)
      vdate.shift = 1.hour

      scheduler.vdates << vdate

      scheduled_vdates = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      scheduled_vdates.each do |i|
        vdate.on?(i.start).should be_true
      end
    end
  end

  describe "Scheduler explanations" do
    it "attaches explanations to vdate scheduled_vdates" do
      scheduler = VirtualDate::Scheduler.new

      vdate = VirtualDate.new
      vdate.duration = 1.hour
      vdate.shift = 30.minutes
      vdate.due << VirtualTime.new(hour: 10)
      vdate.omit << VirtualTime.new(hour: 10)

      scheduler.vdates << vdate

      scheduled_vdates = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      inst = scheduled_vdates.first
      inst.explanation.should_not be_nil
      inst.explanation.lines.should_not be_empty
    end
  end

  describe "Scheduler determinism" do
    it "produces identical results on repeated runs" do
      scheduler = VirtualDate::Scheduler.new

      vdate = VirtualDate.new
      vdate.duration = 1.hour
      vdate.due << VirtualTime.new(hour: 10)

      scheduler.vdates << vdate

      from = Time.local(2023, 5, 10)
      to = Time.local(2023, 5, 11)

      a = scheduler.build(from, to)
      b = scheduler.build(from, to)

      a.map(&.start).should eq b.map(&.start)
    end
  end

  describe "Scheduler priority handling" do
    it "prefers higher-priority vdate when both conflict and are movable" do
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

      scheduler.vdates = [low, high]

      scheduled_vdates = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      hi = scheduled_vdates.find!(&.vdate.id.==("high"))
      lo = scheduled_vdates.find!(&.vdate.id.==("low"))

      hi.start.hour.should eq 9
      lo.start.should be >= hi.finish
    end
  end

  it "does not allow priority to override fixed vdates" do
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

    scheduler.vdates = [fixed, aggressive]

    scheduled_vdates = scheduler.build(
      Time.local(2023, 5, 10),
      Time.local(2023, 5, 11)
    )

    scheduled_vdates.size.should eq 2

    f = scheduled_vdates.find!(&.vdate.id.==("fixed"))
    a = scheduled_vdates.find!(&.vdate.id.==("aggressive"))

    f.start.hour.should eq 9
    a.start.should be >= f.finish
  end

  describe "Scheduler deadline enforcement" do
    it "rejects scheduling that would finish after deadline" do
      scheduler = VirtualDate::Scheduler.new

      vdate = VirtualDate.new("deadline-vdate")
      vdate.duration = 2.hours
      vdate.deadline = Time.local(2023, 5, 10, 10, 0)
      vdate.due << VirtualTime.new(hour: 9)

      scheduler.vdates << vdate

      scheduled_vdates = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      scheduled_vdates.should be_empty
    end

    it "allows scheduling that finishes exactly at deadline" do
      scheduler = VirtualDate::Scheduler.new

      vdate = VirtualDate.new("exact")
      vdate.duration = 1.hour
      vdate.deadline = Time.local(2023, 5, 10, 10, 0)
      vdate.due << VirtualTime.new(hour: 9)

      scheduler.vdates << vdate

      scheduled_vdates = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      scheduled_vdates.size.should eq 1
      scheduled_vdates.first.finish.should eq vdate.deadline
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

    scheduler.vdates = [b, a]

    scheduled_vdates = scheduler.build(
      Time.local(2023, 5, 10),
      Time.local(2023, 5, 10, 23, 59, 59)
    )

    ia = scheduled_vdates.find!(&.vdate.id.==("a"))
    ib = scheduled_vdates.find!(&.vdate.id.==("b"))

    ib.start.should be >= ia.finish
  end

  describe "Scheduler explanations" do
    it "attaches explanations to vdate scheduled_vdates" do
      scheduler = VirtualDate::Scheduler.new

      vdate = VirtualDate.new("explain")
      vdate.duration = 1.hour
      vdate.shift = 30.minutes
      vdate.due << VirtualTime.new(hour: 9)

      blocker = VirtualDate.new("blocker")
      blocker.duration = 2.hours
      blocker.fixed = true
      blocker.due << VirtualTime.new(hour: 9)

      scheduler.vdates = [blocker, vdate]

      scheduled_vdates = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      inst = scheduled_vdates.find!(&.vdate.id.==("explain"))
      inst.explanation.lines.should_not be_empty
    end
  end

  it "never schedules vdates outside the requested horizon" do
    scheduler = VirtualDate::Scheduler.new

    vdate = VirtualDate.new
    vdate.duration = 1.hour
    vdate.shift = 2.hours
    vdate.due << VirtualTime.new(hour: 23)

    scheduler.vdates << vdate

    from = Time.local(2023, 5, 10)
    to = Time.local(2023, 5, 10, 23, 0)

    scheduled = scheduler.build(from, to)

    scheduled.each do |i|
      i.start.should be >= from
      i.finish.should be <= to
    end
  end

  describe "ICS export" do
    it "folds content lines to 75 octets" do
      scheduler = VirtualDate::Scheduler.new

      vdate = VirtualDate.new("folding-vdate")
      vdate.duration = 1.hour
      vdate.shift = 30.minutes
      vdate.due << VirtualTime.new(hour: 10)
      vdate.omit << VirtualTime.new(hour: 10)

      scheduler.vdates << vdate

      scheduled = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      ics = VirtualDate::ICS.export(scheduled)

      # Regression: DESCRIPTION carries several explanation lines and used to be
      # emitted as one long line, which RFC 5545 does not permit.
      ics.split("\r\n", remove_empty: true).each do |line|
        line.bytesize.should be <= 75
      end

      # Folding is reversible, and loses nothing
      description = unfold_ics(ics).find!(&.starts_with?("DESCRIPTION:"))
      description.should contain "Initial candidate at"
      description.should contain "Scheduled at"
    end

    it "folds without splitting multi-byte characters" do
      scheduler = VirtualDate::Scheduler.new

      vdate = VirtualDate.new("ünïcödé-" + "ä" * 80)
      vdate.duration = 1.hour
      vdate.due << VirtualTime.new(hour: 10)

      scheduler.vdates << vdate

      scheduled = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      ics = VirtualDate::ICS.export(scheduled)

      ics.split("\r\n", remove_empty: true).each do |line|
        line.bytesize.should be <= 75
        # A split inside a multi-byte character would leave invalid UTF-8
        line.valid_encoding?.should be_true
      end

      unfold_ics(ics).find!(&.starts_with?("SUMMARY:")).should eq "SUMMARY:#{vdate.id}"
    end

    it "exports scheduled vdates as valid iCal events" do
      scheduler = VirtualDate::Scheduler.new

      vdate = VirtualDate.new("ics-vdate")
      vdate.duration = 1.hour
      vdate.due << VirtualTime.new(hour: 10)

      scheduler.vdates << vdate

      scheduled_vdates = scheduler.build(
        Time.local(2023, 5, 10),
        Time.local(2023, 5, 11)
      )

      ics = VirtualDate::ICS.export(scheduled_vdates)

      ics.should contain("BEGIN:VCALENDAR")
      ics.should contain("BEGIN:VEVENT")
      ics.should contain("SUMMARY:ics-vdate")
      ics.should contain("END:VEVENT")
      ics.should contain("END:VCALENDAR")

      # The DESCRIPTION must hold the human-readable explanation lines,
      # not the raw struct representation (regression for Explanation#to_s).
      description = ics.lines.find!(&.starts_with?("DESCRIPTION:"))
      description.should_not contain("Explanation(@lines")
      description.should contain("Scheduled")
    end

    it "omits DTEND for a zero-duration vdate" do
      scheduler = VirtualDate::Scheduler.new

      vdate = VirtualDate.new("instant")
      vdate.duration = 0.seconds
      vdate.due << VirtualTime.new(hour: 10)

      scheduler.vdates << vdate

      scheduled = scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))
      ics = VirtualDate::ICS.export(scheduled)

      # Regression: DTEND was emitted equal to DTSTART, which RFC 5545 section
      # 3.8.2.2 forbids -- it must be strictly later. Leaving it out is the
      # RFC's own way of saying the event ends when it starts.
      ics.should contain "DTSTART:"
      ics.should_not contain "DTEND:"

      # A vdate that does last a while still gets one
      vdate.duration = 1.hour
      scheduled = scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))
      VirtualDate::ICS.export(scheduled).should contain "DTEND:"
    end
  end

  it "on? returns false when strict_on? is nil" do
    vd = VirtualDate.new
    vd.begin = Time.local(2023, 5, 10)

    vd.on?(Time.local(2023, 5, 9)).should be_false
  end

  it "on? follows an `on` override that is a span" do
    vd = VirtualDate.new
    vd.due << VirtualTime.new(hour: 10)
    vd.on = 2.hours

    asked = Time.local(2023, 5, 10, 10, 0)
    landed = Time.local(2023, 5, 10, 12, 0)

    vd.resolve(asked).should eq landed

    # Regression: the inverse search consulted `#shift` only, so a vdate
    # displaced by its `#on` override reported false even at the very time
    # `#resolve` says it lands on
    vd.on?(landed).should be_true
  end

  it "on? does not treat true as inverse-reachable" do
    vd = VirtualDate.new
    date = Time.local(2023, 5, 10)

    vd.due << VirtualTime.from_time(date)
    vd.shift = 1.hour

    vd.strict_on?(date).should be_true
    vd.on?(date + 1.hour).should be_false
  end

  it "treats max_shift = 0 as no shifting allowed" do
    vd = VirtualDate.new
    date = Time.local(2023, 5, 10)

    vd.due << VirtualTime.from_time(date)
    vd.omit << VirtualTime.from_time(date)
    vd.shift = 1.hour

    vd.strict_on?(date, max_shift: 0.seconds).should be_false
  end

  it "treats max_shifts = 0 as shifts exhausted" do
    vd = VirtualDate.new
    date = Time.local(2023, 5, 10)

    vd.due << VirtualTime.from_time(date)
    vd.omit << VirtualTime.from_time(date)
    vd.shift = 1.hour

    vd.strict_on?(date, max_shifts: 0).should be_false
  end

  it "ensures staggered scheduled vdates are not strictly invalid" do
    scheduler = VirtualDate::Scheduler.new

    vdate = VirtualDate.new
    vdate.due << VirtualTime.from_time(Time.local(2023, 5, 10, 10, 0))
    vdate.omit << VirtualTime.from_time(Time.local(2023, 5, 10, 10, 0))
    vdate.shift = 1.hour
    vdate.parallel = 2
    vdate.stagger = 30.minutes

    scheduler.vdates << vdate

    scheduled = scheduler.build(
      Time.local(2023, 5, 10),
      Time.local(2023, 5, 11)
    )

    scheduled.each do |i|
      # The correct invariant:
      vdate.strict_on?(i.start).should_not be_false
    end
  end

  it "fails scheduling when deadline makes placement impossible" do
    scheduler = VirtualDate::Scheduler.new

    blocker = VirtualDate.new
    blocker.duration = 2.hours
    blocker.fixed = true
    blocker.flags << "work"
    blocker.due << VirtualTime.new(hour: 9)

    doomed = VirtualDate.new
    doomed.duration = 1.hour
    doomed.deadline = Time.local(2023, 5, 10, 10, 0)
    doomed.flags << "work"
    doomed.shift = 30.minutes
    doomed.due << VirtualTime.new(hour: 9)

    scheduler.vdates = [blocker, doomed]

    scheduled = scheduler.build(
      Time.local(2023, 5, 10),
      Time.local(2023, 5, 11)
    )

    scheduled.map(&.vdate).should_not contain(doomed)
  end

  it "rejects duplicate keys at root mapping level" do
    yaml = <<-YAML
      schema_version: 2
      schema_version: 2
      vdates: []
      YAML

    expect_raises(ArgumentError) do
      VirtualDate::VirtualDateFile.load(yaml)
    end
  end

  it "resolve distinguishes nil (not applicable) from false (unschedulable)" do
    date = Time.local(2023, 5, 10)

    vd = VirtualDate.new
    vd.begin = Time.local(2023, 5, 11)

    vd.resolve(date).should be_nil

    vd2 = VirtualDate.new
    vd2.due << VirtualTime.from_time(date)
    vd2.omit << VirtualTime.from_time(date)
    vd2.shift = false

    vd2.resolve(date).should be_false
  end

  it "on? with shift = true treats omitted times as directly on" do
    date = Time.local(2023, 5, 10, 10, 0)

    vd = VirtualDate.new
    vd.due << VirtualTime.from_time(date)
    vd.omit << VirtualTime.from_time(date)
    vd.shift = true

    vd.on?(date).should be_true
  end

  it "enforces deadlines on zero-duration vdates" do
    scheduler = VirtualDate::Scheduler.new

    vdate = VirtualDate.new("instant")
    vdate.duration = 0.seconds
    vdate.deadline = Time.local(2023, 5, 10, 9, 0)
    vdate.due << VirtualTime.new(hour: 10)

    scheduler.vdates << vdate

    # Regression: zero-duration vdates took a shortcut that skipped the
    # deadline check entirely
    scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11)).should be_empty
  end

  it "keeps the explanation of a zero-duration vdate" do
    scheduler = VirtualDate::Scheduler.new

    vdate = VirtualDate.new("instant")
    vdate.duration = 0.seconds
    vdate.due << VirtualTime.new(hour: 10)

    scheduler.vdates << vdate

    scheduled = scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))

    scheduled.size.should eq 1
    # Regression: the candidate's explanation used to be discarded
    scheduled[0].explanation.lines.first.should contain "Initial candidate at"
  end

  it "excludes a shift-resolved start at the exclusive end of the window" do
    scheduler = VirtualDate::Scheduler.new

    vdate = VirtualDate.new("edge")
    vdate.duration = 0.seconds
    vdate.due << VirtualTime.new(hour: 10, minute: 0)
    vdate.omit << VirtualTime.new(hour: 10, minute: 0)
    vdate.shift = 1.hour

    scheduler.vdates << vdate

    # The 10:00 occurrence is omitted and shifts to 11:00, which is outside the
    # half-open window [from, 11:00)
    scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 10, 11, 0)).should be_empty

    scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 10, 11, 1))
      .map(&.start).should eq [Time.local(2023, 5, 10, 11, 0)]
  end

  it "raises when a vdate that others depend on cannot be scheduled" do
    a = VirtualDate.new("a")
    a.duration = 2.hours
    a.deadline = Time.local(2023, 5, 10, 10, 0)
    a.due << VirtualTime.new(hour: 9)

    b = VirtualDate.new("b")
    b.duration = 1.hour
    b.depends_on << a
    b.due << VirtualTime.new(hour: 9)

    scheduler = VirtualDate::Scheduler.new([a, b])

    expect_raises(ArgumentError, /which other vdates depend on/) do
      scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))
    end
  end

  it "drops an unschedulable vdate that only has dependencies of its own" do
    a = VirtualDate.new("a")
    a.duration = 1.hour
    a.due << VirtualTime.new(hour: 9)

    b = VirtualDate.new("b")
    b.duration = 2.hours
    b.deadline = Time.local(2023, 5, 10, 10, 0)
    b.depends_on << a
    b.due << VirtualTime.new(hour: 9)

    scheduler = VirtualDate::Scheduler.new([a, b])
    scheduled = scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))

    # Regression: having dependencies used to be mistaken for being a
    # dependency, so an unschedulable "b" raised instead of being dropped
    scheduled.map(&.vdate.id).should eq ["a"]
  end

  it "keeps a depended-upon vdate whose later occurrence does not fit the window" do
    a = VirtualDate.new("a")
    a.duration = 2.hours
    a.due << VirtualTime.new(hour: 9)

    b = VirtualDate.new("b")
    b.duration = 30.minutes
    b.depends_on << a
    b.due << VirtualTime.new(hour: 14)

    scheduler = VirtualDate::Scheduler.new([a, b])

    # Regression: any rejected candidate of a depended-upon vdate raised, so a
    # second occurrence running past the horizon failed the whole build even
    # though the first one had been scheduled
    scheduled = scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11, 10, 0))
    scheduled.map(&.vdate.id).should eq ["a", "b"]
    scheduled.first.start.should eq Time.local(2023, 5, 10, 9, 0)
  end

  it "refuses to build vdates that a YAML document would be rejected for" do
    from, to = Time.local(2023, 5, 10), Time.local(2023, 5, 11)

    # Regression: a negative duration finishes before it starts, which switches
    # off overlap detection -- the vdate then silently shared a slot with a
    # `parallel: 1` one, and `#on_in_schedule?` never reported it as on
    vdate = VirtualDate.new("bad")
    vdate.due << VirtualTime.new(hour: 10)
    vdate.duration = -1.hour

    expect_raises(ArgumentError, /duration of vdate 'bad' must be >= 0/) do
      VirtualDate::Scheduler.new([vdate]).build(from, to)
    end

    vdate.duration = 1.hour
    vdate.parallel = 0

    expect_raises(ArgumentError, /parallel of vdate 'bad' must be >= 1/) do
      VirtualDate::Scheduler.new([vdate]).build(from, to)
    end

    vdate.parallel = 1
    VirtualDate::Scheduler.new([vdate]).build(from, to).size.should eq 1
  end

  it "does not let a fixed vdate displace one that others depend on" do
    dep = VirtualDate.new("b") # movable, and "e" depends on it
    dep.duration = 2.hours
    dep.due << VirtualTime.new(hour: 9)

    gate = VirtualDate.new("c") # keeps "f" out of the initial ready set
    gate.duration = 10.minutes
    gate.due << VirtualTime.new(hour: 8)

    fixed = VirtualDate.new("f") # fixed, and therefore scheduled after "b"
    fixed.fixed = true
    fixed.duration = 2.hours
    fixed.due << VirtualTime.new(hour: 9)
    fixed.depends_on << gate

    follower = VirtualDate.new("e")
    follower.duration = 30.minutes
    follower.depends_on << dep
    follower.due << VirtualTime.new(hour: 9)

    scheduled = VirtualDate::Scheduler.new([dep, gate, fixed, follower])
      .build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))

    # Regression: only the priority comparison refused to displace a
    # depended-upon vdate; a fixed one displaced "b" anyway, leaving "e"
    # scheduled after a finish time that was no longer in the schedule
    scheduled.map(&.vdate.id).should eq ["c", "b", "e"]
    scheduled.find! { |i| i.vdate.id == "e" }.start.should eq Time.local(2023, 5, 10, 11, 0)
  end

  it "resolves dependencies of vdates appended after construction" do
    yaml = <<-YAML
      ---
      schema_version: 2
      vdates:
      - id: a
        duration: 3600
        due:
        - hour: 9
          default_match: true
      - id: b
        duration: 3600
        depends_on:
        - a
        due:
        - hour: 8
          default_match: true
      YAML

    scheduler = VirtualDate::Scheduler.new
    VirtualDate::VirtualDateFile.load(yaml).each { |vdate| scheduler.vdates << vdate }

    # Regression: ids were turned into references only by the constructor, so a
    # vdate appended afterwards kept its dependencies unresolved and was
    # scheduled as though it had none -- "b" ran at 08:00, before "a"
    scheduled = scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))
    scheduled.map { |i| {i.vdate.id, i.start} }.should eq [
      {"a", Time.local(2023, 5, 10, 9, 0)},
      {"b", Time.local(2023, 5, 10, 10, 0)},
    ]
  end

  it "never schedules one vdate twice at the same start" do
    # Occurrences that fall before a dependency floor all move onto it
    anchor = VirtualDate.new("anchor")
    anchor.duration = 1.hour
    anchor.due << VirtualTime.new(day: 12, hour: 9)

    follower = VirtualDate.new("follower")
    follower.duration = 0.seconds
    follower.depends_on << anchor
    follower.due << VirtualTime.new(hour: 8)

    scheduled = VirtualDate::Scheduler.new([anchor, follower])
      .build(Time.local(2023, 5, 10), Time.local(2023, 5, 14))

    # Regression: the May 10, 11 and 12 occurrences of "follower" were each
    # moved to the floor and scheduled there, three times over
    starts = scheduled.select { |i| i.vdate.id == "follower" }.map(&.start)
    starts.should eq starts.uniq

    # And conflict resolution can walk two occurrences onto one start
    fixed = VirtualDate.new("fixed")
    fixed.fixed = true
    fixed.duration = 1.hour
    fixed.flags << "task"
    fixed.due << VirtualTime.new(hour: 10)

    twice = VirtualDate.new("twice")
    twice.duration = 1.hour
    twice.parallel = 2
    twice.flags << "task"
    twice.due << VirtualTime.new(hour: 10)
    twice.due << VirtualTime.new(hour: 11)

    scheduled = VirtualDate::Scheduler.new([fixed, twice])
      .build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))

    starts = scheduled.select { |i| i.vdate.id == "twice" }.map(&.start)
    starts.should eq [Time.local(2023, 5, 10, 11, 0)]
  end

  it "bounds conflict-driven shifting by max_shift" do
    blocker = VirtualDate.new("blocker")
    blocker.fixed = true
    blocker.duration = 6.hours
    blocker.due << VirtualTime.new(hour: 10)

    movable = VirtualDate.new("movable")
    movable.duration = 1.hour
    movable.due << VirtualTime.new(hour: 10)

    from, to = Time.local(2023, 5, 10), Time.local(2023, 5, 11)

    # Regression: conflict resolution shifted forward until the horizon,
    # ignoring the vdate's own limits, so a 10:00 vdate could land at 16:00
    movable.max_shift = 30.minutes
    VirtualDate::Scheduler.new([blocker, movable]).build(from, to)
      .map(&.vdate.id).should eq ["blocker"]

    # Without a limit it still yields to the fixed vdate as before
    movable.max_shift = nil
    VirtualDate::Scheduler.new([blocker, movable]).build(from, to)
      .map(&.start).should eq [Time.local(2023, 5, 10, 10, 0), Time.local(2023, 5, 10, 16, 0)]
  end

  it "caps parallelism by the strictest limit among overlapping vdates" do
    tolerant = VirtualDate.new("tolerant")
    tolerant.duration = 1.hour
    tolerant.flags << "meeting"
    tolerant.parallel = 2
    tolerant.due << VirtualTime.new(hour: 10)

    strict = VirtualDate.new("strict")
    strict.duration = 1.hour
    strict.flags << "meeting"
    strict.parallel = 1
    strict.due << VirtualTime.new(hour: 10)

    # Regression: only the candidate's own `parallel` was consulted, so a
    # tolerant vdate was placed on top of an already-scheduled strict one and
    # broke the latter's limit after the fact
    scheduled = VirtualDate::Scheduler.new([strict, tolerant])
      .build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))

    scheduled.map(&.start).should eq [Time.local(2023, 5, 10, 10, 0), Time.local(2023, 5, 10, 11, 0)]
  end

  it "schedules zero-duration vdates without blocking others" do
    scheduler = VirtualDate::Scheduler.new

    instant = VirtualDate.new
    instant.duration = 0.seconds
    instant.due << VirtualTime.new(hour: 10)

    long = VirtualDate.new
    long.duration = 2.hours
    long.due << VirtualTime.new(hour: 10)

    scheduler.vdates = [instant, long]

    scheduled = scheduler.build(
      Time.local(2023, 5, 10),
      Time.local(2023, 5, 11)
    )

    scheduled.size.should eq 2
  end

  it "rejects duplicate keys inside vdate mapping" do
    yaml = <<-YAML
      schema_version: 2
      vdates:
        - id: a
          id: b
      YAML

    expect_raises(ArgumentError) do
      VirtualDate::VirtualDateFile.load(yaml)
    end
  end

  it "detects dependency cycles" do
    a = VirtualDate.new("a")
    b = VirtualDate.new("b")

    a.depends_on << b
    b.depends_on << a

    expect_raises(ArgumentError) do
      VirtualDate::Scheduler.new([a, b])
    end
  end

  it "round-trips a VirtualDate through YAML" do
    vd = VirtualDate.new("task1")
    vd.due << VirtualTime.new(hour: 10)
    vd.omit << VirtualTime.new(day: 15)
    vd.shift = 1.hour
    vd.duration = 30.minutes
    vd.max_shift = 2.hours
    vd.flags << "work"

    vd2 = VirtualDate.from_yaml(vd.to_yaml)
    vd2.id.should eq "task1"
    vd2.shift.should eq 1.hour
    vd2.duration.should eq 30.minutes
    vd2.max_shift.should eq 2.hours
    vd2.due.size.should eq 1
    vd2.omit.size.should eq 1
    vd2.flags.should eq Set{"work"}
  end

  it "round-trips a `false` shift and `on` through YAML" do
    vd = VirtualDate.new("falsey")

    # Regression: `YAML::Serializable` tests a converter-backed property for
    # truthiness before handing it to the converter, so `false` was written out
    # as null and read back as nil -- turning "due but unschedulable" into "not
    # scheduled at all", and dropping an `on: false` override altogether.
    # `false` is `shift`'s own default, so this affected every vdate saved.
    vd.shift.should be_false
    vd.to_yaml.should contain "shift: false"
    VirtualDate.from_yaml(vd.to_yaml).shift.should be_false

    vd.on = false
    vd.to_yaml.should contain "on: false"
    VirtualDate.from_yaml(vd.to_yaml).on.should be_false

    vd.on = nil
    VirtualDate.from_yaml(vd.to_yaml).on.should be_nil
  end

  it "round-trips absolute begin/end/deadline times through YAML" do
    vd = VirtualDate.new("bounded")
    vd.begin = Time.local(2023, 5, 10, 9, 0, 0)
    vd.end = Time.local(2023, 5, 20, 17, 30, 0)
    vd.deadline = Time.local(2023, 5, 20, 18, 0, 0)

    # Regression: `Time#to_s` was emitted, which is not RFC 3339 and so could
    # not be read back -- the value was then misread as a VirtualTime rule.
    vd2 = VirtualDate.from_yaml vd.to_yaml
    vd2.begin.should eq vd.begin
    vd2.end.should eq vd.end
    vd2.deadline.should eq vd.deadline
  end

  it "round-trips sub-second spans through YAML" do
    vd = VirtualDate.new("subsecond")
    vd.shift = -500.milliseconds
    vd.duration = 1500.milliseconds
    vd.max_shift = 2500.milliseconds

    # Regression: spans were truncated to whole seconds, so a sub-second shift
    # came back as `0` -- i.e. as "no shift at all".
    vd2 = VirtualDate.from_yaml vd.to_yaml
    vd2.shift.should eq -500.milliseconds
    vd2.duration.should eq 1500.milliseconds
    vd2.max_shift.should eq 2500.milliseconds
  end

  it "keeps whole spans as plain integer seconds in YAML" do
    vd = VirtualDate.new("whole")
    vd.duration = 1.hour
    vd.shift = -90.seconds
    vd.max_shift = 2.hours

    yaml = vd.to_yaml
    yaml.should contain "duration: 3600"
    yaml.should contain "shift: -90"
    yaml.should contain "max_shift: 7200"

    # Documents that documents written by older versions still load
    VirtualDate.from_yaml(yaml).duration.should eq 1.hour
  end

  it "serializes dependencies built in code and restores them on load" do
    a = VirtualDate.new("a")
    b = VirtualDate.new("b")
    b.depends_on << a

    yaml = [a, b].to_yaml
    yaml.should contain "depends_on"

    restored = Array(VirtualDate).from_yaml(yaml)
    restored[1].depends_on_ids.should eq ["a"]

    # Scheduler resolves ids back into the object graph
    scheduler = VirtualDate::Scheduler.new(restored)
    dep = scheduler.vdates.find! { |vdate| vdate.id == "b" }.depends_on
    dep.map(&.id).should eq ["a"]

    # Regression: the ids were derived by assigning to `#depends_on_ids`, so
    # serializing altered the object -- enough to change what a later
    # `Scheduler#build` did with it
    b.depends_on_ids.should be_empty
  end

  it "does not change a vdate by serializing it" do
    dependency = VirtualDate.new("a")

    vdate = VirtualDate.new("b")
    vdate.duration = 1.hour
    vdate.due << VirtualTime.new(hour: 8)
    vdate.depends_on << dependency

    # A scheduler that does not know about the dependency: "b" simply cannot
    # be placed, both before and after the schedule is written out
    scheduler = VirtualDate::Scheduler.new([vdate])
    from, to = Time.local(2023, 5, 10), Time.local(2023, 5, 11)

    scheduler.build(from, to).should be_empty
    vdate.to_yaml
    scheduler.build(from, to).should be_empty
  end

  it "loads a schema_version document via VirtualDateFile.load" do
    yaml = <<-YAML
      schema_version: 2
      vdates:
        - id: a
          duration: 3600
        - id: b
      YAML

    vdates = VirtualDate::VirtualDateFile.load(yaml)
    vdates.map(&.id).should eq ["a", "b"]
    vdates[0].duration.should eq 1.hour
  end

  it "accepts current/older schema versions but rejects newer ones" do
    older = "schema_version: 1\nvdates:\n  - id: a\n"
    current = "schema_version: #{VirtualDate::Migrator::CURRENT_VERSION}\nvdates:\n  - id: a\n"
    future = "schema_version: #{VirtualDate::Migrator::CURRENT_VERSION + 1}\nvdates:\n  - id: a\n"

    VirtualDate::VirtualDateFile.load(older).map(&.id).should eq ["a"]
    VirtualDate::VirtualDateFile.load(current).map(&.id).should eq ["a"]
    expect_raises(ArgumentError, /Unsupported schema_version/) do
      VirtualDate::VirtualDateFile.load(future)
    end
  end

  describe "Scheduler occurrence generation" do
    it "schedules sparse rules over windows longer than a few days" do
      scheduler = VirtualDate::Scheduler.new

      vdate = VirtualDate.new
      vdate.duration = 1.hour
      vdate.due << VirtualTime.new(day: 15, hour: 10, minute: 0)

      scheduler.vdates << vdate

      scheduled = scheduler.build(Time.local(2023, 5, 1), Time.local(2023, 6, 1))

      scheduled.size.should eq 1
      scheduled[0].start.should eq Time.local(2023, 5, 15, 10, 0)
    end

    it "schedules every occurrence of a recurring rule in the window" do
      scheduler = VirtualDate::Scheduler.new

      vdate = VirtualDate.new
      vdate.duration = 1.hour
      vdate.due << VirtualTime.new(hour: 10, minute: 0)

      scheduler.vdates << vdate

      scheduled = scheduler.build(Time.local(2023, 5, 1), Time.local(2023, 5, 6))

      scheduled.size.should eq 5
      scheduled.map(&.start).should eq (1..5).map { |day| Time.local(2023, 5, day, 10, 0) }
    end

    it "coalesces contiguous matching times into a single occurrence" do
      scheduler = VirtualDate::Scheduler.new

      # Matches every minute of hour 10, but that is one contiguous block,
      # so it must produce a single occurrence starting at 10:00.
      vdate = VirtualDate.new
      vdate.duration = 1.hour
      vdate.due << VirtualTime.new(hour: 10)

      scheduler.vdates << vdate

      scheduled = scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))

      scheduled.size.should eq 1
      scheduled[0].start.should eq Time.local(2023, 5, 10, 10, 0)
    end

    it "respects begin/end bounds during occurrence generation" do
      scheduler = VirtualDate::Scheduler.new

      vdate = VirtualDate.new
      vdate.duration = 1.hour
      vdate.due << VirtualTime.new(hour: 10, minute: 0)
      vdate.begin = Time.local(2023, 5, 3)

      scheduler.vdates << vdate

      scheduled = scheduler.build(Time.local(2023, 5, 1), Time.local(2023, 5, 6))

      scheduled.map(&.start).should eq (3..5).map { |day| Time.local(2023, 5, day, 10, 0) }
    end

    it "caps generated candidates at max_candidates" do
      scheduler = VirtualDate::Scheduler.new

      # Hourly rule: 48 occurrences in a two-day window
      vdate = VirtualDate.new
      vdate.due << VirtualTime.new(minute: 0)

      scheduler.vdates << vdate

      scheduled = scheduler.build(Time.local(2023, 5, 1), Time.local(2023, 5, 3), max_candidates: 5)

      scheduled.size.should eq 5
    end

    it "raises when the occurrence scan exceeds the iteration limit" do
      scheduler = VirtualDate::Scheduler.new

      # An always-matching rule is one giant contiguous run; scanning it at
      # 1-minute granularity over ~75 days exceeds MAX_RULE_ITERATIONS.
      vdate = VirtualDate.new
      vdate.due << VirtualTime.new

      scheduler.vdates << vdate

      expect_raises(ArgumentError, /Occurrence scan exceeded/) do
        scheduler.build(Time.local(2023, 5, 1), Time.local(2023, 7, 15))
      end
    end
  end

  describe "Scheduler conflict shifting edge cases" do
    it "terminates when conflicting vdates have zero-span shift" do
      scheduler = VirtualDate::Scheduler.new

      a = VirtualDate.new("a")
      b = VirtualDate.new("b")
      [a, b].each do |vdate|
        vdate.due << VirtualTime.new(hour: 10, minute: 0)
        vdate.duration = 30.minutes
        vdate.flags << "work"
        vdate.parallel = 1
        vdate.shift = 0.seconds
      end

      scheduler.vdates = [a, b]

      scheduled = scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))

      scheduled.size.should eq 2
      scheduled[1].start.should be >= scheduled[0].finish
    end

    it "resolves conflicts by moving forward even when shift is negative" do
      scheduler = VirtualDate::Scheduler.new

      a = VirtualDate.new("a")
      b = VirtualDate.new("b")
      [a, b].each do |vdate|
        vdate.due << VirtualTime.new(hour: 10, minute: 0)
        vdate.duration = 30.minutes
        vdate.flags << "work"
        vdate.parallel = 1
        vdate.shift = -1.hour
      end

      scheduler.vdates = [a, b]

      scheduled = scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))

      scheduled.size.should eq 2
      scheduled[0].start.should eq Time.local(2023, 5, 10, 10, 0)
      scheduled[1].start.should be >= scheduled[0].finish
    end
  end

  describe "Scheduler flag-aware conflict selection" do
    it "does not displace an unrelated (different-flag) vdate when resolving a flag conflict" do
      # "a" (home) and "w" (work) both occupy 10:00. "c" (work, high priority)
      # depends on "z", which sorts after "w", so "c" is processed only after
      # both "a" and "w" are already scheduled. It conflicts only with "w" and
      # must displace it -- not the innocent "a".
      a = VirtualDate.new("a")
      a.due << VirtualTime.new(hour: 10, minute: 0)
      a.duration = 30.minutes
      a.flags << "home"

      z = VirtualDate.new("z")
      z.due << VirtualTime.new(hour: 9, minute: 0)

      w = VirtualDate.new("w")
      w.due << VirtualTime.new(hour: 10, minute: 0)
      w.duration = 1.hour
      w.flags << "work"

      c = VirtualDate.new("c")
      c.due << VirtualTime.new(hour: 10, minute: 0)
      c.duration = 1.hour
      c.flags << "work"
      c.parallel = 1
      c.priority = 10
      c.depends_on << z

      scheduler = VirtualDate::Scheduler.new([a, z, w, c])
      scheduled = scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))

      # "w" is displaced by the higher-priority "c"; "a" survives untouched
      scheduled.map(&.vdate.id).sort!.should eq ["a", "c", "z"]
      scheduled.find! { |item| item.vdate.id == "a" }.start.should eq Time.local(2023, 5, 10, 10, 0)
      scheduled.find! { |item| item.vdate.id == "c" }.start.should eq Time.local(2023, 5, 10, 10, 0)
    end

    it "does not let priority displace a vdate that others depend on" do
      # "a" is scheduled first and "b" is placed right after it. "c" (higher
      # priority, same flag group) is processed last because it depends on "z".
      # Displacing "a" at that point would leave "b" anchored to a finish time
      # that is no longer in the schedule, so "c" must yield instead.
      a = VirtualDate.new("a")
      a.due << VirtualTime.new(hour: 10, minute: 0)
      a.duration = 1.hour
      a.flags << "work"

      b = VirtualDate.new("b")
      b.due << VirtualTime.new(hour: 10, minute: 0)
      b.duration = 30.minutes
      b.flags << "home"
      b.depends_on << a

      z = VirtualDate.new("z")
      z.due << VirtualTime.new(hour: 9, minute: 0)

      c = VirtualDate.new("c")
      c.due << VirtualTime.new(hour: 10, minute: 0)
      c.duration = 1.hour
      c.flags << "work"
      c.parallel = 1
      c.priority = 100
      c.depends_on << z

      scheduler = VirtualDate::Scheduler.new([a, b, z, c])
      scheduled = scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))

      scheduled.map(&.vdate.id).sort!.should eq ["a", "b", "c", "z"]

      by_id = scheduled.to_h { |item| {item.vdate.id, item} }
      by_id["a"].start.should eq Time.local(2023, 5, 10, 10, 0)
      by_id["b"].start.should eq by_id["a"].finish
      by_id["c"].start.should eq Time.local(2023, 5, 10, 11, 0)
    end

    it "shifts past the actual flag conflict instead of yielding to an unrelated fixed vdate" do
      # Fixed "f" (work, 10:00-13:00) does not compete with the "home" group,
      # so "c" only conflicts with "b" (home, 10:00-10:30) and starts at 10:30,
      # not at f's finish (13:00).
      f = VirtualDate.new("f")
      f.due << VirtualTime.new(hour: 10, minute: 0)
      f.duration = 3.hours
      f.flags << "work"
      f.fixed = true

      b = VirtualDate.new("b")
      b.due << VirtualTime.new(hour: 10, minute: 0)
      b.duration = 30.minutes
      b.flags << "home"

      c = VirtualDate.new("c")
      c.due << VirtualTime.new(hour: 10, minute: 0)
      c.duration = 30.minutes
      c.flags << "home"
      c.parallel = 1

      scheduler = VirtualDate::Scheduler.new([f, b, c])
      scheduled = scheduler.build(Time.local(2023, 5, 10), Time.local(2023, 5, 11))

      scheduled.map(&.vdate.id).sort!.should eq ["b", "c", "f"]
      scheduled.find! { |item| item.vdate.id == "c" }.start.should eq Time.local(2023, 5, 10, 10, 30)
    end
  end

  it "loads a legacy bare-sequence document via VirtualDateFile.load" do
    yaml = <<-YAML
      - id: a
        duration: 3600
      - id: b
      YAML

    vdates = VirtualDate::VirtualDateFile.load(yaml)
    vdates.map(&.id).should eq ["a", "b"]
    vdates[0].duration.should eq 1.hour
  end

  describe VirtualDate::Explanation do
    it "renders its lines (not the struct) in IO contexts" do
      e = VirtualDate::Explanation.new
      e.add("line one")
      e.add("line two")

      e.to_s.should eq "line one\nline two"
      String.build { |io| io << e }.should eq "line one\nline two"
    end
  end

  describe VirtualDate::YamlError do
    it "formats with 1-based line and column in IO contexts" do
      node = YAML::Nodes::Scalar.new("x")
      node.start_line = 4
      node.start_column = 2
      err = VirtualDate::YamlError.new("bad", node)

      err.to_s.should eq "Line 5, column 3: bad"
      "#{err}".should eq "Line 5, column 3: bad"
    end
  end
end
