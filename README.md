[![Linux CI](https://github.com/crystallabs/virtualdate/workflows/Linux%20CI/badge.svg)](https://github.com/crystallabs/virtualdate/actions?query=workflow%3A%22Linux+CI%22+event%3Apush+branch%3Amaster)
[![Version](https://img.shields.io/github/tag/crystallabs/virtualdate.svg?maxAge=360)](https://github.com/crystallabs/virtualdate/releases/latest)
[![License](https://img.shields.io/github/license/crystallabs/virtualdate.svg)](https://github.com/crystallabs/virtualdate/blob/master/LICENSE)

## Installation

Add the following to your application's "shard.yml":

```
 dependencies:
   virtualdate:
     github: crystallabs/virtualdate
     version: ~> 1.0
```

And run `shards install` or just `shards`.

## Introduction

VirtualDate is a companion project to [virtualtime](https://github.com/crystallabs/virtualtime).

VirtualDate implements the high-level part, the actual items one might want to schedule, with
additional options and fields, and with the support for complex and flexible, and often recurring,
time/event scheduling.

The class is intentionally called `VirtualDate` not to imply a particular type or purpose
(i.e. it can be a task, event, recurring appointment, reminder, etc.)

Likewise, it does not contain any task/event-specific properties -- it only concerns itself with
the scheduling aspect.

## Usage

Comments in the code hopefully show how to use it:

```crystal
vd = VirtualDate.new

# Create a VirtualTime that matches every other day from Mar 10 to Mar 20:
march = VirtualTime.new
march.month = 3
march.day = (10..20).step 2

# Add this VirtualTime as a due date to our VirtualDate:
vd.due << march

# Create a VirtualTime that matches Mar 20 specifically, and omit the event
# on that particular day:
march_20 = VirtualTime.new
march_20.month = 3
march_20.day = 20
vd.omit << march_20

# If event falls on an omitted date, try rescheduling it for 2 days later:
vd.shift = 2.days
```

Now we can check when the VD is due and when it is not (ignore the `Time[]` syntax):

```crystal
# VirtualDate is not due on Feb 15, 2017 because that's not in March:
p vd.on?( Time["2017-02-15"]) # ==> false

# VirtualDate is not due on Mar 15, 2017 because that's not a day of
# March 10, 12, 14, 16, 18, or 20:
p vd.on?( Time["2017-03-15"]) # ==> false

# VirtualDate is due on Mar 16, 2017:
p vd.on?( Time["2017-03-16"]) # ==> true

# VirtualDate is due on Mar 18, 2017:
p vd.on?( Time["2017-03-18"]) # ==> true

# And it is due on any Mar 18, doesn't need to be in 2017:
p vd.on?( Time["2023-03-18"]) # ==> true

# But it is not due on Mar 20, 2017, because that date is omitted, and the system will give us
# a span of time (offset) when it can be scheduled. Based on our reschedule settings above, this
# will be a span for 2 days later.
p vd.on?( Time["2017-03-20"]) # ==> #<Time::Span @span=2.00:00:00>

# Asking whether the VD is due on the rescheduled date (Mar 22) will tell us no, because currently
# rescheduled dates are not counted as due/on dates:
p vd.on?( Time["2017-03-22"]) # ==> nil
```

Here's another example of a VirtualDate that is due on every other day in March, but if it falls
on a weekend it is ignored:

```crystal
vd = VirtualDate.new

# Create a VirtualTime that matches every other (every even) day in March:
march = VirtualTime.new
march.month = 3
march.day = (2..31).step 2
vd.due << march

# But on weekends it should not be scheduled:
weekend = VirtualTime.new
weekend.day_of_week = [6,7]
vd.omit << weekend

# If item falls on an omitted day, consider it as not scheduled (don't
# try rescheduling):
vd.shift = nil # or 'false' to explicitly say it's omitted; false is the default value

# Now let's check when it is due and when not in March:
# (Do this by printing a list for days 1 - 31):
(1..31).each do |d|
  p "Mar-#{d} = #{vd.on?( Time.local(2023, 3, d)}"
end
```

## More Information

For a realistic, schedulable item it is not enough to have just one `VirtualTime` that controls
when that item is active/scheduled (or simply "on" in VT's terminology).

At a minimum, you might want to specify multiple `VirtualTimes` at which the item is on, and
specify an omit list when an item should not be on (e.g. on weekends or public holidays).

Also, if an item would fall on an omitted date or time, then it might be desired to automatically
reschedule it by shifting it by certain amount of time before or after the original time.

Thus, altogether class `VirtualDate` has the following properties:

- `begin`, an absolute start time, before which the VirtualDate is never on
- `end`, an absolute end time, after which the VirtualDate is never on
- `due`, a list of VirtualTimes on which the VirtualDate is on
- `omit`, a list of VirtualTimes on which the VirtualDate is omitted (not on)
- `shift`, governing whether, and by how much time, the VirtualDate should be shifted if it falls on an omitted date/time
- `max_shifts`, a maximum number of shift attempts to make in an attempt to find a suitable rescheduled date and time
- `max_shift`, a maximum Time::Span by which the VirtualDate can be shifted before being considered unschedulable
- `on`, a property which overrides all other VirtualDate's fields and calculations and directly sets VirtualDate's `on` status
- `duration`
- `flags`, i.e. categories/groups/tags
- `parallel`, how many vdates from the same `flag` group can be scheduled in parallel
- `stagger`, if scheduling in parallel, by how much time to stagger/sequence/order each parallel vdate
- `priority`, higher = schedule first
- `fixed`, whether this vdate is fixed/immovable
- `id`, unique ID (string)
- `depends_on`, list of vdates it depends on
- `deadline`, will fail to schedule if it can't complete before this

If the 's list of due dates is empty, it is considered as always "on".
If the item's list of omit dates is empty, it is considered as never omitted.

A value of `shift` can be nil, `Boolean`, or`Time::Span`.

- Nil instructs that event should not be rescheduled, and to simply treat it as not scheduled on a particular date
- A `Boolean` explicitly marks the item as scheduled or rejected when it falls on an omitted time
- A `Time::Span` implies that rescheduling should be attempted and controls by how much time the item should be shifted (into the past or future) on every attempt

If there are multiple `VirtualTime`s set for a field, e.g. for `due` date, the matches are logically OR-ed;
one match is enough for the field to match.

### Start and End Dates

In addition to absolute `Time` values, `start` and `end` can be `VirtualTime`s. When they are set to those types,
they don't act like usual to confine VD's scheduling to the from-to period, but the actual times asked must
`match?` both of them (if they are specified) in the usual, VT's sense.

In other words, to have a VD active during say, summer months, you could define `start = VirtualTime.new month: 4..10`,
and would not need any `stop` value.

This functionality is quite redundant with the usual `due` and `omit` dates, is highly experimental,
and probably not something to be used.

## Scheduling

There is support for loading/saving schedule to YAML and exporting to iCal.


# Other Projects

List of interesting or similar projects in no particular order:

- https://dianne.skoll.ca/projects/remind/ - a sophisticated calendar and alarm program
