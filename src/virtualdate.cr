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

  # Governs what the Scheduler does with an occurrence that is already running
  # when an absolute (`Time`) `#begin` arrives -- e.g. `due: hour 8..12` with
  # `begin: 10:30`. By default the occurrence is dropped: it began before the
  # vdate existed. With this set, it is clamped to start at `#begin` instead,
  # the same way an occurrence already running at the window's `from` is
  # clamped to `from`. Has no effect on a `VirtualTime`-pattern `#begin`,
  # which is matched as a pattern rather than used as a boundary.
  property? clamp_to_begin : Bool = false

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

  # All mapping keys `.from_yaml` reads, derived from the serialized
  # properties at compile time so `YamlValidator`'s allowed-key check cannot
  # drift from the class. (A method rather than a constant because
  # `instance_vars` is only available inside method bodies.)
  def self.yaml_keys : Array(String)
    {{ @type.instance_vars
         .reject { |ivar| ivar.annotation(::YAML::Field) && ivar.annotation(::YAML::Field)[:ignore] }
         .map { |ivar| ((ivar.annotation(::YAML::Field) && ivar.annotation(::YAML::Field)[:key]) || ivar.name.stringify) } }}
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

    # 2. An `#on` override settles every time alike, so when it is a span every
    #    instant is reachable: the base one span earlier resolves exactly onto
    #    it. `#max_shift`/`#max_shifts` bound omit-driven rescheduling and have
    #    no say over an override, which `#strict_on?` returns before consulting
    #    anything else -- applying them only here would make `#on?` disagree
    #    with the time `#resolve` reports.
    return true if @on.is_a?(Time::Span)

    # 3. Otherwise only a Time::Span shift can produce inverse reachability
    shift = @shift
    return false unless shift.is_a?(Time::Span)
    return false if shift == Time::Span.zero

    # (A log entry could be written about this.)
    return false if shifts_exhausted? max_shifts
    # 4. Inverse successor search:
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

    # The instant `time` stands for, materialized once: the `Time` bounds
    # below and the downstream work all compare against the same one, and a
    # `VirtualTime` question costs a full materialization per ask.
    at = nil
    if time.is_a?(VirtualTime) || a.is_a?(Time) || z.is_a?(Time)
      at = instant_of time, hint
      return unless at
    end

    a.try do |a_val|
      case a_val
      when Time
        return if at.nil? || a_val > at
      else
        return unless a_val.matches?(time)
      end
    end

    z.try do |z_val|
      case z_val
      when Time
        return if at.nil? || z_val < at
      else
        return unless z_val.matches?(time)
      end
    end

    # Convert VirtualTime input to Time for downstream work.
    if time.is_a?(VirtualTime)
      return unless at

      time = at
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
      return false if s == Time::Span.zero
      # (A log entry could be written about this.)
      return false if shifts_exhausted? max_shifts
      # The search is confined to the vdate's own bounds. Without that it walks
      # straight past them, and a vdate whose `#end` says it is "never on after"
      # a date resolves to a time beyond it.
      delta = unwrap_shift_result VirtualTime::Search.shift_from_base(
        time, s,
        domain: Bounds.new(self),
        max_shift: max_shift,
        max_shifts: max_shifts
      ) { |candidate| omit_on?(candidate) == true }
      return delta || false
    end

    nil
  end

  # Returns whether `time` falls within `#begin` and `#end`.
  #
  # A bound that is a `VirtualTime` is matched as a pattern rather than used as
  # an ordering bound, the way `#strict_on?` treats it.
  def within_bounds?(time : Time) : Bool
    if a = @begin
      return false unless a.is_a?(Time) ? a <= time : a.matches?(time)
    end

    if z = @end
      return false unless z.is_a?(Time) ? z >= time : z.matches?(time)
    end

    true
  end

  # Confines an omit-driven shift search to one vdate's `#begin`/`#end` bounds.
  private struct Bounds < VirtualTime::Domain
    def initialize(@vdate : VirtualDate)
    end

    def contains?(time : Time) : Bool
      @vdate.within_bounds? time
    end
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
    return default if times.empty?
    times.each do |vtime|
      return true if vtime.matches?(time)
    end
    nil
  end

  # :ditto:
  #
  # Considers only the date part of each rule.
  def matches_any_date?(time : VirtualTime::TimeOrVirtualTime, times : Array(VirtualTime), default)
    return default if times.empty?
    times.each do |vtime|
      return true if vtime.matches_date?(time)
    end
    nil
  end

  # :ditto:
  #
  # Considers only the time part of each rule.
  def matches_any_time?(time : VirtualTime::TimeOrVirtualTime, times : Array(VirtualTime), default)
    return default if times.empty?
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
  private def instant_of(time : VirtualTime::TimeOrVirtualTime, hint) : Time?
    time.is_a?(Time) ? time : time.to_time(hint)
  rescue ArgumentError
    # A pattern naming no real time -- the 30th of February -- has no instant
    # to compare a bound against. Every `#matches?`-based predicate beside this
    # one lets such a pattern simply never match, rather than raising.
    nil
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
    # Longest duration a vdate can carry: any more and adding it to a start
    # runs off the end of the calendar `Time` can hold.
    MAX_DURATION = Time.utc(9999, 12, 31) - Time.utc(1, 1, 1)

    private def validate_vdates!
      @vdates.each do |vdate|
        if vdate.duration < Time::Span.zero
          raise ArgumentError.new("duration of vdate '#{vdate.id}' must be >= 0")
        end

        if vdate.duration > MAX_DURATION
          raise ArgumentError.new("duration of vdate '#{vdate.id}' is longer than the calendar")
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

      # Vdates knocked out of the schedule by a fixed or higher-priority one;
      # each gets another placement attempt once the pass is over.
      displaced = [] of Scheduled

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

          scheduled_vdate = schedule_candidate(candidate, scheduled_vdates, horizon: to, depended_upon: depended_upon, displaced: displaced)

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

      replace_displaced displaced, scheduled_vdates, to, depended_upon

      scheduled_vdates.sort_by!(&.start)
      scheduled_vdates
    end

    # Gives every displaced occurrence another go at the finished schedule,
    # from the start it lost: conflict resolution walks it forward from there,
    # while `max_shift` stays measured from the occurrence's original start,
    # so the documented *total* bound holds across the displacement. A
    # re-placement can displace in turn -- only ever a strictly lower-priority
    # vdate, so each occurrence re-enters at most once per priority level --
    # and those go back on the queue. The guard is sized to that proof
    # (initial queue × priority levels, at most the vdate count), so it stays
    # a backstop for the reasoning rather than a working limit; a schedule of
    # hundreds of displaced occurrences with no cascading fits well inside it.
    private def replace_displaced(displaced : Array(Scheduled), scheduled_vdates : Array(Scheduled), horizon : Time, depended_upon : Set(VirtualDate)) : Nil
      guard = displaced.size * (@vdates.size + 1) + 64

      until displaced.empty? || (guard -= 1) < 0
        entry = displaced.shift

        candidate = Candidate.new(entry.vdate, entry.start)
        # The history of how the occurrence got here travels with it.
        # (`lines` is `Explanation`'s own Array getter, not `String#lines`.)
        # ameba:disable Performance/ExcessiveAllocations
        entry.explanation.lines.each { |line| candidate.explanation.add line }
        candidate.explanation.add "Attempting re-placement after displacement from #{entry.start}"

        if rescheduled = schedule_candidate(candidate, scheduled_vdates, horizon: horizon, depended_upon: depended_upon, displaced: displaced, origin: entry.origin)
          scheduled_vdates << rescheduled
        end
      end
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

      # Set membership, not `Array#includes?` -- the scan runs once per edge
      known = vdates.to_set

      vdates.each do |vdate|
        vdate.depends_on.each do |dep|
          # A dependency on a vdate that is not being scheduled at all is a
          # configuration error, not a runtime condition: silently ignoring it
          # would schedule the dependent as though it had no dependency.
          # (A dependency that *is* scheduled but has no occurrence in the
          # window remains a skip -- that is a fact about the window.)
          unless known.includes?(dep)
            raise ArgumentError.new(
              "Vdate '#{vdate.id}' depends on '#{dep.id}', which is not among the vdates being scheduled"
            )
          end

          outgoing[dep] << vdate
          indegree[vdate] += 1
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

      # Sorted once; nodes becoming ready later are inserted in order, rather
      # than re-sorting the whole list on every pop.
      ready.sort!(&sorter)

      while ready.size > 0
        n = ready.shift
        result << n

        outgoing[n].each do |dependent|
          indegree[dependent] -= 1
          if indegree[dependent] == 0
            at = ready.bsearch_index { |queued| sorter.call(queued, dependent) > 0 } || ready.size
            ready.insert at, dependent
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
    # occurrence starting at the first matching time, across the due rules taken
    # together: the rules are OR-ed, so "10:00-10:29" beside "10:30-10:59" is one
    # continuous block and not two.
    private def occurrence_starts(vdate : VirtualDate, from : Time, to : Time, granularity : Time::Span, max_candidates : Int32) : Array(Time)
      # An absolute `#begin` inside the window bounds the scan the same way
      # `from` does, when the vdate asks for it: an occurrence already running
      # at `#begin` then starts there, rather than being dropped for having
      # begun before it.
      if vdate.clamp_to_begin? && (b = vdate.begin).is_a?(Time) && b > from
        from = b
        return [] of Time if from >= to
      end

      # No due rules means the vdate is always on; a single candidate at window start
      return [from] if vdate.due.empty?

      # Each rule is scanned for the runs of contiguous matching time it covers,
      # as `{first, last}` pairs, and the runs of all of them are merged. A
      # rule that runs out of budget leaves its own answer complete only up to
      # the last run it emitted, so the merged answer is trusted only below the
      # earliest such point -- and the budget is raised until that reaches as
      # far as the caller asked for. Capping each rule and merging regardless
      # would drop occurrences that come *before* ones it kept, which is not
      # what a limit does.
      # One more than asked for: a rule that spends its budget leaves its own
      # last run out of the trusted set, so a budget of exactly
      # `max_candidates` could never fill it and the scan always ran twice.
      budget = max_candidates == Int32::MAX ? max_candidates : max_candidates + 1

      loop do
        runs, cut = scan_due_rules vdate, from, to, granularity, budget
        starts = merge_runs(runs.reject { |(start, _)| start >= cut }, granularity)

        return starts.first(max_candidates) if cut == to || starts.size >= max_candidates || budget >= MAX_RULE_ITERATIONS

        budget *= 2
      end
    end

    # Scans every due rule for its runs, and returns them together with the
    # point below which the collected set is complete -- `to` when every rule
    # was scanned to the end of the window.
    # ameba:disable Metrics/CyclomaticComplexity
    private def scan_due_rules(vdate : VirtualDate, from : Time, to : Time, granularity : Time::Span, budget : Int32) : Tuple(Array(Tuple(Time, Time)), Time)
      runs = [] of Tuple(Time, Time)
      cut = to

      vdate.due.each do |vtime|
        head = first_occurrence vtime, from
        next unless head && head < to

        # Stepped from just before the head, so that the head itself is the
        # first thing yielded. The first instant the calendar holds has nothing
        # before it, and there the head is handed over by hand instead.
        pending_head = false
        iter =
          begin
            vtime.step(granularity, from: head - 1.nanosecond)
          rescue ArgumentError
            pending_head = true

            begin
              vtime.step(granularity, from: head)
            rescue ArgumentError
              next
            end
          end

        iterations = 0
        prev = nil
        run_start = nil
        run_finish = nil
        run_open = false
        rule_runs = 0
        last_start = nil
        # Where the next run may first begin. A stride past the last match seen
        # is that point; anything nearer would have merged.
        floor = from

        loop do
          if pending_head
            pending_head = false
            t = head
          else
            yielded = iter.next
            break unless yielded.is_a?(Time)

            t = yielded
          end
          # Iterator not advancing (fully-fixed rule reached its only match)
          break if prev && t <= prev

          iterations += 1
          if iterations > MAX_RULE_ITERATIONS
            raise ArgumentError.new("Occurrence scan exceeded #{MAX_RULE_ITERATIONS} steps for a due rule of vdate '#{vdate.id}'; use a coarser granularity or a narrower window")
          end

          prev = t

          # A run reaches as far as its matching stretches carry it, so what
          # decides whether the scan is still inside one is the distance from
          # its end -- not from the last time the scan happened to land on.
          # An end the walk only got part way to says nothing about where the
          # run stops, so it is carried on as far as `t` before being read.
          while (opened = run_start) && (finish = run_finish) && run_open && finish < t
            finish, run_open = run_end vtime, finish, granularity, to
            run_finish = finish
            # Recorded here rather than only where the run goes on to absorb
            # `t`: a carry the scan then walks away from is still the run's
            # end, and leaving the stale one standing puts a gap in front of
            # the next occurrence that the rules do not have.
            runs[-1] = {opened, finish}
          end

          if (finish = run_finish) && (opened = run_start) && (t - finish) <= granularity
            if t > finish
              finish, run_open = run_end vtime, t, granularity, to
              run_finish = finish
            end
            runs[-1] = {opened, finish}
          else
            # A new run. Its start is the first matching time the scan could
            # have reached, which the stride can overshoot exactly as it could
            # the head -- and by an amount that depends on where the caller
            # began looking. A stride past the last match seen is where the
            # next run can first begin; anything nearer would have merged.
            start = first_occurrence(vtime, floor) || t
            start = t if start > t

            break if start >= to

            run_start = start
            ending, run_open = run_end vtime, start, granularity, to
            runs << {start, ending}
            rule_runs += 1
            last_start = start

            # The search can reach back past the stride's own yield, and the
            # run it opens there need not reach as far as `t`. What the scan
            # landed on is a match of its own and begins a second run rather
            # than being dropped.
            if (t - ending) > granularity
              run_start = t
              ending, run_open = run_end vtime, t, granularity, to
              runs << {t, ending}
              rule_runs += 1
              last_start = t
            end

            run_finish = ending
          end

          break if t >= to

          if rule_runs >= budget
            # Out of budget: everything this rule has to say below its last run
            # is known, nothing above it is.
            cut = last_start if last_start && last_start < cut
            break
          end

          # Once a run's end is settled there is nothing left to learn by
          # striding through the rest of it -- the next run cannot begin until
          # more than `granularity` past that end, so the scan resumes from
          # there. Walking it instead costs a stride per matching minute, and a
          # rule as ordinary as office hours over a year exhausts
          # `MAX_RULE_ITERATIONS` long before it runs out of occurrences.
          if (settled = run_finish) && !run_open
            break if settled >= to

            iter = begin
              floor = settled + granularity + 1.nanosecond
              break if floor >= to

              vtime.step(granularity, from: settled + granularity)
            rescue ArgumentError
              # Off the end of the calendar, which is past the window either way
              break
            end

            prev = nil
            run_start = nil
            run_finish = nil
          else
            floor = t + granularity
          end
        end
      end

      {runs, cut}
    end

    # How many times `#first_occurrence` re-asks with a more canonical hint
    # before settling. Two rounds cover the shapes that arise; the third only
    # confirms that nothing moved.
    MAX_SEED_REFINEMENTS = 3

    # Returns the first time at or after `from` that `vtime` matches, or nil if
    # it never does.
    #
    # `VirtualTime` fills a rule's unconstrained fields from the hint it is
    # handed, so materializing straight from `from` overshoots: a rule naming
    # only a month, asked from the 28th, lands on the 28th of that month rather
    # than its 1st, and the occurrences a vdate has would depend on when the
    # caller happened to start looking. The answer is refined by re-asking from
    # the start of the unit it fell in -- minute, hour, day, month, year --
    # keeping whichever lands earliest while still being at or after `from`.
    private def first_occurrence(vtime : VirtualTime, from : Time) : Time?
      best = materialize_at vtime, from
      return nil unless best

      # Seeds are taken from the unit boundaries around `from` as well as
      # around the answer so far. Only the latter would leave a rule whose
      # first pass overshot into a later month with no way back: the seed that
      # would have found the earlier month lies behind the overshoot.
      seeds = ->(answer : Time) { unit_starts(from) + unit_starts(answer) }

      VirtualTime::TimeHelper.refine_earliest best, from, MAX_SEED_REFINEMENTS, seeds do |seed|
        materialize_at vtime, seed
      end
    end

    # Furthest the run walk follows matching stretches in one call. A walk that
    # stops here says so, and the caller resumes it from where it left off, so
    # the work over a whole run stays proportional to the stretches in it.
    MAX_RUN_STEPS = 512

    # Returns the last instant of the run of matching time that `at` belongs
    # to: the end of its own matching stretch, carried on over any further
    # stretches that each begin within `granularity` of the last. The second
    # element of the pair says whether the walk gave up with the run still
    # going, in which case the first is a lower bound and not the end.
    #
    # The scan strides by `granularity` and yields only the matches it lands
    # on, so it sees neither where a matching stretch ends nor the ones lying
    # between its yields. Both have to be worked out from the rule itself, or a
    # rule matching every third minute scanned at five -- which yields every
    # sixth -- would look like a series of separate occurrences.
    #
    # Nothing past `limit` is of interest: every run starts before it, so an end
    # that reaches it already covers whatever else there is to merge with.
    private def run_end(vtime : VirtualTime, at : Time, granularity : Time::Span, limit : Time) : Tuple(Time, Bool)
      ending = match_block_end vtime, at

      MAX_RUN_STEPS.times do
        return {ending, false} if ending >= limit

        resumes = materialize_at vtime, ending + 1.nanosecond
        return {ending, false} unless resumes

        # A rule's unconstrained fields are filled from the hint it is handed,
        # and where a transition has cut the stretch short that hint carries
        # the transition's own clock -- so the answer lands past the start of
        # the stretch resuming on the far side, and the run reads as beginning
        # in its own middle. Refining costs a good many materializations, so it
        # is done only where a transition really does lie between the two.
        if resumes.offset != ending.offset
          refined = first_occurrence vtime, ending + 1.nanosecond
          resumes = refined if refined
        end

        return {ending, false} if (resumes - ending) > granularity

        moved = match_block_end vtime, resumes
        return {ending, false} if moved <= ending

        ending = moved
      end

      {ending, true}
    end

    # Returns the last instant of the stretch of matching time that `at`
    # belongs to.
    #
    # A rule matches continuously for as long as its finest constrained field
    # holds: `minute: 6` matches every instant of that minute, `hour: 20` every
    # instant of that hour. Where nothing finer than the date is named, the
    # stretch runs to the end of the day.
    private def match_block_end(vtime : VirtualTime, at : Time, depth : Int32 = 0) : Time # ameba:disable Metrics/CyclomaticComplexity
      last =
        if constrains?(vtime.nanosecond, 1_000_000_000)
          # Both name an offset within the same second rather than one nested
          # in the other, so a stretch runs only as far as the two agree
          nanos = contiguous_last vtime.nanosecond, at.nanosecond, 1_000_000_000
          if constrains? vtime.millisecond, 1_000
            within_ms = (contiguous_last(vtime.millisecond, at.nanosecond // 1_000_000, 1_000) + 1) * 1_000_000 - 1
            nanos = within_ms if within_ms < nanos
          end
          {at.hour, at.minute, at.second, nanos}
        elsif constrains?(vtime.millisecond, 1_000)
          {at.hour, at.minute, at.second,
           (contiguous_last(vtime.millisecond, at.nanosecond // 1_000_000, 1_000) + 1) * 1_000_000 - 1}
        elsif constrains?(vtime.second, 60)
          {at.hour, at.minute, contiguous_last(vtime.second, at.second, 60), 999_999_999}
        elsif constrains?(vtime.minute, 60)
          {at.hour, contiguous_last(vtime.minute, at.minute, 60), 59, 999_999_999}
        elsif constrains?(vtime.hour, 24)
          {contiguous_last(vtime.hour, at.hour, 24), 59, 59, 999_999_999}
        else
          {23, 59, 59, 999_999_999}
        end

      # How far the stretch reaches is a question about wall clocks, but the
      # answer has to be an instant -- so the wall-clock distance is measured
      # naively and added on. Where no transition falls inside, the two agree
      # and the offset comes out unchanged; a rebuild through `Time.local`
      # would instead have to guess which side of a fold to land on, and for a
      # clock a gap swallowed it can land before `at` altogether.
      span = Time.utc(at.year, at.month, at.day, last[0], last[1], last[2], nanosecond: last[3]) -
             Time.utc(at.year, at.month, at.day, at.hour, at.minute, at.second, nanosecond: at.nanosecond)
      return at if span <= Time::Span.zero

      ending = at + span
      return ending if ending.offset == at.offset || depth >= MAX_BLOCK_TRANSITIONS

      # A transition falls inside. Whether the stretch carries on past it is
      # settled by asking the rule about the clock on the far side: a
      # fall-back that repeats matching time carries on, a gap that skips to a
      # clock the rule refuses ends the stretch where the gap begins.
      crossing = VirtualTime::TimeHelper.transition_between at, ending
      return ending unless crossing

      vtime.matches?(crossing) ? match_block_end(vtime, crossing, depth + 1) : crossing - 1.nanosecond
    end

    # Furthest a single matching stretch is followed across UTC offset changes.
    # Two is already more than any zone puts inside one.
    MAX_BLOCK_TRANSITIONS = 3

    # Returns the largest value at or above `from` that the field allows with
    # every value between the two allowed as well.
    #
    # A rule matches continuously for as long as its finest constrained field
    # keeps saying yes, and consecutive allowed values are one stretch, not one
    # each: `nanosecond: 0..500_000_000` matches for half of every second, and
    # counting that as five hundred million stretches is what turns a
    # millisecond of window into half a second of work. Read from the bounds,
    # never by walking them.
    private def contiguous_last(value, from : Int32, size : Int32) : Int32 # ameba:disable Metrics/CyclomaticComplexity
      case value
      when Nil
        size - 1
      when Bool
        value ? size - 1 : from
      when Range(Int32, Int32)
        return from if value.begin < 0 || value.end < 0

        last = value.exclusive? ? value.end - 1 : value.end
        last < from ? from : {last, size - 1}.min
      when Array(Int32), Set(Int32)
        return from if value.any?(&.<(0))

        last = from
        # `Array#to_a` hands back the array itself, so it is sorted as a copy --
        # this is a query, and reordering the caller's own rule is not its place
        value.to_a.sort.each { |allowed| last = allowed if allowed == last + 1 }
        last
      when Steppable::StepIterator(Int32, Int32, Int32)
        return from unless value.step == 1 && value.current >= 0 && value.limit >= 0

        last = value.exclusive ? value.limit - 1 : value.limit
        last < from ? from : {last, size - 1}.min
      else
        from
      end
    end

    # Returns whether `value` narrows a field at all.
    #
    # A rule letting every value of a field through matches for as long as the
    # field above it does; counting it as a constraint would cut one continuous
    # stretch into as many as the field has values -- a thousand per second for
    # `millisecond: 0..999`, a billion for the nanoseconds under it -- and the
    # run walk would then step through every one of them.
    private def constrains?(value, size : Int32) : Bool
      case value
      when Nil
        false
      when Bool
        # `true` lets everything through; `false` nothing, and a rule matching
        # nothing has no stretch to measure either way
        !value
      when Range(Int32, Int32)
        last = value.exclusive? ? value.end - 1 : value.end
        !(value.begin <= 0 && last >= size - 1)
      when Array(Int32), Set(Int32)
        value.size < size || !(0...size).all? { |v| value.includes? v }
      else
        true
      end
    end

    # Returns the first time at or after `hint` that `vtime` matches.
    #
    # `VirtualTime#succ` rather than `#to_time`, for the sake of the extra it
    # does: a DST fall-back repeats a stretch of wall clock, and only `#succ`
    # looks into the repeat -- materialization on its own meets each wall clock
    # once and steps over the second occurrence.
    private def materialize_at(vtime : VirtualTime, hint : Time) : Time?
      # Asked from just before the hint, so that a match *at* it counts. The
      # first instant the calendar holds has no such point, and there
      # materializing from the hint itself answers the same question.
      begin
        return vtime.succ hint - 1.nanosecond
      rescue ArgumentError
        # Either the rule cannot be satisfied from here or there is nothing
        # before the hint to ask from; the latter is worth a second look
      end

      at = vtime.to_time hint
      at >= hint ? at : nil
    rescue ArgumentError
      # The rule cannot be satisfied from here
      nil
    end

    # Returns the starts of the minute, hour, day, month and year `time` falls in.
    private def unit_starts(time : Time) : Array(Time)
      location = time.location

      # The sub-minute boundaries are reached by instant arithmetic: nothing
      # that short is rebuilt from a wall clock, so neither a gap nor a fold
      # has any say over them. Without them a rule constraining `#second` or
      # finer has no seed that reaches the start of its own matching stretch,
      # and whatever fraction the floor happened to carry leaks into the
      # answer -- an occurrence reported a fraction of a second late.
      [
        time - time.nanosecond.nanoseconds,
        time - (time.nanosecond % 1_000_000).nanoseconds,
      ] + [
        unit_start(time.year, time.month, time.day, time.hour, time.minute, location),
        unit_start(time.year, time.month, time.day, time.hour, 0, location),
        unit_start(time.year, time.month, time.day, 0, 0, location),
        unit_start(time.year, time.month, 1, 0, 0, location),
        unit_start(time.year, 1, 1, 0, 0, location),
      ].compact.flat_map { |seed| fold_twins seed }
    end

    # Returns every instant sharing `time`'s wall clock, `time` itself first.
    #
    # A DST fall-back gives one wall clock two instants and `Time.local`
    # settles on one of them without saying which -- the earlier in
    # America/New_York, the later in Europe/Zagreb. A seed built from
    # wall-clock fields therefore lands in whichever pass the zone prefers, and
    # when the search is in the other one the seed sits behind its floor and is
    # thrown away, leaving the overshoot it was meant to correct standing.
    # Offering both leaves the choice to the search.
    private def fold_twins(time : Time) : Array(Time)
      fold = VirtualTime::TimeHelper.dst_fold_at time
      return [time] unless fold > Time::Span.zero

      twins = [time]
      [time + fold, time - fold].each do |twin|
        twins << twin if VirtualTime::TimeHelper.same_wall_clock? twin, time
      end
      twins
    rescue ArgumentError
      # Too near the end of the representable calendar to look either way
      [time]
    end

    # Returns the first instant of the unit that begins on the given wall clock.
    #
    # A DST gap can swallow that wall clock outright -- midnight does not exist
    # in Santiago on the day the clocks go forward -- and `Time.local` then
    # hands back a neighbouring instant that reads as an *earlier* clock. Such a
    # seed is worse than none: a rule's unconstrained fields are filled from the
    # hint it is given, so a seed reading 23:00 of the previous day sends the
    # search to 23:00 rather than to the start of the day it stands for. Where
    # the wall clock is missing, the unit begins where the gap ends.
    private def unit_start(year : Int32, month : Int32, day : Int32, hour : Int32, minute : Int32, location : Time::Location) : Time?
      if exact = VirtualTime::TimeHelper.local? year, month, day, hour, minute, location: location
        return exact
      end

      wanted = Time.local year, month, day, hour, minute, 0, location: location
      skew = Time.utc(year, month, day, hour, minute, 0) -
             Time.utc(wanted.year, wanted.month, wanted.day, wanted.hour, wanted.minute, wanted.second)
      return unless skew > Time::Span.zero

      wanted + skew
    rescue ArgumentError
      nil
    end

    # Returns the start of each run once overlapping and adjacent runs -- those
    # no more than `granularity` apart -- have been merged into one.
    private def merge_runs(runs : Array(Tuple(Time, Time)), granularity : Time::Span) : Array(Time)
      return [] of Time if runs.empty?

      runs.sort_by! &.[0]

      starts = [] of Time
      current_start, current_end = runs.first

      runs.each do |(run_start, run_end)|
        if (run_start - current_end) <= granularity
          current_end = run_end if run_end > current_end
        else
          starts << current_start
          current_start, current_end = run_start, run_end
        end
      end

      starts << current_start
      starts
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
    # ameba:disable Metrics/CyclomaticComplexity
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
        # The window is half-open, so a start of exactly `to` is outside it --
        # and a negative shift can just as well carry an occurrence out the
        # other side, before `from`
        next if start < from || start >= to
        # Different bases can shift-resolve to the same start; schedule it once
        next unless seen_starts.add?(start)

        if (stagger = vdate.stagger) && vdate.parallel > 1
          raise ArgumentError.new("stagger must be positive") if stagger <= 0.seconds

          vdate.parallel.times do |i|
            t = start + stagger * i
            break if t >= to
            break if candidates.size >= max_candidates

            # The same two exemptions the placement guard makes: `shift = true`
            # is the policy that keeps an omitted time, and a non-nil `#on`
            # overrides omission outright. Turning `#stagger` on is not meant
            # to decide whether an occurrence exists at all.
            next if vdate.on.nil? && vdate.shift != true && vdate.omit_on?(t)

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
    #
    # A `Scheduled` this call displaces is appended to `displaced` when one is
    # given, so the caller can try to place it again; without one the
    # displacement is final.
    #
    # `origin` overrides where `max_shift` is measured from -- a re-placement
    # after displacement passes the occurrence's original start, so the
    # documented *total* shift bound holds across the displacement rather than
    # restarting at the start it lost.
    # ameba:disable Metrics/CyclomaticComplexity
    def schedule_candidate(candidate : Candidate, scheduled_vdates : Array(Scheduled), *, horizon : Time, depended_upon : Set(VirtualDate) = vdates_with_dependents, displaced : Array(Scheduled)? = nil, origin : Time? = nil) : Scheduled?
      vdate = candidate.vdate
      start = candidate.start
      duration = vdate.duration
      explanation = candidate.explanation

      # Conflict resolution moves a vdate forward, so it is bounded by the same
      # two limits as omit-driven rescheduling -- otherwise a `max_shift` of
      # half an hour would not stop a 10:00 vdate from ending up at 23:00.
      origin = origin || start
      previous_start = start
      max_shift = vdate.max_shift
      max_shifts = vdate.max_shifts
      shifts = 0

      # A `VirtualTime` deadline is resolved once, against the occurrence this
      # candidate came from. Resolving it afresh at each shifted start would
      # hand the vdate a new deadline every time it moved -- tomorrow's 17:00
      # once it had slipped past today's -- so it could never miss one.
      # A rule naming no real time -- the 30th of February -- cannot be
      # materialized. Every other `VirtualTime`-valued field tolerates one of
      # those by simply never matching, and a deadline that can never arrive is
      # a deadline the vdate can never meet.
      deadline_time =
        case deadline = vdate.deadline
        when Time
          deadline
        when VirtualTime
          begin
            deadline.to_time start
          rescue ArgumentError
            explanation.add "Rejected: deadline #{deadline} names no real time"
            return nil
          end
        end

      # Every step forward uses the vdate's own shift when it has a usable one.
      # A zero or negative shift would never get past a conflict (looping for
      # ever), so those fall back to the default step.
      shift_span =
        case s = vdate.shift
        when Time::Span
          s > Time::Span.zero ? s : 1.minute
        else
          1.minute
        end

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

        # A start the scheduler picked itself -- moving past a conflict, or
        # meeting a dependency floor -- must not land on a time the vdate is
        # omitted from. `shift = true` is the one policy that says an omitted
        # time is to be kept, and starts that came straight from `#resolve`
        # have had the vdate's own omit policy applied already.
        if vdate.on.nil? && vdate.shift != true && vdate.omit_on? start
          explanation.add "Shifted on from omitted time #{start} to #{start + shift_span}"
          start += shift_span
          next
        end

        # Nor outside the vdate's own bounds. `#end` is documented as a time it
        # is never on after, and moving forward can only take it further past
        # one -- `#strict_on?` confines its own shift search for the same
        # reason. An `#on` override sidesteps bounds like everything else.
        if vdate.on.nil? && !vdate.within_bounds?(start)
          explanation.add "Rejected: #{start} falls outside the vdate's begin/end bounds"
          return nil
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

        # Horizon guard. The window is half-open, so a start of exactly the
        # horizon is outside it -- which only a zero-duration vdate could
        # otherwise slip through, its finish being no later than its start.
        # Measuring the duration against the room left rather than adding it on
        # first also keeps one that would run off the end of the calendar from
        # raising where it should simply not fit.
        if start >= horizon || duration > horizon - start
          explanation.add("Rejected: #{start} plus a duration of #{duration} falls outside the window ending #{horizon}")
          return nil
        end

        finish = start + duration

        scheduled = Scheduled.new(vdate, start, explanation, origin: origin)

        if deadline_time
          if finish > deadline_time
            explanation.add "Rejected: finish #{finish} exceeds hard deadline #{deadline_time}"
            return nil
          end
        end

        # Check parallelism / conflicts. A zero-duration vdate overlaps nothing
        # that starts at or after it, but it does overlap anything already under
        # way, so it can be in conflict like any other.
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
            displaced << conflict if displaced
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
            displaced << conflict if displaced
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

        # Equal priority or no decisive conflict → shift forward
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
    # `parallel` states how much overlap a vdate itself tolerates, so everyone
    # the candidate would join has to stay within their own limit too, not just
    # the candidate within its. Counting only the candidate's own overlaps
    # misses the case where a third vdate overlaps two others that do not
    # overlap each other: it passes that test while pushing the one in the
    # middle over its limit.
    private def acceptable_parallelism?(candidate : Scheduled, scheduled_vdates : Array(Scheduled)) : Bool
      return false unless within_parallel_limit? candidate, scheduled_vdates, candidate

      scheduled_vdates.each do |other|
        next unless overlaps?(candidate.start, candidate.finish, other.start, other.finish)
        next unless shares_flag_group?(candidate.vdate, other.vdate)
        return false unless within_parallel_limit? other, scheduled_vdates, candidate
      end

      true
    end

    # Returns whether `subject` stays within its own `#parallel` limit once
    # `candidate` joins `scheduled_vdates`.
    #
    # `#parallel` counts the vdates sharing *any* flag with this one, the same
    # union `#shares_flag_group?` uses to spot a conflict -- counting each flag
    # separately would let a vdate with two flags overlap its limit once over
    # in each of them.
    private def within_parallel_limit?(subject : Scheduled, scheduled_vdates : Array(Scheduled), candidate : Scheduled) : Bool
      limit = subject.vdate.parallel
      concurrent = competes?(subject, candidate) ? 1 : 0
      return false if concurrent + 1 > limit

      scheduled_vdates.each do |other|
        if competes?(subject, other)
          concurrent += 1
          return false if concurrent + 1 > limit
        end
      end

      true
    end

    @[AlwaysInline]
    private def competes?(subject : Scheduled, other : Scheduled) : Bool
      return false if other.same? subject
      return false unless shares_flag_group? subject.vdate, other.vdate

      overlaps? subject.start, subject.finish, other.start, other.finish
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

    # The start the occurrence was originally due at, before any conflict
    # shifting. `max_shift` is a bound on total displacement from here, and it
    # has to survive the occurrence being displaced and placed again.
    getter origin : Time

    def initialize(@vdate : VirtualDate, @start : Time, explanation : VirtualDate::Explanation? = nil, origin : Time? = nil)
      @finish = @start + vdate.duration
      @explanation = explanation || VirtualDate::Explanation.new
      @origin = origin || @start
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
    # Maximum number of messages kept. Once reached, the penultimate line gives
    # way to a notice of how many were dropped.
    MAX_LINES = 100

    # Read-only: `#add` maintains the size invariant the overflow handling
    # below relies on, and an externally assigned short array would break it.
    getter lines : Array(String)

    # How many messages have been dropped for want of room
    getter dropped = 0

    def initialize
      @lines = [] of String
    end

    # Appends `msg`, and returns whether the buffer still had room for it.
    #
    # Once it is full the most recent message is kept in place of the previous
    # one, rather than dropped: the last thing said about a candidate is its
    # verdict, and for a vdate scheduled over a conflict because dependents
    # require it, that line is the only thing telling a deliberate
    # over-subscription apart from a scheduling fault.
    def add(msg : String) : Bool
      if @lines.size >= MAX_LINES
        # The first overflow costs two real messages: the one this replaces,
        # and the one whose slot the notice takes. Later ones cost only the
        # former, the notice being in place by then.
        @dropped += @dropped.zero? ? 2 : 1
        @lines[-2] = "... #{@dropped} message(s) dropped (limit: #{MAX_LINES})"
        @lines[-1] = msg
        return false
      end

      @lines << msg
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
        # so it must run after the root type is known. The already-parsed root
        # is handed over rather than the string, saving a re-parse.
        YamlValidator.validate!(node)

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

      validate! root
    end

    # :ditto: for an already-parsed document root
    def validate!(root : YAML::Nodes::Node)
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
        allowed: ["schema_version", "vdates"],
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

          # An unknown key is far more often a typo silently ignored by the
          # serializer (`durration: 5`) than intentional extra data; documents
          # needing new keys have `schema_version` to say so.
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

    # ameba:disable Metrics/CyclomaticComplexity
    private def self.validate_vdates(
      seq : YAML::Nodes::Sequence,
      errors : Array(YamlError),
    )
      seq.nodes.each do |node|
        # A YAML alias stands for the node it was anchored to -- which is what
        # `#to_yaml` emits for a vdate that appears twice, and what a
        # hand-written document uses to share one definition
        vdate_node = node.is_a?(YAML::Nodes::Alias) ? (node.value || node) : node

        unless vdate_node.is_a?(YAML::Nodes::Mapping)
          errors << YamlError.new("Each vdate must be a mapping", vdate_node)
          next
        end

        validate_mapping_keys(
          vdate_node,
          required: ["id"],
          allowed: VirtualDate.yaml_keys,
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

    # From here on the object graph is the one source of truth. Ids left behind
    # would put back a dependency taken out of `#depends_on` -- on the next
    # resolve, and on save, where they are the fallback.
    @depends_on_ids.clear
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
    # `Scheduler#build` made of the same vdate. No dependencies at all is the
    # field's default and is not worth a `depends_on: []` line in every vdate.
    ids = @depends_on.empty? ? @depends_on_ids : @depends_on.map(&.id)
    unless ids.empty?
      yaml.scalar "depends_on"
      ids.to_yaml yaml
    end
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
      begin
        VirtualTime.from_yaml(value)
      rescue e : YAML::ParseException | ArgumentError
        # Re-raised at the node's own position: the inner parse counts lines
        # within the scalar it was handed, which reads as "line 1, column 1"
        # wherever the value sits in the user's document.
        node.raise "Expected an RFC 3339 time or a VirtualTime rule, got #{value.inspect} (#{e.message})"
      end
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
      seconds = value.to_i
      return seconds.to_s if nanoseconds == 0

      # The whole part is rendered as it stands rather than as a sign plus its
      # magnitude: `Int64::MIN` -- the seconds of `Time::Span::MIN` -- has no
      # positive counterpart, and asking for one overflows. Only the "-0.5"
      # shape needs the sign put back by hand.
      whole = seconds == 0 && value < Time::Span.zero ? "-0" : seconds.to_s
      fraction = nanoseconds.abs.to_s.rjust(9, '0').rstrip('0')

      "#{whole}.#{fraction}"
    end

    # Returns the `Time::Span` `value` denotes, or `nil` if it is not a number.
    def self.from_scalar?(value : String) : Time::Span?
      return nil unless value.matches? PATTERN

      seconds, _, fraction = value.partition '.'
      # A number too large for `Int64` matches the pattern but is not a span we
      # can express. Reporting it as "not a number of seconds" lets the caller
      # raise with the document position, the way every other bad value does.
      #
      # The sign is kept on the whole part rather than applied to the finished
      # span, since negating `Int64::MIN` -- what `Time::Span::MIN` writes out
      # as -- has no answer, and that value would then be one this could write
      # but not read back.
      whole = seconds.to_i64?
      return nil unless whole

      # Digits beyond the nanosecond (the 9th) are truncated, not rounded --
      # more precision than a `Time::Span` holds cannot round-trip anyway
      nanoseconds = fraction.empty? ? 0i64 : fraction.ljust(9, '0')[0, 9].to_i64
      nanoseconds = -nanoseconds if seconds.starts_with? '-'

      Time::Span.new seconds: whole, nanoseconds: nanoseconds
    end

    # Returns the `Time::Span` `node` carries, raising at the node's own
    # position when it holds anything else.
    def self.from_node(node : YAML::Nodes::Node) : Time::Span
      unless node.is_a?(YAML::Nodes::Scalar)
        node.raise "Expected a number of seconds for Time::Span"
      end

      from_scalar?(node.value) ||
        node.raise "Expected a number of seconds for Time::Span, got #{node.value.inspect}"
    end
  end

  class TimeSpanSecondsConverter
    def self.to_yaml(value : Time::Span, yaml : YAML::Nodes::Builder)
      yaml.scalar SecondsSpan.to_scalar value
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Time::Span
      SecondsSpan.from_node node
    end
  end

  class NullableTimeSpanSecondsConverter
    def self.to_yaml(value : Time::Span?, yaml : YAML::Nodes::Builder)
      yaml.scalar(value ? SecondsSpan.to_scalar(value) : nil)
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Time::Span?
      YAML::Schema::Core.parse_null?(node) ? nil : SecondsSpan.from_node(node)
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

      # Bool, in the spellings the YAML core schema accepts -- a hand-written
      # `True` is a boolean by that schema, and refusing it here while taking
      # the quoted string `'true'` for one reads as arbitrary.
      return true if v.in?("true", "True", "TRUE")
      return false if v.in?("false", "False", "FALSE")

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
      # The stamp carries whole seconds, which `#stagger` can place two
      # occurrences inside; the fraction is appended only where there is one,
      # so that the UID of an event on a whole second stays what it was.
      stamp = inst.start.nanosecond.zero? ? inst.start.to_unix.to_s : "#{inst.start.to_unix}.#{inst.start.nanosecond}"
      uid = "#{inst.vdate.id}-#{stamp}@virtualdate"
      starts_at = format_time inst.start
      ends_at = format_time inst.finish

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
        "DTSTART:#{starts_at}",
        # RFC 5545 section 3.8.2.2 requires DTEND to be strictly later than
        # DTSTART, so a zero-duration vdate leaves it out -- which the RFC
        # defines as an event ending at the very time it starts. The two are
        # compared as rendered, since the format carries whole seconds only and
        # a duration shorter than one would print an identical DTEND.
        ends_at > starts_at ? "DTEND:#{ends_at}" : nil,
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
