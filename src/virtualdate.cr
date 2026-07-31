require "virtualtime"

# VirtualDate builds on VirtualTime to represent due/omit rules plus higher-level scheduling semantics.
class VirtualDate
  VERSION_MAJOR    = 1
  VERSION_MINOR    = 4
  VERSION_REVISION = 0
  VERSION          = [VERSION_MAJOR, VERSION_MINOR, VERSION_REVISION].join '.'

  include YAML::Serializable

  # Absolute begin date/time. Item is never "on" before this date.
  @[YAML::Field(converter: VirtualDate::VirtualTimeOrTimeConverter)]
  property begin : VirtualTime::TimeOrVirtualTime?

  # Absolute end date/time. Item is never "on" after this date.
  @[YAML::Field(converter: VirtualDate::VirtualTimeOrTimeConverter)]
  property end : VirtualTime::TimeOrVirtualTime?

  # List of VirtualTimes on which the vdate is "on"/due/active.
  property due = [] of VirtualTime

  # List of VirtualTimes on which the vdate should be "omitted".
  property omit = [] of VirtualTime

  # Decision about an vdate to make if it falls on an omitted date/time.
  #
  # Allowed values are:
  # - nil: treat the vdate as non-applicable/not-scheduled on the specified date/time
  # - false: treat the vdate as not due due to falling on an omitted date/time, after a reschedule was not attempted or was not able to find another spot
  # - true: treat the vdate as due regardless of falling on an omitted date/time
  # - Time::Span: shift the scheduled date/time by specified time span. Can be negative or positive.
  #
  # Written out by `#on_to_yaml`, not by the generated serializer; see the note there.
  @[YAML::Field(converter: VirtualDate::ShiftConverter, ignore_serialize: true)]
  property shift : Nil | Bool | Time::Span = false

  # Max amount of total time by which vdate can be shifted before it's considered unschedulable (false)
  @[YAML::Field(converter: VirtualDate::NullableTimeSpanSecondsConverter)]
  property max_shift : Time::Span?

  # Max amount of shift attempts, before it's considered unschedulable (false)
  property max_shifts = 1500

  # Fixed override of `#on?` for this vdate. If set, takes precedence over begin/end/due/omit.
  # Same union as `#shift`.
  #
  # Written out by `#on_to_yaml`, not by the generated serializer; see the note there.
  @[YAML::Field(converter: VirtualDate::ShiftConverter, ignore_serialize: true)]
  property on : Nil | Bool | Time::Span

  @[YAML::Field(converter: VirtualDate::TimeSpanSecondsConverter)]
  property duration : Time::Span = 0.seconds

  # Flags/categories (e.g. meeting, task, or passive/active/unimportant, or color-coded, or anything). Used by Scheduler for parallelism.
  property flags = Set(String).new

  # Max number of overlapping vdates that share at least one common flag with this vdate.
  # Example: flags={meeting}, parallel=2 means up to 2 meetings can overlap.
  property parallel : Int32 = 1

  # Higher wins conflict resolution when Scheduler must choose.
  property priority : Int32 = 0

  # If true, Scheduler treats this vdate as non-movable due to conflicts (still movable by omit-rescheduling rules if you keep shift != false).
  property? fixed : Bool = false

  # Optional dependencies: scheduler will try to place this vdate after all dependencies.
  # (Used only by Scheduler; VirtualDate itself does not enforce this.)
  @[YAML::Field(ignore: true)]
  property depends_on = [] of VirtualDate

  # Serialized form
  #
  # Written out by `#on_to_yaml`, not by the generated serializer; see the note there.
  @[YAML::Field(key: "depends_on", ignore_serialize: true)]
  property depends_on_ids = [] of String

  # Optional staggered parallel scheduling
  @[YAML::Field(converter: VirtualDate::NullableTimeSpanSecondsConverter)]
  property stagger : Time::Span? = nil

  # Identifier (important for dependencies)
  property id : String

  # Hard deadline — vdate MUST finish before this time or fails scheduling
  @[YAML::Field(converter: VirtualDate::VirtualTimeOrTimeConverter)]
  property deadline : VirtualTime::TimeOrVirtualTime? = nil

  def initialize(@id : String = "")
  end

  # Checks if the vdate is effectively scheduled at `time`.
  # Returns:
  # - true if it is on at `time` directly, OR due at some base time that resolves (via shifting) to exactly `time`
  # - false otherwise (not applicable, not scheduled, or unschedulable)
  #
  # Unlike `#strict_on?`, this method never returns nil or Time::Span.
  #
  # (For omit-driven shifting (Time::Span), we can search candidate base times by shifting back in the opposide direction.
  # This is deterministic, bounded by max_shifts/max_shift.)
  def on?(time : Time, *, max_shift = @max_shift, max_shifts = @max_shifts) : Bool
    # 1. Direct check
    direct = strict_on?(time, max_shift: max_shift, max_shifts: max_shifts, hint: time)
    return true if direct == true
    return false if direct == false

    # 2. Only Time::Span shifts can produce inverse reachability.
    #    An `#on` override of a span displaces the vdate in place of the
    #    omit-driven `#shift` policy, so that is the step to search back along;
    #    consulting `#shift` alone would report a vdate as never on even at the
    #    very time `#resolve` says it lands on.
    shift = @on.as?(Time::Span) || @shift
    return false unless shift.is_a?(Time::Span)
    return false if shift.total_nanoseconds == 0

    # (A log entry could be written about this.)
    return false if shifts_exhausted? max_shifts
    # 3. Inverse successor search:
    #    Look for a base time such that:
    #      strict_on?(base) => Time::Span delta
    #      base + delta == time
    VirtualTime::Search.shifted_from_base?(time, shift, max_shift: max_shift, max_shifts: max_shifts) do |base|
      r = strict_on?(base, max_shift: max_shift, max_shifts: max_shifts, hint: base)
      # As mentioned, only Time::Span results participate in inverse reachability
      # (value of `true` does NOT imply reachability of `time`)
      r.is_a?(Time::Span) ? r : nil
    end
  end

  # Checks whether the vdate is "on" on the specified date/time.
  #
  # Return values:
  # nil        - vdate is not "on" / not due / not scheduled
  # true       - vdate is "on" (due and not omitted)
  # false      - vdate is due but omitted and no reschedule requested or possible
  # Time::Span - the span to add to asked date to reach earliest/closest time when vdate is "on"
  #
  # IMPORTANT: If the vdate is rescheduled away from the asked time,
  # `strict_on?` returns a Time::Span, but querying `strict_on?` at the rescheduled time will not
  # necessarily return true. Use `#resolve` or `#on?` to return a true falue for shifted dates/times.
  # ameba:disable Metrics/CyclomaticComplexity
  def strict_on?(time : VirtualTime::TimeOrVirtualTime = Time.local, *, max_shift = @max_shift, max_shifts = @max_shifts, hint = time.is_a?(Time) ? time : Time.local) : Nil | Bool | Time::Span
    # If `@on` is non-nil, it overrides vdate's status unconditionally.
    @on.try { |status| return status }

    # Absolute begin/end filtering. If they are VirtualTime by chance, then
    # they are not used for `a <= T <= z` comparison but simply they must
    # match `T` in the usual sense (via a VT comparison).
    a, z = @begin, @end

    a.try do |a_val|
      case a_val
      when Time
        return if a_val > instant_of(time, hint)
      else
        return unless a_val.matches?(time)
      end
    end

    z.try do |z_val|
      case z_val
      when Time
        return if z_val < instant_of(time, hint)
      else
        return unless z_val.matches?(time)
      end
    end

    # Convert VirtualTime input to Time for downstream work.
    if time.is_a?(VirtualTime)
      time = time.to_time(hint)
    end

    yes = due_on?(time)
    no = omit_on?(time)

    if yes
      if !no
        return true
      end

      # Due but omitted: apply shift policy
      s = @shift
      if s.is_a?(Nil | Bool)
        return s
      end

      # Time::Span shift
      return false if s.total_nanoseconds == 0
      # (A log entry could be written about this.)
      return false if shifts_exhausted? max_shifts
      delta = unwrap_shift_result VirtualTime::Search.shift_from_base(time, s, max_shift: max_shift, max_shifts: max_shifts) { |candidate| omit_on?(candidate) == true }
      return delta || false
    end

    nil
  end

  # Returns whether any of the vdate's `#due` rules is on at `time`.
  #
  # An empty list means the vdate is always due.
  def due_on?(time : VirtualTime::TimeOrVirtualTime = Time.local, times = @due)
    matches_any?(time, times, true)
  end

  def due_on_any_date?(time : VirtualTime::TimeOrVirtualTime = Time.local, times = @due)
    matches_any_date?(time, times, true)
  end

  def due_on_any_time?(time : VirtualTime::TimeOrVirtualTime = Time.local, times = @due)
    matches_any_time?(time, times, true)
  end

  # Returns whether any of the vdate's `#omit` rules covers `time`.
  #
  # An empty list means the vdate is never omitted.
  def omit_on?(time : VirtualTime::TimeOrVirtualTime = Time.local, times = @omit)
    matches_any?(time, times, nil)
  end

  def omit_on_dates?(time : VirtualTime::TimeOrVirtualTime = Time.local, times = @omit)
    matches_any_date?(time, times, nil)
  end

  def omit_on_times?(time : VirtualTime::TimeOrVirtualTime = Time.local, times = @omit)
    matches_any_time?(time, times, nil)
  end

  # Returns `default` if `times` is empty, `true` if at least one of them
  # matches `time` outright, and `nil` otherwise.
  #
  # A rule has to match on both its date and its time part. Taking the date
  # from one rule and the time from another would report a match that none of
  # the rules on its own expresses -- and would, for instance, make an `omit`
  # of "December 25" together with "12:00" omit every instant of the year,
  # since the first rule constrains no time and the second no date.
  def matches_any?(time : VirtualTime::TimeOrVirtualTime, times : Array(VirtualTime), default)
    return default if times.size == 0
    times.each do |vtime|
      return true if vtime.matches?(time)
    end
    nil
  end

  # :ditto:
  #
  # Considers only the date part of each rule.
  def matches_any_date?(time : VirtualTime::TimeOrVirtualTime, times : Array(VirtualTime), default)
    return default if times.size == 0
    times.each do |vtime|
      return true if vtime.matches_date?(time)
    end
    nil
  end

  # :ditto:
  #
  # Considers only the time part of each rule.
  def matches_any_time?(time : VirtualTime::TimeOrVirtualTime, times : Array(VirtualTime), default)
    return default if times.size == 0
    times.each do |vtime|
      return true if vtime.matches_time?(time)
    end
    nil
  end

  # Resolves the asked VirtualTime to an effective scheduled Time.
  #
  # Returns:
  # - Time  : resolved scheduled time
  # - true  : scheduled "as asked" (same as returning `time`, but preserved for symmetry)
  # - nil   : not scheduled
  # - false : due but unschedulable
  #
  # Notes:
  # - For `Time` input, returned `Time` preserves the timezone/location of the input time.
  # - For `VirtualTime` input, uses `hint` for materialization as in legacy `on?`.
  def resolve(time : VirtualTime::TimeOrVirtualTime = Time.local, *, max_shift = @max_shift, max_shifts = @max_shifts, hint = time.is_a?(Time) ? time : Time.local) : Time | Bool | Nil
    r = strict_on?(time, max_shift: max_shift, max_shifts: max_shifts, hint: hint)
    case r
    when Time::Span
      t = time.is_a?(Time) ? time : time.to_time(hint)
      t + r
    else
      r
    end
  end

  @[AlwaysInline]
  private def shifts_exhausted?(max_shifts)
    max_shifts && max_shifts <= 0
  end

  # Returns the point in time `time` stands for, materializing it against
  # `hint` if it is a pattern rather than an instant.
  #
  # An absolute `#begin` or `#end` bounds the instant, so it has to be compared
  # with one. Matching the bound against the asked pattern instead would answer
  # differently depending on how the very same moment was spelled: a
  # `VirtualTime` for June 1 asked of a vdate beginning on May 10 would come
  # back "not applicable", while the identical `Time` came back "on".
  @[AlwaysInline]
  private def instant_of(time : VirtualTime::TimeOrVirtualTime, hint) : Time
    time.is_a?(Time) ? time : time.to_time(hint)
  end

  # A simple, deterministic scheduler for VirtualDate vdates.
  #
  # This scheduler:
  # - Generates candidate candidates from `vdate.due` VirtualTimes
  # - Resolves omit-driven shifts via `VirtualDate#resolve`
  # - Enforces conflict resolution using `duration`, `flags`, `parallel`
  # - Reschedules forward on conflicts when possible
  #
  # Notes:
  # - This is an “advanced baseline” scheduler; it is intentionally conservative and predictable.
  # - If you need global optimality (e.g. minimizing total displacement), you would add a second pass
  #   or switch to a constraint solver.
  class Scheduler
    property vdates : Array(VirtualDate)

    def initialize(@vdates = [] of VirtualDate)
      resolve_dependencies!
      validate_no_dependency_cycles!
    end

    # Turns each vdate's serialized `depends_on` ids into object references.
    #
    # `#build` runs this too, because `#vdates` is writable: a vdate appended
    # after construction -- one just loaded from YAML, say -- would otherwise
    # keep its dependencies as unresolved ids and be scheduled as though it had
    # none, quite possibly before the vdates it depends on.
    def resolve_dependencies!
      index = @vdates.to_h { |vdate| {vdate.id, vdate} }

      @vdates.each do |vdate|
        vdate.resolve_dependencies!(index)
      end
    end

    # Holds the vdates to the same limits `VirtualDateFile` enforces on a
    # document, so that a value set in code cannot do what one read from YAML
    # is refused for.
    #
    # A negative duration in particular has consequences beyond the vdate
    # itself: it finishes before it starts, which switches off overlap
    # detection, so other vdates are then free to take a slot it holds.
    private def validate_vdates!
      @vdates.each do |vdate|
        if vdate.duration < Time::Span.zero
          raise ArgumentError.new("duration of vdate '#{vdate.id}' must be >= 0")
        end

        if vdate.parallel < 1
          raise ArgumentError.new("parallel of vdate '#{vdate.id}' must be >= 1")
        end
      end
    end

    # Maximum number of step-iterator advances per due rule while scanning for
    # occurrence starts. Guards against effectively-continuous rules scanned at
    # too fine a granularity (e.g. an always-matching rule over a year-long window).
    MAX_RULE_ITERATIONS = 100_000

    # Produces scheduled vdates in [from, to).
    #
    # Each due rule generates one candidate per distinct occurrence in the window.
    # Times that match contiguously at `granularity` spacing (e.g. every minute of
    # `hour: 10`) coalesce into a single occurrence starting at the first match.
    #
    # Parameters:
    # - granularity: resolution at which due rules are scanned and distinct occurrences are told apart (defaults to 1 minute)
    # - max_candidates: safety limit on candidates per vdate, to avoid runaway generation for very broad rules
    #
    # Returns: Array(Scheduled), sorted by start time.
    def build(from : Time, to : Time, *, granularity : Time::Span = 1.minute, max_candidates : Int32 = 1000) : Array(Scheduled)
      raise ArgumentError.new("granularity must be positive") if granularity <= Time::Span.zero
      raise ArgumentError.new("max_candidates must be >= 1") if max_candidates < 1

      validate_vdates!
      resolve_dependencies!
      validate_no_dependency_cycles!

      scheduled_vdates = [] of Scheduled

      ordered = order_vdates_by_dependencies(@vdates)
      scheduled_index = {} of VirtualDate => Scheduled

      # Computed once, because it is consulted for every candidate and for
      # every conflict encountered while placing one.
      depended_upon = vdates_with_dependents

      ordered.each do |vdate|
        dependency_floor = vdate.depends_on.empty? ? nil : earliest_start_time_after_dependencies(vdate, scheduled_index)
        next if !vdate.depends_on.empty? && dependency_floor.nil?

        candidates = generate_candidates(vdate, from, to, granularity, max_candidates)

        placed = false
        rejected = false

        candidates.each do |candidate|
          if dependency_floor && dependency_floor > candidate.start
            original_start = candidate.start
            candidate = Candidate.new(vdate, dependency_floor)
            candidate.explanation.add("Shifted from #{original_start} to #{dependency_floor} to satisfy dependency constraints")
          end

          scheduled_vdate = schedule_candidate(candidate, scheduled_vdates, horizon: to, depended_upon: depended_upon)

          if scheduled_vdate
            placed = true
            scheduled_vdates << scheduled_vdate
            scheduled_index[scheduled_vdate.vdate] = scheduled_vdate
          else
            rejected = true
          end
          # A rejected candidate may fail silently
        end

        # A vdate that others depend on must never be silently dropped, or
        # those dependents would be scheduled against nothing. Losing some of
        # its occurrences is fine though -- a later one may simply not fit in
        # the window -- as long as at least one of them was placed.
        if rejected && !placed && depended_upon.includes? vdate
          raise ArgumentError.new(
            "Failed to schedule vdate #{vdate.id}, which other vdates depend on"
          )
        end
      end

      scheduled_vdates.sort_by!(&.start)
      scheduled_vdates
    end

    # Sort by dependencies. VDates with no dependencies have indegree == 0.
    # E.g. ready = vdates.select { |t| indegree[t] == 0 }
    private def order_vdates_by_dependencies(vdates : Array(VirtualDate)) : Array(VirtualDate)
      # Build adjacency + indegree
      indegree = Hash(VirtualDate, Int32).new(0)
      outgoing = Hash(VirtualDate, Array(VirtualDate)).new { |hash, key| hash[key] = [] of VirtualDate }

      vdates.each do |vdate|
        indegree[vdate] = 0
      end

      vdates.each do |vdate|
        vdate.depends_on.each do |dep|
          next unless vdates.includes?(dep)
          outgoing[dep] << vdate
          indegree[vdate] = indegree[vdate] + 1
        end
      end

      # Ready set (indegree 0)
      ready = vdates.select { |vdate| indegree[vdate] == 0 }

      # Deterministic ordering:
      # - fixed first (true first)
      # - higher priority first
      # - stable tie-breaker by id (string)
      sorter = ->(a : VirtualDate, b : VirtualDate) do
        # 1. Fixed vdates first
        fa = a.fixed? ? 0 : 1
        fb = b.fixed? ? 0 : 1
        cmp = fa <=> fb
        return cmp if cmp != 0

        # 2. Higher priority first
        cmp = b.priority <=> a.priority
        return cmp if cmp != 0

        # 3. Stable ordering (ID)
        a.id <=> b.id
      end

      result = [] of VirtualDate

      while ready.size > 0
        ready.sort!(&sorter)
        n = ready.shift
        result << n

        outgoing[n].each do |dependent|
          indegree[dependent] = indegree[dependent] - 1
          if indegree[dependent] == 0
            ready << dependent
          end
        end
      end

      if result.size != vdates.size
        raise ArgumentError.new("Dependency cycle detected")
      end

      result
    end

    # Returns start times of distinct occurrences of `vdate`'s due rules in [from, to),
    # sorted and deduplicated. Occurrences are found by materializing successive matching
    # times directly from each due rule (`VirtualTime#step`), so sparse rules (e.g. one
    # day per month) are found without scanning the window minute by minute.
    #
    # Times that match contiguously at `granularity` spacing coalesce into a single
    # occurrence starting at the first matching time.
    private def occurrence_starts(vdate : VirtualDate, from : Time, to : Time, granularity : Time::Span, max_candidates : Int32) : Array(Time)
      # No due rules means the vdate is always on; a single candidate at window start
      return [from] if vdate.due.empty?

      starts = [] of Time

      vdate.due.each do |vtime|
        iter =
          begin
            vtime.step(granularity, from: from - 1.nanosecond)
          rescue ArgumentError
            # Rule cannot materialize at all (e.g. unsatisfiable constraints)
            next
          end

        iterations = 0
        prev = nil

        loop do
          t = iter.next
          break unless t.is_a?(Time)
          # Rule only materializes into the past; not satisfiable in this window
          break if t < from
          break if t >= to
          # Iterator not advancing (fully-fixed rule reached its only match)
          break if prev && t <= prev

          iterations += 1
          if iterations > MAX_RULE_ITERATIONS
            raise ArgumentError.new("Occurrence scan exceeded #{MAX_RULE_ITERATIONS} steps for a due rule of vdate '#{vdate.id}'; use a coarser granularity or a narrower window")
          end

          if prev.nil? || (t - prev) > granularity
            starts << t
          end
          prev = t

          break if starts.size >= max_candidates
        end
      end

      starts.uniq!.sort!
      starts.first(max_candidates)
    end

    # Finds earliest time a vdate can start, but not before its dependencies
    # are completed.
    private def earliest_start_time_after_dependencies(vdate : VirtualDate, scheduled_index : Hash(VirtualDate, VirtualDate::Scheduled)) : Time?
      finishes = [] of Time

      vdate.depends_on.each do |dep_vdate|
        inst = scheduled_index[dep_vdate]?
        return nil unless inst
        finishes << inst.finish
      end

      finishes.max?
    end

    # Generates one candidate per occurrence of the vdate's due rules in [from, to).
    #
    # Does:
    # - Applies begin/end bounds and omit/shift policies (via `VirtualDate#resolve`)
    # - Optionally expands each occurrence into multiple candidates (staggered / parallel vdates)
    #
    # Does not do things that happen later in `schedule_candidate`, such as:
    # - Resolve conflicts
    # - Respect dependencies
    # - Parallelism limits
    # - Check deadlines
    # - Shift due to conflicts
    #
    # - Returns a bounded list of concrete Time values wrapped as objects
    private def generate_candidates(vdate : VirtualDate, from : Time, to : Time, granularity : Time::Span, max_candidates : Int32) : Array(Candidate)
      candidates = [] of Candidate
      seen_starts = Set(Time).new

      occurrence_starts(vdate, from, to, granularity, max_candidates).each do |base|
        start =
          case r = vdate.resolve(base)
          when Time then r    # Due but omitted; rescheduled by shift policy
          when true then base # Due as asked
          else           nil  # nil: not on (begin/end bounds), false: unschedulable
          end

        next unless start
        # The window is half-open, so a start of exactly `to` is outside it
        next if start >= to
        # Different bases can shift-resolve to the same start; schedule it once
        next unless seen_starts.add?(start)

        if (stagger = vdate.stagger) && vdate.parallel > 1
          raise ArgumentError.new("stagger must be positive") if stagger <= 0.seconds

          vdate.parallel.times do |i|
            t = start + stagger * i
            break if t >= to

            next if vdate.omit_on?(t)

            candidate = Candidate.new(vdate, t)
            candidate.explanation.add("Initial staggered candidate ##{i + 1} at #{t} (stagger=#{stagger})")
            candidates << candidate
          end
        else
          candidate = Candidate.new(vdate, start)
          candidate.explanation.add("Initial candidate at #{start}")
          candidates << candidate
        end

        break if candidates.size >= max_candidates
      end

      candidates
    end

    # Schedules a vdate, resolving conflicts by shifting forward (using vdate.shift when Time::Span),
    # respecting vdate.fixed and max_shift/max_shifts.
    #
    # `depended_upon` is the set of vdates that others depend on; those are
    # scheduled even when they conflict with a fixed vdate. It defaults to
    # deriving that set from `#vdates`, and exists so that `#build` can compute
    # it once instead of once per conflict.
    # ameba:disable Metrics/CyclomaticComplexity
    def schedule_candidate(candidate : Candidate, scheduled_vdates : Array(Scheduled), *, horizon : Time, depended_upon : Set(VirtualDate) = vdates_with_dependents) : Scheduled?
      vdate = candidate.vdate
      start = candidate.start
      duration = vdate.duration
      explanation = candidate.explanation

      # Conflict resolution moves a vdate forward, so it is bounded by the same
      # two limits as omit-driven rescheduling -- otherwise a `max_shift` of
      # half an hour would not stop a 10:00 vdate from ending up at 23:00.
      origin = start
      previous_start = start
      max_shift = vdate.max_shift
      max_shifts = vdate.max_shifts
      shifts = 0

      loop do
        if start != previous_start
          previous_start = start
          shifts += 1

          if shifts > max_shifts
            explanation.add "Rejected: conflict shifting exceeded max_shifts (#{max_shifts})"
            return nil
          end

          if max_shift && (start - origin) > max_shift
            explanation.add "Rejected: shifting to #{start} exceeds max_shift (#{max_shift})"
            return nil
          end
        end

        # Two instances of one vdate at the very same start are one occurrence
        # counted twice, whatever `#parallel` allows for overlapping ones.
        # Several of them can converge here: occurrences before a dependency
        # floor all move onto it, and conflict resolution can walk two of them
        # onto a single start.
        if scheduled_vdates.any? { |i| i.vdate.same?(vdate) && i.start == start }
          explanation.add "Rejected: #{vdate.id} is already scheduled at #{start}"
          return nil
        end

        finish = start + duration

        # Horizon guard
        if finish > horizon
          explanation.add("Rejected: finish #{finish} exceeds horizon #{horizon}")
          return nil
        end

        scheduled = Scheduled.new(vdate, start, explanation)

        if deadline = vdate.deadline
          deadline_time =
            case deadline
            when Time
              deadline
            else
              deadline.to_time(start)
            end

          if finish > deadline_time
            explanation.add "Rejected: finish #{finish} exceeds hard deadline #{deadline_time}"
            return nil
          end
        end

        # Check parallelism / conflicts. A zero-duration vdate overlaps nothing,
        # so it always lands here on the first pass.
        if acceptable_parallelism?(scheduled, scheduled_vdates)
          explanation.add "Scheduled at #{start}, no conflicts, parallelism OK"
          return scheduled
        end

        # Conflict exists. Only vdates competing for the same parallelism slots
        # (sharing an effective flag group) count; an unrelated overlapping vdate
        # can run in parallel and must not be displaced or yielded to.
        conflict = scheduled_vdates.find do |i|
          overlaps?(start, finish, i.start, i.finish) && shares_flag_group?(vdate, i.vdate)
        end

        # Fixed vdate rules
        if conflict
          if conflict.vdate.fixed?
            # If vdate has dependents, it must be scheduled even if it conflicts
            if depended_upon.includes? vdate
              explanation.add("Scheduled despite conflicts because dependent vdates require it")
              return scheduled
            end

            # Otherwise respect fixed semantics
            return nil if vdate.fixed?

            explanation.add "Yielded to fixed vdate #{conflict.vdate.id} (#{conflict.start}-#{conflict.finish}), shifted from #{start} to #{conflict.finish}"
            start = conflict.finish
            next
          end

          if vdate.fixed?
            # An already-scheduled vdate that others depend on is not
            # displaced, for the same reason as in the priority comparison
            # below: its dependents are placed relative to its finish time, and
            # removing it would leave them anchored to a time that is no longer
            # in the schedule. Being fixed is a statement about movement,
            # whereas a dependency is structural, so the dependency wins.
            if depended_upon.includes? conflict.vdate
              # Unless this vdate is depended on as well, which is the same
              # standoff the fixed-versus-fixed case above settles by
              # scheduling regardless.
              if depended_upon.includes? vdate
                explanation.add "Scheduled despite conflicts because dependent vdates require it"
                return scheduled
              end

              explanation.add "Not scheduled: being fixed, it cannot move, and it must not displace vdate #{conflict.vdate.id}, which other vdates depend on"
              return nil
            end

            scheduled_vdates.delete(conflict)
            explanation.add "Displaced movable vdate #{conflict.vdate.id} because this vdate is fixed"
            next
          end

          # Priority comparison.
          #
          # An already-scheduled vdate that others depend on is not displaced:
          # its dependents were placed relative to its finish time earlier in
          # this pass, and removing it now would leave them anchored to a time
          # that is no longer in the schedule. Priority is a preference, whereas
          # a dependency is structural, so the dependency wins.
          if vdate.priority > conflict.vdate.priority && !depended_upon.includes?(conflict.vdate)
            scheduled_vdates.delete(conflict)
            explanation.add "Displaced lower-priority vdate #{conflict.vdate.id} (priority #{conflict.vdate.priority})"
            next
          elsif vdate.priority > conflict.vdate.priority
            explanation.add "Yielded to vdate #{conflict.vdate.id} despite its lower priority, because other vdates depend on it; shifted from #{start} to #{conflict.finish}"
            start = conflict.finish
            next
          elsif vdate.priority < conflict.vdate.priority
            explanation.add "Yielded to higher-priority vdate #{conflict.vdate.id}, shifted from #{start} to #{conflict.finish}"
            start = conflict.finish
            next
          end
        end

        # Equal priority or no decisive conflict → shift forward.
        # A zero or negative shift would never advance past the conflict
        # (looping forever), so those fall back to the default step.
        shift_span =
          case s = vdate.shift
          when Time::Span
            s > Time::Span.zero ? s : 1.minute
          else
            1.minute
          end

        explanation.add("Conflict unresolved; shifted forward by #{shift_span} to #{start + shift_span}")

        start += shift_span
      end
    end

    # True if `vdate` is considered “on” at `time` in the produced schedule.
    def on_in_schedule?(scheduled_vdates : Array(Scheduled), vdate : VirtualDate, time : Time) : Bool
      scheduled_vdates.any? do |i|
        next false unless i.vdate == vdate

        if i.start == i.finish
          time == i.start
        else
          i.start <= time && time < i.finish
        end
      end
    end

    # Returns the vdates that at least one other vdate depends on.
    #
    # Scheduling consults this per candidate and per conflict, so it is built in
    # one pass rather than re-scanning every vdate's dependencies each time.
    def vdates_with_dependents : Set(VirtualDate)
      depended_upon = Set(VirtualDate).new

      @vdates.each do |vdate|
        vdate.depends_on.each { |dep| depended_upon << dep }
      end

      depended_upon
    end

    @[AlwaysInline]
    private def overlaps?(a_start, a_end, b_start, b_end)
      a_start < b_end && b_start < a_end
    end

    # True if the two vdates compete for the same parallelism slots.
    # Vdates without flags all share one implicit default group.
    private def shares_flag_group?(a : VirtualDate, b : VirtualDate) : Bool
      if a.flags.empty?
        b.flags.empty?
      else
        a.flags.any? { |flag| b.flags.includes?(flag) }
      end
    end

    # Enforces per-vdate parallelism across overlapping scheduled_vdates sharing flags.
    #
    # `parallel` states how much overlap a vdate itself tolerates, so a set of
    # overlapping vdates is capped by the smallest limit among them: placing a
    # `parallel: 2` vdate on top of an already-scheduled `parallel: 1` one would
    # otherwise break the latter's constraint after the fact.
    private def acceptable_parallelism?(candidate : Scheduled, scheduled_vdates : Array(Scheduled)) : Bool
      c_start = candidate.start
      c_end = candidate.finish
      limit = candidate.vdate.parallel
      flags = candidate.vdate.flags

      # Vdates without flags all compete within one implicit default group
      if flags.empty?
        concurrent = 0

        scheduled_vdates.each do |i|
          next unless i.vdate.flags.empty?
          next unless overlaps?(c_start, c_end, i.start, i.finish)

          concurrent += 1
          limit = i.vdate.parallel if i.vdate.parallel < limit
        end

        return concurrent + 1 <= limit
      end

      flags.each do |flag|
        concurrent = 0
        flag_limit = limit

        scheduled_vdates.each do |i|
          next unless i.vdate.flags.includes? flag
          next unless overlaps?(c_start, c_end, i.start, i.finish)

          concurrent += 1
          flag_limit = i.vdate.parallel if i.vdate.parallel < flag_limit
          return false if concurrent + 1 > flag_limit
        end
      end

      true
    end

    # Ensure there are no depdendency cycles or raise.
    private def validate_no_dependency_cycles!
      visiting = Set(VirtualDate).new
      visited = Set(VirtualDate).new

      @vdates.each do |vdate|
        dfs_check!(vdate, visiting, visited)
      end
    end

    # Depth-first search. Checks for dependency cycles.
    private def dfs_check!(
      vdate : VirtualDate,
      visiting : Set(VirtualDate),
      visited : Set(VirtualDate),
    )
      return if visited.includes?(vdate)

      if visiting.includes?(vdate)
        raise ArgumentError.new("Dependency cycle detected involving '#{vdate.id}'")
      end

      visiting << vdate
      vdate.depends_on.each do |dep|
        dfs_check!(dep, visiting, visited)
      end
      visiting.delete(vdate)
      visited << vdate
    end
  end

  # A candidate for scheduling, points to vdate, time, and an explanation buffer
  struct Candidate
    getter vdate : VirtualDate
    getter start : Time
    getter explanation : VirtualDate::Explanation

    def initialize(@vdate : VirtualDate, @start : Time)
      @explanation = VirtualDate::Explanation.new
    end
  end

  # A concrete scheduled candidate of a VirtualDate vdate.
  class Scheduled
    getter vdate : VirtualDate
    getter start : Time
    getter finish : Time
    property explanation : VirtualDate::Explanation

    def initialize(@vdate : VirtualDate, @start : Time, explanation : VirtualDate::Explanation? = nil)
      @finish = @start + vdate.duration
      @explanation = explanation || VirtualDate::Explanation.new
    end

    def flags : Array(String)
      vdate.flags.to_a
    end

    def fixed? : Bool
      vdate.fixed?
    end
  end

  # Holds a buffer of string explanations, for scheduling etc.
  #
  # This is a reference type on purpose: a `Candidate` hands its buffer to the
  # `Scheduled` it turns into, and both go on appending to the same buffer.
  class Explanation
    # Maximum number of messages kept. Once reached, a final overflow notice is
    # appended and all further messages are dropped.
    MAX_LINES = 100

    property lines : Array(String)

    def initialize
      @lines = [] of String
    end

    # Appends `msg`, and returns whether it (and any further message) was kept.
    def add(msg : String) : Bool
      return false if @lines.size >= MAX_LINES

      @lines << msg

      if @lines.size == MAX_LINES
        @lines[-1] = "Explanation buffer overflow (limit: #{MAX_LINES} messages)"
        return false
      end

      true
    end

    def to_s(io : IO) : Nil
      @lines.join io, "\n"
    end
  end

  # Files-related stuff (YAML)

  struct VirtualDateFile
    include YAML::Serializable

    property schema_version : Int32
    property vdates : Array(VirtualDate)

    def self.load(yaml : String) : Array(VirtualDate)
      doc = YAML::Nodes.parse(yaml)
      node = doc.nodes.first? || raise ArgumentError.new("Empty YAML document")

      case node
      when YAML::Nodes::Mapping
        # Validation applies to the current (schema-versioned) format only,
        # so it must run after the root type is known.
        YamlValidator.validate!(yaml)

        file = from_yaml(yaml)

        if file.schema_version > Migrator::CURRENT_VERSION
          raise ArgumentError.new("Unsupported schema_version #{file.schema_version}")
        end

        file.vdates
      when YAML::Nodes::Sequence
        # Legacy format: bare vdate list
        Array(VirtualDate).from_yaml(yaml)
      else
        raise ArgumentError.new(
          "Invalid YAML root (expected mapping with schema_version or vdate list)"
        )
      end
    end
  end

  module Migrator
    # Latest on-disk schema version produced and accepted by `VirtualDateFile`.
    # Documents tagged with a higher version are rejected by `VirtualDateFile.load`.
    CURRENT_VERSION = 2
  end

  struct YamlError
    getter message : String
    getter line : Int32
    getter column : Int32

    def initialize(@message, node : YAML::Nodes::Node)
      @line = node.start_line + 1
      @column = node.start_column + 1
    end

    def to_s(io : IO) : Nil
      io << "Line " << @line << ", column " << @column << ": " << @message
    end
  end

  module YamlValidator
    extend self

    def validate!(yaml : String)
      doc = YAML::Nodes.parse(yaml)
      root = doc.nodes.first? || raise "Empty YAML document"

      errors = [] of YamlError

      unless root.is_a?(YAML::Nodes::Mapping)
        errors << YamlError.new("Root must be a mapping", root)
        raise_errors(errors)
      end

      validate_root_mapping(root, errors)

      raise_errors(errors) unless errors.empty?
    end

    private def raise_errors(errors)
      msg = errors.map(&.to_s).join("\n")
      raise ArgumentError.new("Invalid YAML:\n#{msg}")
    end

    private def self.validate_root_mapping(
      node : YAML::Nodes::Mapping,
      errors : Array(YamlError),
    )
      validate_mapping_keys(
        node,
        required: ["schema_version", "vdates"],
        errors: errors
      )

      pair =
        node.nodes
          .each_slice(2)
          .find do |slice|
            key = slice[0]
            key.is_a?(YAML::Nodes::Scalar) && key.value == "vdates"
          end

      vdates_node = pair ? pair[1] : nil

      unless vdates_node.is_a?(YAML::Nodes::Sequence)
        errors << YamlError.new("'vdates' must be a sequence", node)
        return
      end

      validate_vdates(vdates_node, errors)
    end

    private def self.validate_mapping_keys(
      node : YAML::Nodes::Mapping,
      *,
      required : Array(String) = [] of String,
      allowed : Array(String)? = nil,
      errors : Array(YamlError),
    ) : Set(String)
      seen = {} of String => YAML::Nodes::Scalar
      keys = Set(String).new

      nodes = node.nodes
      i = 0

      while i < nodes.size
        key_node = nodes[i]

        if key_node.is_a?(YAML::Nodes::Scalar)
          key = key_node.value

          if prev = seen[key]?
            errors << YamlError.new(
              "Duplicate key '#{key}' (previous definition at line #{prev.start_line + 1})",
              key_node
            )
          else
            seen[key] = key_node
            keys << key
          end

          if allowed && !allowed.includes?(key)
            errors << YamlError.new("Unknown key '#{key}'", key_node)
          end
        end

        i += 2
      end

      required.each do |req|
        unless keys.includes?(req)
          errors << YamlError.new("Missing '#{req}'", node)
        end
      end

      keys
    end

    private def self.validate_vdates(
      seq : YAML::Nodes::Sequence,
      errors : Array(YamlError),
    )
      seq.nodes.each do |vdate_node|
        unless vdate_node.is_a?(YAML::Nodes::Mapping)
          errors << YamlError.new("Each vdate must be a mapping", vdate_node)
          next
        end

        validate_mapping_keys(
          vdate_node,
          required: ["id"],
          errors: errors
        )

        nodes = vdate_node.nodes
        i = 0

        while i + 1 < nodes.size
          key_node = nodes[i]
          val = nodes[i + 1]
          i += 2

          # A non-scalar key (e.g. a YAML complex key) is not one of ours
          next unless key_node.is_a?(YAML::Nodes::Scalar)
          next unless val.is_a?(YAML::Nodes::Scalar)

          case key_node.value
          when "parallel"
            p = val.value.to_i?
            if p && p < 1
              errors << YamlError.new("'parallel' must be >= 1", val)
            end
          when "duration"
            d = val.value.to_f?
            if d && d < 0
              errors << YamlError.new("'duration' must be >= 0", val)
            end
          end
        end
      end
    end
  end

  # Various unspecific helpers below

  def resolve_dependencies!(index : Hash(String, VirtualDate))
    return if @depends_on_ids.empty?

    @depends_on = @depends_on_ids.compact_map do |id|
      index[id]? || raise ArgumentError.new("Unknown dependency '#{id}'")
    end
  end

  # `YAML::Serializable` tests a converter-backed property for truthiness
  # before handing it to the converter, so a value of `false` is written out as
  # null and read back as `nil`. For `shift` that would turn "due but
  # unschedulable" into "not scheduled at all" -- and `false` is its default --
  # while for `on` it would drop a hard "never on" override altogether. Both
  # are therefore emitted here; reading them still goes through
  # `ShiftConverter`.
  protected def on_to_yaml(yaml : YAML::Nodes::Builder)
    yaml.scalar "shift"
    ShiftConverter.to_yaml @shift, yaml

    unless (status = @on).nil?
      yaml.scalar "on"
      ShiftConverter.to_yaml status, yaml
    end

    # Dependencies built in code live in `#depends_on`, while ids read from
    # YAML stay in `#depends_on_ids` until `#resolve_dependencies!` links them
    # up; whichever of the two holds them is written out. Deriving the ids here
    # rather than assigning them keeps `#to_yaml` from altering the very object
    # it is serializing -- which it used to do, changing what a later
    # `Scheduler#build` made of the same vdate.
    yaml.scalar "depends_on"
    (@depends_on.empty? ? @depends_on_ids : @depends_on.map(&.id)).to_yaml yaml
  end

  private def unwrap_shift_result(r : VirtualTime::Result::Result) : Time::Span?
    case r
    when VirtualTime::Result::Found
      r.delta
    else
      nil
    end
  end

  class VirtualTimeOrTimeConverter
    def self.to_yaml(value : VirtualTime::TimeOrVirtualTime?, yaml : YAML::Nodes::Builder)
      case value
      when Time
        # Must be RFC 3339, because that is the only absolute-time format
        # `.from_yaml` recognizes. `Time#to_s` renders "2023-05-10 10:00:00
        # +02:00", which fails to parse and would then be misread as a
        # VirtualTime rule.
        yaml.scalar value.to_rfc3339(fraction_digits: 9)
      when VirtualTime
        yaml.scalar value.to_yaml
      when Nil
        yaml.scalar nil
      end
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : VirtualTime::TimeOrVirtualTime?
      return nil if YAML::Schema::Core.parse_null?(node)

      unless node.is_a?(YAML::Nodes::Scalar)
        node.raise "Expected Time or VirtualTime"
      end

      value = node.value

      # 1. Absolute time
      begin
        return Time.parse_rfc3339(value)
      rescue Time::Format::Error
        # Not an absolute time; fall through to parsing it as a rule
      end

      # 2. VirtualTime rule
      VirtualTime.from_yaml(value)
    end
  end

  # Renders and parses a `Time::Span` as a number of seconds.
  #
  # Whole spans are written as plain integers. Sub-second spans keep their
  # fractional part, so that e.g. a `shift` of 500 milliseconds survives a
  # round-trip instead of truncating to `0` -- which would silently read back
  # as "no shift at all".
  module SecondsSpan
    PATTERN = /\A-?\d+(?:\.\d+)?\z/

    # Returns `value` rendered as a (possibly fractional) number of seconds.
    def self.to_scalar(value : Time::Span) : String
      nanoseconds = value.nanoseconds
      return value.to_i.to_s if nanoseconds == 0

      sign = value < Time::Span.zero ? "-" : ""
      fraction = nanoseconds.abs.to_s.rjust(9, '0').rstrip('0')
      "#{sign}#{value.to_i.abs}.#{fraction}"
    end

    # Returns the `Time::Span` `value` denotes, or `nil` if it is not a number.
    def self.from_scalar?(value : String) : Time::Span?
      return nil unless value.matches? PATTERN

      seconds, _, fraction = value.partition '.'
      span = Time::Span.new(
        seconds: seconds.lchop('-').to_i64,
        nanoseconds: fraction.empty? ? 0i64 : fraction.ljust(9, '0')[0, 9].to_i64
      )

      seconds.starts_with?('-') ? -span : span
    end
  end

  class TimeSpanSecondsConverter
    def self.to_yaml(value : Time::Span, yaml : YAML::Nodes::Builder)
      yaml.scalar SecondsSpan.to_scalar value
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Time::Span
      unless node.is_a?(YAML::Nodes::Scalar)
        node.raise "Expected a number of seconds for Time::Span"
      end
      SecondsSpan.from_scalar?(node.value) ||
        node.raise "Expected a number of seconds for Time::Span, got #{node.value.inspect}"
    end
  end

  class NullableTimeSpanSecondsConverter
    def self.to_yaml(value : Time::Span?, yaml : YAML::Nodes::Builder)
      if value
        yaml.scalar SecondsSpan.to_scalar value
      else
        yaml.scalar nil
      end
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Time::Span?
      return nil if YAML::Schema::Core.parse_null?(node)
      unless node.is_a?(YAML::Nodes::Scalar)
        node.raise "Expected a number of seconds for Time::Span?"
      end
      SecondsSpan.from_scalar?(node.value) ||
        node.raise "Expected a number of seconds for Time::Span?, got #{node.value.inspect}"
    end
  end

  class ShiftConverter
    def self.to_yaml(value : Nil | Bool | Time::Span, yaml : YAML::Nodes::Builder)
      case value
      when Nil
        yaml.scalar nil
      when Bool
        yaml.scalar value
      when Time::Span
        yaml.scalar SecondsSpan.to_scalar value
      end
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Nil | Bool | Time::Span
      return nil if YAML::Schema::Core.parse_null?(node)

      unless node.is_a?(YAML::Nodes::Scalar)
        node.raise "Expected null, bool, or a number of seconds for shift"
      end

      v = node.value

      # Bool
      return true if v == "true"
      return false if v == "false"

      # Seconds
      SecondsSpan.from_scalar?(v) ||
        node.raise "Expected 'true', 'false', or a number of seconds for shift, got #{v.inspect}"
    end
  end

  # Export support

  module ICS
    ICS_TIME_FORMAT = Time::Format.new("%Y%m%dT%H%M%SZ")

    def self.export(
      scheduled_vdates : Array(Scheduled),
      *,
      calendar_name : String = "VirtualDate Schedule",
    ) : String
      now = Time.utc

      lines = [] of String
      lines << "BEGIN:VCALENDAR"
      lines << "VERSION:2.0"
      lines << "PRODID:-//VirtualDate//Scheduler//EN"
      lines << "CALSCALE:GREGORIAN"
      lines << "METHOD:PUBLISH"
      lines << "X-WR-CALNAME:#{escape(calendar_name)}"

      scheduled_vdates.each do |inst|
        lines.concat event(inst, now)
      end

      lines << "END:VCALENDAR"

      String.build do |io|
        lines.each { |line| fold line, io }
      end
    end

    # Maximum length in octets of one content line, per RFC 5545 section 3.1.
    MAX_OCTETS = 75

    # Writes `line` to `io`, wrapped as one or more CRLF-terminated content lines.
    #
    # RFC 5545 limits a content line to 75 octets, and requires longer ones to be
    # split with a CRLF followed by a single space. Splitting must not fall inside
    # a multi-byte character, so the line is measured and cut in bytes at
    # character boundaries.
    private def self.fold(line : String, io : IO) : Nil
      # Fast path: nothing to fold (also the only path for pure-ASCII short lines)
      if line.bytesize <= MAX_OCTETS
        io << line << "\r\n"
        return
      end

      # A continuation line spends one octet on its leading space
      limit = MAX_OCTETS
      octets = 0

      line.each_char do |char|
        size = char.bytesize

        if octets + size > limit
          io << "\r\n "
          limit = MAX_OCTETS - 1
          octets = 0
        end

        io << char
        octets += size
      end

      io << "\r\n"
    end

    private def self.event(inst : Scheduled, now : Time) : Array(String)
      uid = "#{inst.vdate.id}-#{inst.start.to_unix}@virtualdate"

      description = String.build do |io|
        io << inst.explanation
        unless inst.vdate.flags.empty?
          io << "\nFlags: " << inst.vdate.flags.join(", ")
        end
      end

      [
        "BEGIN:VEVENT",
        "UID:#{escape(uid)}",
        "DTSTAMP:#{format_time(now)}",
        "DTSTART:#{format_time(inst.start)}",
        # RFC 5545 section 3.8.2.2 requires DTEND to be strictly later than
        # DTSTART, so a zero-duration vdate leaves it out -- which the RFC
        # defines as an event ending at the very time it starts.
        inst.finish > inst.start ? "DTEND:#{format_time(inst.finish)}" : nil,
        "SUMMARY:#{escape(inst.vdate.id)}",
        "DESCRIPTION:#{escape(description)}",
        categories(inst),
        "END:VEVENT",
      ].compact
    end

    private def self.categories(inst : Scheduled) : String?
      return nil if inst.vdate.flags.empty?
      "CATEGORIES:#{inst.vdate.flags.map { |flag| escape(flag) }.join(",")}"
    end

    private def self.format_time(t : Time) : String
      ICS_TIME_FORMAT.format(t.to_utc)
    end

    # RFC 5545 escaping.
    #
    # The backslash must be escaped first, so that the backslashes introduced by
    # the later substitutions are not escaped a second time. A bare CR is dropped
    # rather than escaped, because RFC 5545 defines no escape for it and only
    # `\n` may appear in a TEXT value.
    private def self.escape(s : String) : String
      s
        .gsub("\\", "\\\\")
        .delete('\r')
        .gsub("\n", "\\n")
        .gsub(",", "\\,")
        .gsub(";", "\\;")
    end
  end
end
