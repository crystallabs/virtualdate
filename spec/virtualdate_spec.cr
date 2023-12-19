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

    vd4 = VirtualTime.from_time(Time.parse_local("2017-3-15", "%F")).nil_time!
    vd.due << vd4
    vd.due_on?(date).should be_true

    vd5 = VirtualTime.from_time(Time.parse_local("12:13:14", "%X")).nil_date!
    vd.due = [vd5]
    vd.due_on?(date).should be_true

    vd6 = VirtualTime.from_time(Time.parse_local("12:13:15", "%X")).nil_date!
    vd.due = [vd6]
    vd.due_on?(date).should be_nil

    date = Time.parse_local("2017-3-15 1:2:3", "%F %X")
    vd7 = VirtualTime.from_time(Time.parse_local("2017-3-18", "%F")).nil_time!
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
