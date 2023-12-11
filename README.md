[![Linux CI](https://github.com/crystallabs/virtualdate/workflows/Linux%20CI/badge.svg)](https://github.com/crystallabs/virtualdate/actions?query=workflow%3A%22Linux+CI%22+event%3Apush+branch%3Amaster)
[![Version](https://img.shields.io/github/tag/crystallabs/virtualdate.svg?maxAge=360)](https://github.com/crystallabs/virtualdate/releases/latest)
[![License](https://img.shields.io/github/license/crystallabs/virtualdate.svg)](https://github.com/crystallabs/virtualdate/blob/master/LICENSE)

VirtualDate is a time scheduling component for Crystal. It is a sibling project of [virtualtime](https://github.com/crystallabs/virtualtime).
It is used for complex and flexible, and often recurring, time/event scheduling.

VirtualTime from the other shard implements the low-level time matching component.
VirtualDate implements the high-level part, the actual items one might want to schedule.

# Installation

Add the following to your application's "shard.yml":

```
 dependencies:
   virtualdate:
     github: crystallabs/virtualdate
     version: ~> 1.0
```

And run `shards install` or just `shards`.

# Introduction

`VirtualTime` is a shard which implements the low-level component. It contains a class `VirtualTime` that is
used for matching Times.

`VirtualDate` is the high-level component. It represents actual things you want to schedule and/or their reminders.

The class is intentionally called `VirtualDate` not to imply a particular type or purpose
(i.e. it can be a task, event, recurring appointment, reminder, etc.)

Likewise, it does not contain any task/event-specific properties -- it only concerns itself with
the matching and scheduling aspect.

For a schedulable item it is not enough to have just one `VirtualTime` that controls
when that item is active/scheduled (or simply "on" in virtualtime's terminology).

Instead, for additional flexibility, at a minimum you might want to be able to specify multiple
`VirtualTimes` at which the item is on, and specify an omit list when an item
should not be on (e.g. on weekends or public holidays).

Also, if an item would fall on an omitted date or time, then it might be desired to automatically
reschedule it by shifting it by certain amount of time before or after the original time.

Thus, `VirtualDate` has the following properties:

- `start`, an absolute start time, before which the VirtualDate is never on
- `stop`, an absolute end time, after which the VirtualDate is never on

- `due`, a list of VirtualTimes on which the VirtualDate is on
- `omit`, a list of VirtualTimes on which the VirtualDate is omitted (not on)
- `shift`, governing whether, and by how much time, the VirtualDate should be shifted if it falls on an omitted date/time
- `max_shift`, a maximum Time::Span by which the VirtualDate can be shifted before being considered unschedulable
- `max_shifts`, a maximum number of shift attempts to make in an attempt to find a suitable rescheduled date and time

- `on`, a property which overrides all other VirtualDate's fields and calculations and directly sets VirtualDate's `on` status

If the item's list of due dates is empty, it is considered as always "on".
If the item's list of omit dates is empty, it is considered as never omitted.

A value of `shift` can be nil, `Boolean`, or`Time::Span`. Nil instructs that event should not be rescheduled,
and to simply treat it as not scheduled on a particular date. A `Boolean` explicitly marks the item as scheduled or rejected
when it falls on an omitted time. A `Time::Span` implies that rescheduling should be attempted and controls by
how much time the item should be shifted (into the past or future) on every attempt.

If there are multiple `VirtualDate`s set for a field, e.g. for `due` date, the matches are logically OR-ed;
one match is enough for the field to match.

# Usage

## Matching

Let's start with creating a VirtualDate:

```crystal
vd = VirtualDate.new

# Create a VirtualTime that matches every other day from Mar 10 to Mar 20:
due_march = VirtualTime.new
due_march.month = 3
due_march.day = (10..20).step 2

# Add this VirtualTime as due date to vd:
vd.due << due_march

# Create a VirtualTime that matches Mar 20 specifically. We will use this to actually omit
# the event on that day:
omit_march_20 = VirtualTime.new
omit_march_20.month = 3
omit_march_20.day = 20

# Add this VirtualTime as omit date to vd:
vd.omit << omit_march_20

# If event falls on an omitted date, try rescheduling it for 2 days later:
vd.shift = 2.days
```

Now we can check when the vd is due and when it is not (ignore the `Time[]` syntax):

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

# Asking whether the vd is due on the rescheduled date (Mar 22) will tell us no, because currently
# rescheduled dates are not counted as due/on dates:
p vd.on?( Time["2017-03-22"]) # ==> nil
```

Here's another example of a VirtualDate that is due on every other day in March, but if it falls
on a weekend it is ignored:

```crystal
vd = VirtualDate.new

# Create a VirtualTime that matches every other (every even) day in March:
due_march = VirtualTime.new
due_march.month = 3
due_march.day = (2..31).step 2
vd.due << due_march

# But on weekends it should not be scheduled:
not_due_weekend = VirtualTime.new
not_due_weekend.day_of_week = [6,7]
vd.omit << not_due_weekend

# If item falls on an omitted day, consider it as not scheduled (don't try rescheduling):
vd.shift = nil # or 'false' to explicitly say it's omitted; false is the default value

# Now let's check when it is due and when not in March:
# (Do this by printing a list for days 1 - 31):
(1..31).each do |d|
  p "Mar-#{d} = #{vd.on?( Time.local(2023, 3, d)}"
end
```

## Scheduling

TODO (and include note on rbtree and list of upcoming events)

## Reminding

TODO (note: reminder = VirtualDate::Reminder)

# Other Projects

List of interesting or similar projects in no particular order:

- https://dianne.skoll.ca/projects/remind/ - a sophisticated calendar and alarm program
