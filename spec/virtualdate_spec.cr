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

  it "keeps an `on` override outside the shift bounds" do
    moment = Time.utc(2023, 1, 1, 10)

    # An override settles every time alike, so every instant is reachable.
    # Regression: `#on?` ran the override through the omit-shift bounds, which
    # `#strict_on?` never applies to it, so the two disagreed
    bounded = VirtualDate.new
    bounded.on = 2.hours
    bounded.max_shift = 1.hour
    bounded.resolve(moment).should eq moment + 2.hours
    bounded.on?(moment + 2.hours).should be_true

    exhausted = VirtualDate.new
    exhausted.on = 2.hours
    exhausted.max_shifts = 0
    exhausted.on?(moment + 2.hours).should be_true

    # A zero span means "displaced by nothing", i.e. on right here
    still = VirtualDate.new
    still.on = 0.seconds
    still.resolve(moment).should eq moment
    still.on?(moment).should be_true
  end

  it "keeps omit-driven shifting inside begin/end" do
    vd = VirtualDate.new
    vd.begin = Time.utc(2023, 3, 1)
    vd.end = Time.utc(2023, 3, 21)
    vd.due << VirtualTime.new(month: 3, day: 20)
    vd.omit << VirtualTime.new(month: 3, day: 20)
    vd.shift = 2.days

    # Regression: the shift search only avoided omitted times and never looked
    # at the bounds, so a vdate documented as "never on after" its end date
    # resolved to a day past it
    vd.resolve(Time.utc(2023, 3, 20)).should be_false
    vd.on?(Time.utc(2023, 3, 22)).should be_false

    backwards = VirtualDate.new
    backwards.begin = Time.utc(2023, 3, 19)
    backwards.end = Time.utc(2023, 3, 31)
    backwards.due << VirtualTime.new(month: 3, day: 20)
    backwards.omit << VirtualTime.new(month: 3, day: 20)
    backwards.shift = -2.days

    backwards.resolve(Time.utc(2023, 3, 20)).should be_false
    backwards.on?(Time.utc(2023, 3, 18)).should be_false
  end

  it "reads the boolean spellings the YAML schema accepts" do
    # Regression: `True` was refused although the same method used the schema
    # for nulls -- while the quoted string 'true' was taken for a boolean
    VirtualDate.from_yaml("id: x\nshift: True\n").shift.should be_true
    VirtualDate.from_yaml("id: x\nshift: FALSE\n").shift.should be_false
    VirtualDate.from_yaml("id: x\nshift: ~\n").shift.should be_nil

    # A number too large for Int64 is reported with its position, like every
    # other malformed value, rather than escaping as a bare ArgumentError
    expect_raises(YAML::ParseException, /number of seconds/) do
      VirtualDate.from_yaml("id: x\nduration: 99999999999999999999\n")
    end
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

  it "keeps every scheduled start inside the half-open window" do
    from, to = Time.local(2024, 5, 10, 9, 0, 0), Time.local(2024, 5, 11)

    # Regression: only `start >= to` was checked, so a negative shift carried
    # an occurrence out of the other side of the window
    backwards = VirtualDate.new("a")
    rule = VirtualTime.new(hour: 10)
    backwards.due << rule
    backwards.omit << rule
    backwards.shift = -2.hours
    backwards.duration = 30.minutes

    VirtualDate::Scheduler.new([backwards]).build(from, to).should be_empty

    # Regression: conflict shifting re-derived the start and only the finish
    # was checked against the horizon, so a zero-duration vdate could begin at
    # exactly `to`
    blocker = VirtualDate.new("fixed")
    blocker.due << VirtualTime.new(hour: 9)
    blocker.duration = 1.hour
    blocker.fixed = true

    instant = VirtualDate.new("zero")
    instant.due << VirtualTime.new(hour: 9, minute: 30)
    instant.duration = 0.seconds

    horizon = Time.local(2024, 5, 10, 10, 0, 0)
    VirtualDate::Scheduler.new([blocker, instant])
      .build(Time.local(2024, 5, 10, 8), horizon)
      .map(&.vdate.id).should eq ["fixed"]
  end

  it "pins a VirtualTime deadline to the occurrence it came from" do
    blocker = VirtualDate.new("blocker")
    blocker.due << VirtualTime.new(hour: 16)
    blocker.duration = 70.minutes
    blocker.fixed = true

    task = VirtualDate.new("task")
    task.due << VirtualTime.new(hour: 16)
    task.duration = 30.minutes
    task.deadline = VirtualTime.new(hour: 17)

    # Regression: the deadline was re-materialized against each shifted start,
    # so once the task slipped past today's 17:00 it was handed tomorrow's and
    # could never miss one -- it was scheduled 10 minutes after its own deadline
    VirtualDate::Scheduler.new([blocker, task])
      .build(Time.local(2024, 5, 10, 8), Time.local(2024, 5, 11))
      .map(&.vdate.id).should eq ["blocker"]
  end

  it "does not place a vdate on a time it is omitted from" do
    blocker = VirtualDate.new("blocker")
    blocker.due << VirtualTime.new(hour: 10)
    blocker.duration = 2.hours
    blocker.fixed = true

    task = VirtualDate.new("task")
    task.due << VirtualTime.new(hour: 10)
    task.due << VirtualTime.new(hour: 12)
    task.duration = 30.minutes
    task.omit << VirtualTime.new(hour: 12)
    task.shift = nil

    # Regression: conflict shifting never consulted `omit`, so the 10:00
    # occurrence was pushed onto exactly the hour the vdate is omitted from --
    # the same instant its own 12:00 occurrence had just been refused for
    scheduled = VirtualDate::Scheduler.new([blocker, task])
      .build(Time.local(2024, 5, 10), Time.local(2024, 5, 11))

    scheduled.each do |instance|
      instance.vdate.omit_on?(instance.start).should_not be_true
    end
  end

  it "finds occurrences the window start would otherwise hide entirely" do
    vdate = VirtualDate.new("v")
    rule = VirtualTime.new(month: 4..7, minute: 2..42)
    rule.day_of_week = 4
    vdate.due << rule

    # Regression: the seeds for the refinement were derived from the answer the
    # first pass gave, which had already overshot into May -- the seed that
    # would have reached April lay behind it, so every Thursday of April was
    # dropped
    vdate.due_on?(Time.utc(2024, 4, 4, 0, 2, 0)).should be_true
    VirtualDate::Scheduler.new([vdate])
      .build(Time.utc(2024, 3, 29, 13, 1, 0), Time.utc(2024, 4, 6, 14, 1, 0))
      .map(&.start).first.should eq Time.utc(2024, 4, 4, 0, 2, 0)
  end

  it "starts every occurrence at its own first matching time" do
    starts = [0, 30, 53].map do |minute|
      vdate = VirtualDate.new("t")
      vdate.due << VirtualTime.new(hour: 9)
      vdate.parallel = 99

      VirtualDate::Scheduler.new([vdate])
        .build(Time.utc(2024, 5, 11, 9, minute, 0), Time.utc(2024, 5, 13), granularity: 1.hour)
        .map(&.start)
    end

    # The first occurrence begins where the window does, since its run was
    # already under way. Regression: only that head was canonicalized, so every
    # later occurrence inherited the window's own minute
    starts.map(&.first).should eq [
      Time.utc(2024, 5, 11, 9, 0, 0), Time.utc(2024, 5, 11, 9, 30, 0), Time.utc(2024, 5, 11, 9, 53, 0),
    ]
    starts.map(&.[1]).uniq!.should eq [Time.utc(2024, 5, 12, 9, 0, 0)]
  end

  it "tells occurrences apart by the gaps between the matching stretches" do
    vdate = VirtualDate.new("a")
    vdate.due << VirtualTime.new(minute: [0, 27])
    from = Time.utc(2024, 1, 1)

    # The two matching minutes are 26 minutes apart, further than the 15-minute
    # granularity. Regression: the run check walked from the last time the scan
    # landed on rather than from the end of its matching stretch, and reported
    # a bridge that is not there
    VirtualDate::Scheduler.new([vdate]).build(from, from + 1.hour, granularity: 15.minutes)
      .map(&.start).should eq [from, from + 27.minutes]
  end

  it "groups occurrences the same way at every granularity" do
    vdate = VirtualDate.new("b")
    vdate.due << VirtualTime.new(minute: [9, 44])
    vdate.parallel = 9999
    from = Time.utc(2024, 1, 1)

    # The stretches are 34 and 24 minutes apart, so they stay separate until
    # the granularity reaches 25, and all merge from 40 on. Regression: the
    # count wandered -- 25 at a granularity of 15, 1 at 20, 24 at 30
    counts = [1, 5, 10, 15, 20, 25, 30, 40, 60].map do |minutes|
      VirtualDate::Scheduler.new([vdate])
        .build(from, from + 1.day, granularity: minutes.minutes, max_candidates: 5000).size
    end

    counts.should eq [48, 48, 48, 48, 48, 25, 25, 1, 1]
    counts.each_cons_pair { |a, b| a.should be >= b }
  end

  it "carries a run to the end of its matching stretch, not its last sample" do
    vdate = VirtualDate.new("c")
    vdate.due << VirtualTime.new(hour: 20)
    vdate.due << VirtualTime.new(minute: 6)
    vdate.parallel = 9999
    from = Time.utc(2026, 11, 7)

    # `hour: 20` matches right up to 20:59:59, so the 21:06 stretch is seven
    # minutes later and belongs to the same occurrence at a granularity of 15.
    # Regression: the run recorded its last sample, 20:45, as its end
    starts = VirtualDate::Scheduler.new([vdate])
      .build(from, from + 1.day, granularity: 15.minutes, max_candidates: 5000)
      .map(&.start.to_s("%H:%M"))

    starts.should_not contain "21:06"
    starts.size.should eq 23
  end

  it "keeps an occurrence whose first sample lands past the window" do
    vdate = VirtualDate.new("d")
    vdate.due << VirtualTime.new(hour: 18)
    from = Time.utc(2022, 11, 4, 18, 26, 0)
    to = Time.utc(2022, 11, 5, 18, 26, 0)

    # The scan is phased from the window start, so the first sample of the
    # second day is 18:26 -- past `to`. Regression: the scan stopped there,
    # although the occurrence itself begins at 18:00, inside the window
    vdate.due_on?(Time.utc(2022, 11, 5, 18, 0, 0)).should be_true
    VirtualDate::Scheduler.new([vdate]).build(from, to, granularity: 30.minutes)
      .map(&.start).should eq [from, Time.utc(2022, 11, 5, 18, 0, 0)]
  end

  it "counts parallelism over the vdates sharing any flag" do
    both = VirtualDate.new("both")
    both.flags << "x"
    both.flags << "m"
    both.parallel = 2

    one = VirtualDate.new("one")
    one.flags << "x"
    one.parallel = 3

    other = VirtualDate.new("other")
    other.flags << "m"
    other.parallel = 3

    [both, one, other].each do |vdate|
      vdate.duration = 1.hour
      vdate.due << VirtualTime.new(hour: 10)
    end

    # `parallel` is documented as the number of overlapping vdates sharing at
    # least one flag. Regression: each flag was counted on its own, so "both"
    # overlapped two others -- one per flag -- while its limit was 2
    VirtualDate::Scheduler.new([both, one, other])
      .build(Time.utc(2024, 5, 1), Time.utc(2024, 5, 2), granularity: 1.hour)
      .map(&.start).should eq [Time.utc(2024, 5, 1, 10, 0), Time.utc(2024, 5, 1, 10, 0), Time.utc(2024, 5, 1, 11, 0)]
  end

  it "refuses a duration that runs off the end of the calendar" do
    vdate = VirtualDate.from_yaml "id: x\nduration: 9223372036854775807\n"
    vdate.due << VirtualTime.new(hour: 10)

    # Regression: the YAML layer accepted it and `Scheduled` then overflowed
    expect_raises(ArgumentError, /longer than the calendar/) do
      VirtualDate::Scheduler.new([vdate]).build(Time.utc(2024, 5, 1), Time.utc(2024, 5, 2))
    end
  end

  it "does not split an occurrence on a gap its own scan stride made" do
    vdate = VirtualDate.new("t")
    vdate.due << VirtualTime.new(minute: (26..55).step(3))
    vdate.parallel = 99

    from, to = Time.utc(2024, 5, 11, 12), Time.utc(2024, 5, 11, 15)

    # The matches are three minutes apart, so at any granularity of three
    # minutes or more they form one run per hour. Regression: the scan strides
    # by the granularity and can step over matches lying between its yields, so
    # a granularity of four or five turned three occurrences into fifteen
    counts = [3, 4, 5, 6, 10, 15].map do |minutes|
      VirtualDate::Scheduler.new([vdate]).build(from, to, granularity: minutes.minutes).size
    end

    counts.should eq [3, 3, 3, 3, 3, 3]
  end

  it "finds the repeated hour of a DST fall-back" do
    santiago = Time::Location.load("America/Santiago") # falls back 2024-04-07 00:00 -03:00
    vdate = VirtualDate.new("v")
    vdate.due << VirtualTime.new(minute: 32)
    vdate.parallel = 999

    from = Time.local(2024, 4, 6, 23, 58, 0, location: santiago)
    repeated = Time.utc(2024, 4, 7, 3, 32, 0).in(santiago) # 23:32 -04:00, the second time round

    # Regression: the head was materialized rather than stepped to, and only
    # stepping looks into the repeat -- materialization meets each wall clock
    # once
    vdate.due_on?(repeated).should be_true
    VirtualDate::Scheduler.new([vdate]).build(from, from + 5.hours)
      .map(&.start).first.should eq repeated
  end

  it "does not shift a vdate past its own end" do
    from, to = Time.utc(2024, 5, 11, 8), Time.utc(2024, 5, 11, 20)

    blocker = VirtualDate.new("blocker")
    blocker.fixed = true
    blocker.duration = 4.hours
    blocker.flags << "room"

    vdate = VirtualDate.new("v")
    vdate.duration = 30.minutes
    vdate.flags << "room"
    vdate.end = from + 10.minutes

    # Regression: conflict shifting had no bounds guard, so a vdate documented
    # as never on after 08:10 was scheduled at 12:00
    scheduled = VirtualDate::Scheduler.new([blocker, vdate]).build(from, to, granularity: 1.hour)
    scheduled.map(&.vdate.id).should eq ["blocker"]
  end

  it "finds the same occurrences whatever date the window starts on" do
    vdate = VirtualDate.new("december")
    vdate.due << VirtualTime.new(month: 12, hour: 2)

    # Regression: seeding the scan at the window start leaked its day-of-month
    # into a rule that names only a month, so asking from November 28 landed on
    # December 28 -- past the window -- and reported nothing at all
    late = VirtualDate::Scheduler.new([vdate])
      .build(Time.local(2023, 11, 28, 17, 3), Time.local(2023, 12, 1, 17, 3))

    late.map(&.start).should eq [Time.local(2023, 12, 1, 2, 0)]
  end

  it "finds occurrences on a day whose local midnight does not exist" do
    santiago = Time::Location.load("America/Santiago") # 2023-09-03 has no 00:00
    vdate = VirtualDate.new("odd-days")
    vdate.due << VirtualTime.new(day: (1..28).step(2))

    from = Time.local(2023, 9, 3, 11, 15, 0, location: santiago)

    # Regression: the scan was seeded at `#at_beginning_of_day`, which on such a
    # day answers with 23:00 of the day *before* -- and that 23:00 was then
    # filled into the rule's unconstrained hour
    vdate.due_on?(from).should be_true
    VirtualDate::Scheduler.new([vdate]).build(from, from + 1.hour)
      .map(&.start).should eq [from]
  end

  it "is not thrown off by a DST transition elsewhere in the window" do
    sydney = Time::Location.load("Australia/Sydney") # 2023-10-01 02:00 -> 03:00
    vdate = VirtualDate.new("mon")
    rule = VirtualTime.new(hour: 2..22)
    rule.day_of_week = 1
    vdate.due << rule

    # Monday the 2nd has no anomaly of its own. Regression: materializing over
    # Sunday's gap moved the hour to 3, and the day-of-week walk carried that
    # onto Monday
    VirtualDate::Scheduler.new([vdate])
      .build(Time.local(2023, 10, 1, 16, 24, 0, location: sydney), Time.local(2023, 10, 4, 16, 24, 0, location: sydney))
      .map(&.start).should eq [Time.local(2023, 10, 2, 2, 0, 0, location: sydney)]
  end

  it "starts a fall-back occurrence at the first of the repeated hours" do
    zagreb = Time::Location.load("Europe/Zagreb") # 2023-10-29 03:00 -> 02:00
    vdate = VirtualDate.new("sunday-two")
    rule = VirtualTime.new(hour: 2)
    rule.day_of_week = 7
    vdate.due << rule

    first = Time.utc(2023, 10, 29, 0, 0, 0).in(zagreb)  # 02:00 +02:00
    second = Time.utc(2023, 10, 29, 1, 0, 0).in(zagreb) # 02:00 +01:00
    vdate.due_on?(first).should be_true
    vdate.due_on?(second).should be_true

    # Both hours are due, so the run -- and the occurrence -- begins at the
    # first. Regression: the scheduler started it an hour late
    from = Time.local(2023, 10, 26, 5, 37, 0, location: zagreb)
    VirtualDate::Scheduler.new([vdate]).build(from, from + 3.days)
      .map(&.start).should eq [first]
  end

  it "finds the same occurrences whatever time of day the window starts" do
    vdate = VirtualDate.new("v")
    vdate.due << VirtualTime.new(hour: 14, minute: 8..11)
    vdate.duration = 30.minutes

    # Regression: the scan was seeded at the window start, and `VirtualTime`
    # fills a rule's unconstrained fields from its hint -- so a window opening
    # at 07:11 pulled that 11 into a rule that says nothing about minutes
    starts = [10, 11, 12].map do |minute|
      from = Time.local(2025, 1, 3, 7, minute, 0)
      VirtualDate::Scheduler.new([vdate]).build(from, from + 2.days).first.start
    end

    starts.uniq.should eq [Time.local(2025, 1, 3, 14, 8)]
  end

  it "coalesces contiguous due times across rules, not only within one" do
    vdate = VirtualDate.new("v")
    vdate.due << VirtualTime.new(hour: 10, minute: 0..29)
    vdate.due << VirtualTime.new(hour: 10, minute: 30..59)
    vdate.duration = 1.hour

    # The rules are OR-ed, so together they describe one continuous block.
    # Regression: each rule was coalesced on its own, yielding a second
    # occurrence that was then conflict-shifted to 11:00 -- an hour the vdate
    # is not due at at all
    VirtualDate::Scheduler.new([vdate])
      .build(Time.local(2024, 5, 10), Time.local(2024, 5, 11))
      .map(&.start).should eq [Time.local(2024, 5, 10, 10, 0)]
  end

  it "keeps a vdate within the parallelism of everyone it joins" do
    # "middle" overlaps both of the others, which do not overlap each other
    early = VirtualDate.new("early")
    early.due << VirtualTime.new(hour: 7)
    early.duration = 90.minutes
    early.flags << "meeting"
    early.parallel = 2

    middle = VirtualDate.new("middle")
    middle.due << VirtualTime.new(hour: 8)
    middle.duration = 90.minutes
    middle.flags << "meeting"
    middle.parallel = 2

    late = VirtualDate.new("late")
    late.due << VirtualTime.new(hour: 9)
    late.duration = 90.minutes
    late.flags << "meeting"
    late.parallel = 2

    scheduled = VirtualDate::Scheduler.new([early, middle, late])
      .build(Time.local(2024, 5, 10), Time.local(2024, 5, 11))

    # Regression: the check only counted what the candidate itself overlapped,
    # so "late" was accepted against "middle" alone -- leaving "middle"
    # overlapping two others at once, one past its own limit of 2
    scheduled.each do |instance|
      concurrent = scheduled.count do |other|
        !other.same?(instance) &&
          other.vdate.flags.includes?("meeting") &&
          instance.start < other.finish && other.start < instance.finish
      end
      (concurrent + 1).should be <= instance.vdate.parallel
    end
  end

  it "counts every message the explanation buffer drops" do
    explanation = VirtualDate::Explanation.new
    limit = VirtualDate::Explanation::MAX_LINES
    (limit + 1).times { |i| explanation.add "m#{i + 1}" }

    # Regression: the first overflow overwrote two real lines -- the one being
    # replaced and the one the notice took -- but counted only one
    explanation.dropped.should eq 2
    explanation.lines.count(&.starts_with?("m")).should eq limit - 1
    explanation.lines[-2].should contain "2 message(s) dropped"
    explanation.lines[-1].should eq "m#{limit + 1}"
  end

  it "omits ICS DTEND for a duration shorter than a second" do
    vdate = VirtualDate.new("ev")
    vdate.duration = 500.milliseconds
    ics = VirtualDate::ICS.export([VirtualDate::Scheduled.new(vdate, Time.utc(2023, 5, 10, 10, 0, 0))])

    # Regression: the guard compared the raw Times, but the format carries
    # whole seconds -- so a sub-second duration printed DTEND == DTSTART, which
    # RFC 5545 section 3.8.2.2 forbids
    ics.should contain "DTSTART:20230510T100000Z"
    ics.should_not contain "DTEND:"
  end

  it "does not resurrect a dependency removed in code" do
    vdate = VirtualDate.from_yaml "---\nid: b\nshift: false\ndepends_on:\n- a\n"
    index = {"a" => VirtualDate.new("a")}

    vdate.resolve_dependencies! index
    vdate.depends_on.map(&.id).should eq ["a"]

    vdate.depends_on.clear

    # Regression: the ids were left in place alongside the resolved objects, so
    # both saving and the next resolve put the dependency back
    vdate.to_yaml.should_not contain "- a"
    vdate.resolve_dependencies! index
    vdate.depends_on.should be_empty
  end

  it "answers rather than raising when a shift walks off the calendar" do
    vdate = VirtualDate.new("o")
    vdate.omit << VirtualTime.new(minute: 0..59)
    vdate.shift = 365.days
    vdate.max_shifts = 10_000

    # Regression: the search stepped past the end of the range `Time` can hold,
    # and the ArgumentError escaped from methods declared to return Bool and
    # Time | Bool | Nil
    vdate.resolve(Time.utc(2023, 1, 1)).should be_false
    vdate.on?(Time.utc(2023, 1, 1)).should be_false
  end

  it "reads back the extreme spans it writes" do
    # Regression: the sign was stripped before parsing and re-applied by
    # negating the finished span, and `Int64::MIN` -- what `Time::Span::MIN`
    # writes out as -- has no negation, so that one value could be written but
    # not read
    vdate = VirtualDate.new("x")
    vdate.shift = Time::Span::MIN
    VirtualDate.from_yaml(vdate.to_yaml).shift.should eq Time::Span::MIN

    vdate.shift = Time::Span::MAX
    VirtualDate.from_yaml(vdate.to_yaml).shift.should eq Time::Span::MAX
  end

  it "renders the extreme spans without overflowing" do
    # Regression: the whole part was rendered as a sign plus its magnitude, and
    # `Int64::MIN` -- the seconds of `Time::Span::MIN` -- has no positive
    # counterpart, so asking for one overflowed out of `#to_yaml`
    VirtualDate::SecondsSpan.to_scalar(Time::Span::MIN).should start_with "-9223372036854775808."
    VirtualDate::SecondsSpan.to_scalar(Time::Span::MAX).should start_with "9223372036854775807."
    VirtualDate::SecondsSpan.to_scalar(-500.milliseconds).should eq "-0.5"

    vdate = VirtualDate.new("m")
    vdate.shift = Time::Span::MIN
    vdate.to_yaml.should contain "shift: -9223372036854775808."
  end

  it "keeps the closing verdict when the explanation buffer fills up" do
    vdate = VirtualDate.new("v")
    vdate.due << VirtualTime.new(minute: 0)
    vdate.duration = 3.hours

    scheduled = VirtualDate::Scheduler.new([vdate])
      .build(Time.local(2024, 5, 10), Time.local(2024, 5, 11))

    # Regression: the overflow notice replaced the last line, so the verdict --
    # the only thing telling a deliberate over-subscription from a fault --
    # was the first thing lost
    scheduled.each do |instance|
      instance.explanation.lines.last.should contain "Scheduled at"
    end

    overflowed = scheduled.select { |instance| instance.explanation.dropped > 0 }
    overflowed.should_not be_empty
    overflowed.each do |instance|
      instance.explanation.lines.size.should eq VirtualDate::Explanation::MAX_LINES
      instance.explanation.lines[-2].should contain "dropped"
    end
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

    it "steps over a continuous run rather than through it" do
      # An always-matching rule is one giant contiguous run. It used to be
      # scanned a stride at a time, exhausting `MAX_RULE_ITERATIONS` over
      # seventy-five days at a 1-minute granularity; the scan now resumes past
      # each run's end, so the rule costs one step and yields one occurrence.
      # (The ceiling still guards a rule with more runs in the window than it
      # allows -- one a second over the same window -- but reaching it takes
      # a hundred thousand steps, too slow to assert here.)
      scheduler = VirtualDate::Scheduler.new
      vdate = VirtualDate.new
      vdate.due << VirtualTime.new
      scheduler.vdates << vdate

      scheduled = scheduler.build(Time.local(2023, 5, 1), Time.local(2023, 7, 15))
      scheduled.size.should eq 1
      scheduled.first.start.should eq Time.local(2023, 5, 1)
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

  it "keeps one continuous run one occurrence however long it goes on" do
    # Regression: the walk that carries a run's end forward gave up after a
    # fixed number of matching stretches and reported where it stopped as the
    # end. The scan then found itself more than a granularity past that and
    # opened a new run in the middle of a genuinely continuous one
    vd = VirtualDate.new "a"
    vd.due << VirtualTime.new(minute: (4..36).step(4))
    from = Time.utc(2025, 6, 14, 3, 0, 0)

    # :04 to :36 every hour: never more than 28 minutes without a match
    VirtualDate::Scheduler.new([vd]).build(from, from + 16.days, granularity: 30.minutes)
      .map(&.start).should eq [Time.utc(2025, 6, 14, 3, 4, 0)]

    # ... and the same defect made the count wander as the granularity coarsened
    other = VirtualDate.new "b"
    other.due << VirtualTime.new(minute: 5..46)
    start = Time.utc(2025, 3, 27, 21, 46, 0)
    sched = VirtualDate::Scheduler.new [other]

    counts = [20, 30, 45, 60].map do |minutes|
      sched.build(start, start + 42.hours, granularity: minutes.minutes).size
    end
    counts.should eq [1, 1, 1, 1]
  end

  it "does not split a run at a DST fall-back" do
    # Regression: a matching stretch's end was rebuilt from its wall clock, and
    # a fall-back gives one wall clock two instants -- of which the rebuild
    # takes the earlier. For a time in the second of the two the "end" came out
    # before the time itself, and the run was cut at the transition
    loc = Time::Location.load "America/Santiago"
    vd = VirtualDate.new "a"
    vd.due << VirtualTime.new

    from = Time.local(2025, 4, 5, 12, 0, 0, location: loc)
    to = Time.local(2025, 4, 7, 0, 0, 0, location: loc)
    VirtualDate::Scheduler.new([vd]).build(from, to, granularity: 1.hour)
      .map(&.start).should eq [from]

    # Newfoundland gives up half an hour rather than a whole one, and the
    # repeated stretch straddles an hour boundary rather than a day one
    sj = Time::Location.load "America/St_Johns"
    hourly = VirtualDate.new "b"
    hourly.due << VirtualTime.new(hour: 1)
    midnight = Time.local(2025, 11, 2, 0, 0, 0, location: sj)

    VirtualDate::Scheduler.new([hourly]).build(midnight, midnight + 26.hours, granularity: 5.minutes)
      .size.should eq 1
  end

  it "seeds the occurrence search past a DST gap rather than behind it" do
    # Regression: the seeds the search re-asks from were built with
    # `Time.local`, which for a wall clock a spring-forward swallowed hands
    # back a neighbouring one on the day before. A rule's unconstrained fields
    # are filled from the hint, so that seed sent the search to 23:00 instead
    # of to the start of the day it stood for, and the day's earlier
    # occurrences were dropped
    loc = Time::Location.load "America/Santiago"
    vd = VirtualDate.new "a"
    vt = VirtualTime.new
    vt.day_of_week = 7
    vt.minute = 49
    vd.due << vt

    from = Time.local(2025, 9, 6, 21, 0, 0, location: loc)
    to = from + 27.hours
    starts = VirtualDate::Scheduler.new([vd])
      .build(from, to, granularity: 1.minute, max_candidates: 10_000).map(&.start)

    # Sunday 2025-09-07 has no hour 0 in Santiago, so :49 of hours 1 through 23
    starts.size.should eq 23
    starts.first.should eq Time.local(2025, 9, 7, 1, 49, 0, location: loc)
    starts.each { |occurrence| vd.due_on?(occurrence).should be_true }
  end

  it "treats a duration that runs off the calendar as one that does not fit" do
    # Regression: `#validate_vdates!` accepts any duration the calendar itself
    # can hold, but adding one to a start in 2025 overflowed, and the failure
    # escaped `#build` as an opaque error rather than the vdate simply not
    # fitting the window
    vd = VirtualDate.new "a"
    vd.duration = VirtualDate::Scheduler::MAX_DURATION

    VirtualDate::Scheduler.new([vd]).build(Time.utc(2025, 1, 1), Time.utc(2025, 1, 2)).should be_empty
  end

  it "treats a deadline that names no real time as one that cannot be met" do
    # Regression: every other `VirtualTime`-valued field tolerates a rule no
    # date satisfies by never matching, but the deadline was materialized
    # unguarded and took `#build` down with it
    vd = VirtualDate.new "a"
    vd.duration = 1.hour
    vd.deadline = VirtualTime.new(month: 2, day: 30)

    VirtualDate::Scheduler.new([vd]).build(Time.utc(2025, 1, 1), Time.utc(2025, 1, 2)).should be_empty
  end

  it "reads a matching stretch's end on the side of a fall-back it belongs to" do
    # Regression: the end was rebuilt from its wall clock, and which of a
    # fall-back's two instants that lands on is the zone's own business --
    # Europe/Zagreb answers with the later, America/New_York with the earlier.
    # An end a whole fold too late swallowed every occurrence in between
    loc = Time::Location.load "Europe/Zagreb"
    vd = VirtualDate.new "x"
    vt = VirtualTime.new
    vt.minute = [0, 30]
    vt.second = 0
    vd.due << vt

    from = Time.local(2023, 10, 29, 1, 0, 0, location: loc)
    to = Time.local(2023, 10, 29, 4, 0, 0, location: loc)
    starts = VirtualDate::Scheduler.new([vd])
      .build(from, to, granularity: 1.minute, max_candidates: 1000).map(&.start)

    # Half-hourly across a repeated hour: eight, not six
    starts.size.should eq 8
    starts.each { |occurrence| vd.due_on?(occurrence).should be_true }
    starts.should contain Time.local(2023, 10, 29, 2, 30, 0, location: loc)
  end

  it "does not drop an occurrence the stride passed over" do
    # Regression: the search can reach back past the stride's own yield, and
    # the run opened there need not reach as far as it. The yield was then
    # neither its own run nor part of that one, and went missing
    loc = Time::Location.load "America/Santiago"
    vd = VirtualDate.new "x"
    vt = VirtualTime.new
    vt.hour = 1
    vt.minute = [0, 56]
    vd.due << vt

    from = Time.local(2023, 9, 2, 1, 0, 0, location: loc)
    to = Time.local(2023, 9, 3, 2, 0, 0, location: loc)
    starts = VirtualDate::Scheduler.new([vd])
      .build(from, to, granularity: 5.minutes, max_candidates: 1000).map(&.start)

    starts.size.should eq 4
    starts.last.should eq Time.local(2023, 9, 3, 1, 56, 0, location: loc)
  end

  it "lets an `on` override beat the scheduler's bounds and omit guards too" do
    # `#on` is documented to take precedence over begin/end/due/omit, and
    # `#strict_on?` returns it before consulting anything else. Regression: the
    # scheduler re-applied both guards to the start `#resolve` handed it, so a
    # vdate every query API called on was dropped from the schedule
    from = Time.utc(2023, 5, 10)
    to = Time.utc(2023, 5, 11)
    at_ten = Time.utc(2023, 5, 10, 10)

    bounded = VirtualDate.new "a"
    due = VirtualTime.new
    due.hour = 10
    bounded.due << due
    bounded.on = true
    bounded.begin = Time.utc(2024, 1, 1)

    bounded.strict_on?(at_ten).should be_true
    VirtualDate::Scheduler.new([bounded]).build(from, to).map(&.start).should eq [at_ten]

    omitted = VirtualDate.new "b"
    due2 = VirtualTime.new
    due2.hour = 10
    omitted.due << due2
    omit = VirtualTime.new
    omit.hour = 10
    omitted.omit << omit
    omitted.on = true

    omitted.strict_on?(at_ten).should be_true
    VirtualDate::Scheduler.new([omitted]).build(from, to).map(&.start).should eq [at_ten]
  end

  it "gives staggered occurrences distinct ICS UIDs and honours max_candidates" do
    # Regression: the UID's stamp carries whole seconds, which a sub-second
    # `#stagger` can place several occurrences inside -- RFC 5545 3.8.4.7 wants
    # one UID per component
    vd = VirtualDate.new "meeting"
    due = VirtualTime.new
    due.hour = 10
    due.minute = 0
    due.second = 0
    vd.due << due
    vd.parallel = 3
    vd.stagger = 300.milliseconds

    scheduled = VirtualDate::Scheduler.new([vd]).build(Time.utc(2023, 5, 10), Time.utc(2023, 5, 11))
    scheduled.size.should eq 3

    uids = VirtualDate::ICS.export(scheduled).split("\r\n").select(&.starts_with?("UID:"))
    uids.size.should eq 3
    uids.uniq.size.should eq 3

    # A start on a whole second keeps the UID it always had
    plain = VirtualDate.new "plain"
    plain.due << due
    one = VirtualDate::Scheduler.new([plain]).build(Time.utc(2023, 5, 10), Time.utc(2023, 5, 11))
    VirtualDate::ICS.export(one).should contain "UID:plain-#{one.first.start.to_unix}@virtualdate"

    # Regression: the cap was tested only after a whole stagger group had been
    # emitted, so it could be overshot by `parallel - 1`
    capped = VirtualDate.new "a"
    every_hour = VirtualTime.new
    every_hour.minute = 0
    capped.due << every_hour
    capped.parallel = 3
    capped.stagger = 10.minutes

    VirtualDate::Scheduler.new([capped])
      .build(Time.utc(2023, 5, 1), Time.utc(2023, 5, 3), max_candidates: 5).size.should eq 5
  end

  it "keeps a run's carried-forward end when the scan walks away from it" do
    # Regression: the walk that carries a run's end forward recorded it only
    # where the run went on to absorb the scan's next yield. Where it did not,
    # the stale end stood -- putting a gap in front of the next occurrence that
    # the rules do not have, and making a coarser granularity report *more*
    # occurrences than a finer one
    vd = VirtualDate.new "a"
    seconds = VirtualTime.new
    seconds.hour = 10
    seconds.second = 22..53
    vd.due << seconds
    hourly = VirtualTime.new
    hourly.minute = 4
    vd.due << hourly

    from = Time.utc 2024, 5, 15
    to = Time.utc 2024, 5, 16
    scheduler = VirtualDate::Scheduler.new [vd]

    counts = [5, 12, 15, 30].map do |minutes|
      scheduler.build(from, to, granularity: minutes.minutes, max_candidates: 10_000).size
    end
    # The hour-10 block ends at 10:59:53, and 11:04 is four minutes later
    counts.should eq [23, 23, 23, 23]
  end

  it "does not walk a rule that matches continuously value by value" do
    # Regression: a `#millisecond` rule with no `#nanosecond` beside it was
    # taken to match for a single instant, so the run walk stepped through it a
    # nanosecond at a time -- half a minute of work per day of window. A field
    # letting its whole domain through does not shorten a stretch at all
    vd = VirtualDate.new "daily"
    vt = VirtualTime.new
    vt.hour = 9
    vt.minute = 0
    vt.millisecond = 0
    vd.due << vt

    started = Time.instant
    built = VirtualDate::Scheduler.new([vd])
      .build(Time.utc(2024, 1, 1), Time.utc(2024, 1, 2), granularity: 1.minute)
    elapsed = Time.instant - started

    built.size.should eq 1
    elapsed.should be < 5.seconds

    wide = VirtualDate.new "wide"
    every = VirtualTime.new
    every.hour = 9
    every.second = 0..59
    wide.due << every

    started = Time.instant
    VirtualDate::Scheduler.new([wide]).build(Time.utc(2024, 1, 1), Time.utc(2024, 1, 8), granularity: 1.hour)
    (Time.instant - started).should be < 5.seconds
  end

  it "starts an occurrence at the first matching instant inside a fall-back" do
    # Regression: the seeds the search re-asks from are built from wall-clock
    # fields, and a fall-back gives one wall clock two instants. Where the zone
    # handed back the pass the search was not in, every seed sat behind the
    # floor and the overshoot they exist to correct went uncorrected
    loc = Time::Location.load "America/New_York"
    vd = VirtualDate.new "a"
    vt = VirtualTime.new
    vt.minute = [7, 53]
    vd.due << vt

    from = Time.local(2024, 11, 3, 0, 0, 0, location: loc)
    to = Time.local(2024, 11, 3, 3, 0, 0, location: loc)
    starts = VirtualDate::Scheduler.new([vd]).build(from, to, granularity: 7.seconds).map(&.start)

    starts.size.should eq 8
    starts.each do |occurrence|
      vd.due_on?(occurrence).should be_true
      # Nothing may match the second before an occurrence starts
      vd.due_on?(occurrence - 1.second).should be_falsey
    end
  end

  it "does not cut a stretch that legitimately spans a transition" do
    # A local day can be twenty-five hours long and a Lord Howe local hour
    # ninety minutes; neither is a fall-back resolving a wall clock to the
    # wrong side, and the correction for that must leave them alone
    zagreb = Time::Location.load "Europe/Zagreb"
    always = VirtualDate.new "a"
    always.due << VirtualTime.new

    long_day = Time.local(2023, 10, 28, 12, 0, 0, location: zagreb)
    VirtualDate::Scheduler.new([always])
      .build(long_day, long_day + 48.hours, granularity: 1.minute).size.should eq 1

    lord_howe = Time::Location.load "Australia/Lord_Howe"
    hourly = VirtualDate.new "b"
    hour_one = VirtualTime.new
    hour_one.hour = 1
    hourly.due << hour_one

    long_hour = Time.local(2023, 4, 1, 12, 0, 0, location: lord_howe)
    VirtualDate::Scheduler.new([hourly])
      .build(long_hour, long_hour + 48.hours, granularity: 1.minute).size.should eq 2
  end

  it "starts a sub-second occurrence at the start of its matching stretch" do
    # Regression: the seeds the search re-asks from ran no finer than a minute,
    # so a rule constraining `#second` had nothing that reached the start of
    # its own matching stretch and whatever fraction the floor carried leaked
    # into the answer -- half a second here, and up to nine tenths of one on
    # every occurrence of a stepped rule
    vd = VirtualDate.new "v"
    listed = VirtualTime.new
    listed.second = [4, 15]
    vd.due << listed

    from = Time.utc 2023, 1, 1, 0, 0, 5, nanosecond: 500_000_000
    VirtualDate::Scheduler.new([vd]).build(from, from + 30.seconds, granularity: 1.minute)
      .map(&.start).should eq [Time.utc(2023, 1, 1, 0, 0, 15)]

    stepped = VirtualDate.new "w"
    every_ten = VirtualTime.new
    every_ten.second = (0...60).step(10)
    stepped.due << every_ten

    at = Time.utc 2023, 5, 1
    VirtualDate::Scheduler.new([stepped]).build(at, at + 1.minute, granularity: 1900.milliseconds)
      .map(&.start).should eq (0..5).map { |i| at + (i * 10).seconds }
  end

  it "truncates at max_candidates instead of punching holes in the middle" do
    # Regression: the cap was counted across the due rules taken together, so
    # once the first had spent it every later rule contributed a single run --
    # and the merged answer dropped occurrences that come *before* ones it kept
    vd = VirtualDate.new "x"
    on_the_hour = VirtualTime.new
    on_the_hour.minute = 0
    vd.due << on_the_hour
    half_past = VirtualTime.new
    half_past.minute = 30
    vd.due << half_past

    from = Time.utc 2023, 5, 1
    to = from + 1.day
    scheduler = VirtualDate::Scheduler.new [vd]

    full = scheduler.build(from, to, granularity: 1.minute, max_candidates: 1000).map(&.start)
    capped = scheduler.build(from, to, granularity: 1.minute, max_candidates: 5).map(&.start)

    capped.should eq full.first(5)
  end

  it "loads a vdate written as a YAML alias" do
    # Regression: `#to_yaml` emits an anchor and an alias for a vdate that
    # appears twice, and the validator then refused its own output -- as it
    # refused any hand-written document sharing a definition that way
    vd = VirtualDate.new "a"
    document = {"schema_version" => 2, "vdates" => [vd, vd]}.to_yaml

    VirtualDate::VirtualDateFile.load(document).map(&.id).should eq ["a", "a"]
  end

  it "raises the budget until the capped list is a genuine prefix" do
    # Regression: each rule got its own budget of `max_candidates` runs, so a
    # dense rule spent its budget early while a broad one scanned on -- and the
    # merged answer kept late occurrences while dropping earlier ones. Raising
    # the limit did not add them back either
    vd = VirtualDate.new "x"
    hourly = VirtualTime.new
    hourly.minute = 58
    vd.due << hourly
    morning = VirtualTime.new
    morning.hour = 4..11
    vd.due << morning

    from = Time.utc 2023, 3, 24, 2
    to = Time.utc 2023, 3, 26, 2
    scheduler = VirtualDate::Scheduler.new [vd]

    full = scheduler.build(from, to, granularity: 5.minutes, max_candidates: 1000).map(&.start)
    [3, 4, 5].each do |cap|
      scheduler.build(from, to, granularity: 5.minutes, max_candidates: cap)
        .map(&.start).should eq full.first(cap)
    end
  end

  it "counts a contiguous stretch of allowed values as one" do
    # Regression: a rule's matching stretch was cut at its finest constrained
    # field's own unit, so consecutive allowed values counted as one stretch
    # each -- half a billion of them for `nanosecond: 0..500_000_000`, which
    # the run walk then stepped through one at a time
    vd = VirtualDate.new "x"
    half = VirtualTime.new
    half.nanosecond = 0..500_000_000
    vd.due << half

    from = Time.utc 2023, 5, 1
    started = Time.instant
    built = VirtualDate::Scheduler.new([vd]).build(from, from + 4.milliseconds, granularity: 1.millisecond)
    elapsed = Time.instant - started

    built.size.should eq 1
    built.first.start.should eq from
    elapsed.should be < 1.second
  end

  it "scans office hours over a year without exhausting the iteration limit" do
    # Regression: the scan strode through every matching minute rather than
    # over each run, so the ceiling tracked matching *duration* -- and any
    # daily nine-to-five rule broke past roughly six months at the default
    # granularity
    vd = VirtualDate.new "x"
    office = VirtualTime.new
    office.hour = 9..17
    vd.due << office

    from = Time.utc 2023, 5, 1
    VirtualDate::Scheduler.new([vd]).build(from, from + 365.days, granularity: 1.minute)
      .size.should eq 365
  end

  it "cuts a matching stretch where a transition inside it cuts the match" do
    # Regression: a stretch's end was rebuilt from a wall clock, which assumes
    # the stretch runs uninterrupted -- but a zone whose transition falls
    # inside one (Newfoundland at :01, Chatham at :45) breaks that. The rebuilt
    # end could even precede the stretch's own start, and the scan never
    # recovered
    st_johns = Time::Location.load "America/St_Johns"
    quarter = VirtualDate.new "v"
    quarter_hour = VirtualTime.new
    quarter_hour.minute = 0..15
    quarter.due << quarter_hour

    # 2007-03-11: clocks went 00:01 -03:30 to 01:01 -02:30
    starts = VirtualDate::Scheduler.new([quarter]).build(
      Time.local(2007, 3, 10, 20, 1, 0, location: st_johns),
      Time.local(2007, 3, 11, 6, 1, 0, location: st_johns), granularity: 1.minute).map(&.start)
    starts.size.should eq 10
    starts.each { |occurrence| quarter.due_on?(occurrence).should be_true }

    # A fall-back that repeats matching time is two occurrences, not one
    chatham = Time::Location.load "Pacific/Chatham"
    hourly = VirtualDate.new "v"
    hour_three = VirtualTime.new
    hour_three.hour = 3
    hourly.due << hour_three

    VirtualDate::Scheduler.new([hourly]).build(
      Time.local(2023, 4, 2, 0, 0, 0, location: chatham),
      Time.local(2023, 4, 3, 0, 0, 0, location: chatham), granularity: 1.minute).size.should eq 2

    # ... and a run the transition does not interrupt stays one
    wide = VirtualDate.new "v"
    most_of_the_hour = VirtualTime.new
    most_of_the_hour.minute = 0..45
    wide.due << most_of_the_hour

    VirtualDate::Scheduler.new([wide]).build(
      Time.local(2004, 4, 3, 22, 1, 0, location: st_johns),
      Time.local(2004, 4, 4, 11, 1, 0, location: st_johns), granularity: 1.hour).size.should eq 1
  end

  it "does not reorder a rule's own list of allowed values" do
    # Regression: `Array#to_a` hands back the array itself, so sorting it to
    # measure a contiguous stretch reordered the caller's own rule -- and with
    # it the vdate's serialized form
    minutes = [30, 0, 45]
    vt = VirtualTime.new
    vt.hour = 10
    vt.minute = minutes
    vd = VirtualDate.new "v"
    vd.due << vt

    before = vt.to_yaml
    from = Time.utc 2023, 1, 1
    VirtualDate::Scheduler.new([vd]).build(from, from + 1.day, granularity: 1.minute)

    minutes.should eq [30, 0, 45]
    vt.to_yaml.should eq before
  end

  it "resumes a run at the start of the stretch on the far side of a transition" do
    # Regression: the run walk resumed with `#succ` directly, whose
    # unconstrained fields are filled from the hint it is handed -- and where a
    # transition had cut the stretch short, that hint carries the transition's
    # own clock. The run resumed in the middle of itself, and was reported as a
    # second occurrence starting at an instant no stretch begins at
    chatham = Time::Location.load "Pacific/Chatham"
    vd = VirtualDate.new "v"
    hour_three = VirtualTime.new
    hour_three.hour = 3
    vd.due << hour_three

    from = Time.local 2022, 4, 1, 19, 45, 0, location: chatham
    to = Time.local 2022, 4, 5, 18, 45, 0, location: chatham
    scheduler = VirtualDate::Scheduler.new [vd]

    # The two stretches of 2022-04-03 are 15 minutes apart, so anything coarser
    # coalesces them; a coarser granularity may never report more occurrences
    scheduler.build(from, to, granularity: 1.hour).map(&.start).size.should eq 4
    scheduler.build(from, to, granularity: 30.minutes).map(&.start).size.should eq 4
    scheduler.build(from, to, granularity: 5.minutes).map(&.start).size.should eq 5
  end

  it "reads a millisecond rule and a nanosecond rule as bounding one stretch" do
    # Regression: both name an offset within the same second rather than one
    # nested in the other, but only the finer of the two decided how far a
    # stretch ran -- so the end overstated it, the gap fell inside the
    # granularity, and two of three occurrences merged away
    vd = VirtualDate.new "v"
    vt = VirtualTime.new millisecond: 0, nanosecond: (0..500_000_000)
    vd.due << vt

    from = Time.utc 2023, 1, 1
    VirtualDate::Scheduler.new([vd]).build(from, from + 3.seconds, granularity: 600.milliseconds)
      .map(&.start).should eq [from, from + 1.second, from + 2.seconds]
  end

  it "lets a pattern naming no real time simply not match" do
    # Regression: `#strict_on?` materialized a `VirtualTime` argument to
    # compare it against an absolute bound, and one naming no real date took
    # the call down with it -- where every `#matches?`-based predicate beside
    # it lets such a pattern never match
    vd = VirtualDate.new "v"
    february = VirtualTime.new month: 2
    vd.due << february

    impossible = VirtualTime.new month: 2, day: 30
    vd.due_on?(impossible).should be_true
    vd.strict_on?(impossible).should be_nil
    vd.resolve(impossible).should be_nil
  end

  it "gives staggered candidates the same omit exemptions as placed ones" do
    # Regression: the staggered expansion dropped anything falling on an
    # omitted time outright, while the placement guard beside it makes two
    # exemptions -- `shift = true`, the policy that keeps an omitted time, and
    # a non-nil `#on`, which overrides omission. Turning `#stagger` on decided
    # whether an occurrence existed at all
    from = Time.utc 2024, 5, 1
    to = Time.utc 2024, 5, 2

    kept = VirtualDate.new "a"
    at_ten = VirtualTime.new hour: 10
    kept.due << at_ten
    kept.omit << VirtualTime.new(hour: 10)
    kept.shift = true
    kept.duration = 0.seconds
    kept.parallel = 3

    kept.resolve(Time.utc(2024, 5, 1, 10)).should be_true
    VirtualDate::Scheduler.new([kept]).build(from, to, granularity: 1.hour)
      .map(&.start).should eq [Time.utc(2024, 5, 1, 10)]

    kept.stagger = 30.minutes
    VirtualDate::Scheduler.new([kept]).build(from, to, granularity: 1.hour).map(&.start)
      .should eq [Time.utc(2024, 5, 1, 10), Time.utc(2024, 5, 1, 10, 30), Time.utc(2024, 5, 1, 11)]

    overridden = VirtualDate.new "b"
    overridden.due << at_ten
    overridden.omit << VirtualTime.new(hour: 11)
    overridden.on = true
    overridden.duration = 0.seconds
    overridden.parallel = 3
    overridden.stagger = 30.minutes

    VirtualDate::Scheduler.new([overridden]).build(from, to, granularity: 1.hour).map(&.start)
      .should eq [Time.utc(2024, 5, 1, 10), Time.utc(2024, 5, 1, 10, 30), Time.utc(2024, 5, 1, 11)]
  end

  it "survives the edges of the calendar" do
    # Regression: the resume floor was built without a guard, so a granularity
    # that carried it past the last instant the calendar holds took `#build`
    # down with an error saying nothing about the vdate or the window
    late = VirtualDate.new "b"
    late.due << VirtualTime.new(year: 9999, month: 3, day: 1)
    VirtualDate::Scheduler.new([late]).build(
      Time.utc(9999, 1, 1), Time.utc(9999, 6, 1), granularity: 365.days)
      .map(&.start).should eq [Time.utc(9999, 3, 1)]

    # ... and the first instant the calendar holds has nothing before it to ask
    # from, which used to drop every due rule silently
    early = VirtualDate.new "a"
    every_midnight = VirtualTime.new
    every_midnight.hour = 0
    early.due << every_midnight
    VirtualDate::Scheduler.new([early]).build(Time.utc(1, 1, 1), Time.utc(1, 1, 5))
      .map(&.start).size.should eq 4

    # The largest legal cap is the natural spelling of "no cap"
    capped = VirtualDate.new "c"
    at_ten = VirtualTime.new
    at_ten.hour = 10
    capped.due << at_ten
    VirtualDate::Scheduler.new([capped])
      .build(Time.utc(2024, 1, 1), Time.utc(2024, 1, 5), max_candidates: Int32::MAX).size.should eq 4
  end

  it "schedules a proc-valued rule the same as the list it stands for" do
    # Regression: the scan got the first matching hour, then the resume raised
    # and the rule was taken as finished -- so a proc rule produced a wrong set
    # of occurrences, not merely fewer. Root cause was in VirtualTime
    loc = Time::Location.load "America/St_Johns"
    from = Time.local 2025, 5, 2, 10, 33, 0, location: loc
    to = from + 25.hours

    procs = VirtualTime.new
    procs.hour = VirtualTime::VirtualProc.new { |value| value % 3 == 0 }
    procs.minute = VirtualTime::VirtualProc.new(&.even?)

    lists = VirtualTime.new
    lists.hour = (0..23).select { |value| value % 3 == 0 }
    lists.minute = (0..59).select(&.even?)

    counted = [procs, lists].map do |rule|
      vd = VirtualDate.new "q"
      vd.due << rule
      VirtualDate::Scheduler.new([vd])
        .build(from, to, granularity: 1.minute, max_candidates: 100_000).size
    end
    counted.first.should eq counted.last
    counted.first.should eq 240
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
