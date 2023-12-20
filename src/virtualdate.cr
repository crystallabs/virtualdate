require "virtualtime"

class VirtualDate
  VERSION_MAJOR    = 1
  VERSION_MINOR    = 0
  VERSION_REVISION = 0
  VERSION          = [VERSION_MAJOR, VERSION_MINOR, VERSION_REVISION].join '.'

  alias TimeOrVirtualTime = Time | VirtualTime

  # Absolute begin date/time. Item is never "on" before this date.
  property begin : Time?

  # Absolute end date/time. Item is never "on" after this date.
  property end : Time?

  # List of VirtualTimes on which the item is "on"/due/active.
  property due = [] of VirtualTime

  # List of VirtualTimes on which the item should be "omitted", i.e. on which it should not be on/due/active.
  # For example, this list may include weekends, known holidays in a year, sick days, vacation days, etc.
  #
  # Maybe this list should also implicitly contain all already scheduled items?
  property omit = [] of VirtualTime

  # Decision about an item to make if it falls on an omitted date/time.
  #
  # Allowed values are:
  # - nil: treat the item as non-applicable/not-scheduled on the specified date/time
  # - false: treat the item as not due due to falling on an omitted date/time, after a reschedule was not attempted or was not able to find another spot
  # - true: treat the item as due regardless of falling on an omitted date/time
  # - Time::Span: shift the scheduled date/time by specified time span. Can be negative (for rescheduling before the original due) or positive (for rescheduling after the original due)).
  #
  # If a time span is specified, shifting is performed incrementaly until a suitable date/time is found, or until max number of shift attempts is reached.
  property shift : Nil | Bool | Time::Span = false

  # Max amount of total time by which item can be shifted, before it's considered unschedulable (false)
  # E.g., if a company has meetings every 7 days, it probably makes no sense to reschedule a particular meeting for more than 6 days later, since on the 7th day a new meeting would be scheduled anyway.
  property max_shift : Time::Span?

  # Max amount of shift attempts, before it's considered unschedulable (false)
  #
  # If `shift = 1.minute` and `max_shifts = 1440`, it means the item will be shifted at most
  # 1440 minutes (1 day) compared to the original time for which it was asked, and on which it was
  # unschedulable due to omit times.
  property max_shifts = 1500

  # Fixed value of `#on?` for this item. This is useful for outright setting the item's status, without any calculations.
  #
  # It can be used for things such as:
  # - Marking an item as parmanently on, e.g. after it has once been activated
  # - Marking an item as permanently off, if it was disabled until further notice
  # - Marking the item as always shifted/postponed by certain time (e.g. to keep it on the 'upcoming' list or something)
  #
  # This field has the same union of types as `#shift`.
  #
  # The default is nil (no setting), to not override anything and allow for the standard calculations to run.
  # If defined, this setting takes precedence over `#begin` and `#end`.
  property on : Nil | Bool | Time::Span

  # TODO:
  # Add properties for:
  # 1. Duration of item (how long something will take, e.g. a meeting)
  # 2. Concurrency of item (how many items can be scheduled with this one concurrently)

  # Checks whether the item is "on" on the specified date/time. Item is
  # considered "on" if it matches at least one "due" time and does not
  # match any "omit" time. If it matches an omit time, then depending on
  # the value of shift it may still be "on", or attempted to be
  # rescheduled. Return values are:
  # nil - item is not "on" / not "due"
  # true - item is "on" (it is "due" and not on "omit" list)
  # false - item is due, but that date is omitted, and no reschedule was requested or possible, so effectively it is not "on"
  # Time::Span - span which is to be added to asked date to reach the earliest/closest time when item is "on"
  def on?(time : TimeOrVirtualTime = Time.local, *, max_shift = @max_shift, max_shifts = @max_shifts, hint = time.is_a?(Time) ? time : Time.local)
    # If `@on` is non-nil, it will dictate the item's status.
    @on.try { |status| return status }

    # VirtualTimes do not have a <=> relation. They inevitably must be converted to a `Time` before such comparisons.
    # Even a time hint is supported, in case you are checking for some date in the future.
    if time.is_a? VirtualTime
      time = time.to_time hint
    end

    # If date asked is not within item's absolute begin-end time, consider it not scheduled
    a, z = @begin, @end
    return if a && (a > time)
    return if z && (z < time)

    # Otherwise, we go perform the calculation:
    yes = due_on? time
    no = omit_on? time

    if yes
      if !no
        true
      else # Item falls on omitted time, try rescheduling
        shift = @shift
        if shift.is_a? Nil | Bool
          shift
        elsif shift.total_nanoseconds == 0
          false
        else
          # +amount => search into the future, -amount => search into the past
          new_time = time.dup

          shifts = 0
          ret = loop do
            shifts += 1
            new_time += shift

            if (max_shift && ((new_time - time).total_nanoseconds.abs > max_shift.total_nanoseconds)) || (max_shifts && (shifts > max_shifts))
              break false
            end
            if omit_on? new_time
              next
            else
              break true
            end

            if shifts >= max_shifts
              break false
            end
          end

          return ret ? (new_time - time) : ret
        end
      end
    end
  end

  # Due Date/Time-related functions

  # Checks if item is due on any of its date and time specifications.
  def due_on?(time : TimeOrVirtualTime = Time.local, times = @due)
    due_on_any_date?(time, times) && due_on_any_time?(time, times)
  end

  # Checks if item is due on any of its date specifications (without times).
  def due_on_any_date?(time : TimeOrVirtualTime = Time.local, times = @due)
    matches_any_date?(time, times, true)
  end

  # Checks if item is due on any of its time specifications (without dates).
  def due_on_any_time?(time : TimeOrVirtualTime = Time.local, times = @due)
    matches_any_time?(time, times, true)
  end

  # Omit Date/Time-related functions

  # Checks if item is omitted on any of its date and time specifications.
  def omit_on?(time : TimeOrVirtualTime = Time.local, times = @omit)
    omit_on_dates?(time, times) && omit_on_times?(time, times)
  end

  # Checks if item is omitted on any of its date specifications (without times).
  def omit_on_dates?(time : TimeOrVirtualTime = Time.local, times = @omit)
    matches_any_date?(time, times, nil)
  end

  # Checks if item is omitted on any of its time specifications (without dates).
  def omit_on_times?(time : TimeOrVirtualTime = Time.local, times = @omit)
    matches_any_time?(time, times, nil)
  end

  # Helper methods below, used by both due- and omit-related functions.

  # Checks if any item in `times` matches the date part of `time`
  def matches_any_date?(time : TimeOrVirtualTime, times, default)
    return default if !times || (times.size == 0)

    times.each do |vt|
      return true if vt.matches_date? time
    end

    nil
  end

  # Checks if any item in `times` matches the time part of `time`
  def matches_any_time?(time : TimeOrVirtualTime, times, default)
    return default if !times || (times.size == 0)

    times.each do |e|
      return true if e.matches_time? time
    end

    nil
  end
end
