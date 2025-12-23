require "virtualtime"

# VirtualDate builds on VirtualTime to represent due/omit rules plus higher-level scheduling semantics.
class VirtualDate
  VERSION_MAJOR    = 1
  VERSION_MINOR    = 2
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
  @[YAML::Field(converter: VirtualDate::ShiftConverter)]
  property shift : Nil | Bool | Time::Span = false

  # Max amount of total time by which vdate can be shifted before it's considered unschedulable (false)
  @[YAML::Field(converter: VirtualDate::NullableTimeSpanSecondsConverter)]
  property max_shift : Time::Span?

  # Max amount of shift attempts, before it's considered unschedulable (false)
  property max_shifts = 1500

  # Fixed override of `#on?` for this vdate. If set, takes precedence over begin/end/due/omit.
  # Same union as `#shift`.
  @[YAML::Field(converter: VirtualDate::ShiftConverter)]
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
  property fixed : Bool = false

  # Optional dependencies: scheduler will try to place this vdate after all dependencies.
  # (Used only by Scheduler; VirtualDate itself does not enforce this.)
  @[YAML::Field(ignore: true)]
  property depends_on = [] of VirtualDate

  # Serialized form
  @[YAML::Field(key: "depends_on")]
  property depends_on_ids = [] of String

  # Optional staggered parallel scheduling
  @[YAML::Field(converter: VirtualDate::NullableTimeSpanSecondsConverter)]
  property stagger : Time::Span? = nil

  # Identifier (important for dependencies)
  property id : String

  # Hard deadline — vdate MUST finish before this time or fails scheduling
  @[YAML::Field(converter: VirtualDate::VirtualTimeOrTimeConverter)]
  property deadline : VirtualTime::TimeOrVirtualTime? = nil

  def initialize(@id : String? = "")
  end

  # Checks if the vdate is effectively scheduled at `time`.
  # Returns:
  # - true if it is on at `time` directly, OR due at some base time that resolves (via shifting) to exactly `time`
  # - false if would be on, but can't be scheduled to a slot
  # Returns Time::Span if it's shifted by some amount
  # Returns nil if not applicable / not scheduled
  #
  # (For omit-driven shifting (Time::Span), we can search candidate base times by shifting back in the opposide direction.
  # This is deterministic, bounded by max_shifts/max_shift.)
  def on?(time : Time, *, max_shift = @max_shift, max_shifts = @max_shifts) : Bool
    # 1. Direct check
    direct = strict_on?(time, max_shift: max_shift, max_shifts: max_shifts, hint: time)
    return true if direct == true
    return false if direct == false

    # 2. Only Time::Span shifts can produce inverse reachability
    shift = @shift
    return false unless shift.is_a?(Time::Span)
    return false if shift.total_nanoseconds == 0

    # TODO write a log about this
    return false if shifts_exhausted? max_shifts
    # 3. Inverse successor search:
    #    Look for a base time such that:
    #      strict_on?(base) => Time::Span delta
    #      base + delta == time
    VirtualTime::Search.is_shifted_from_base?(time, shift, max_shift: max_shift, max_shifts: max_shifts) do |base|
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
        case time
        when Time
          return if a_val > time
        else
          return unless time.matches?(a_val)
        end
      else
        return unless a_val.matches?(time)
      end
    end

    z.try do |z_val|
      case z_val
      when Time
        case time
        when Time
          return if z_val < time
        else
          return unless time.matches?(z_val)
        end
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
      # TODO Write a log about this
      return false if shifts_exhausted? max_shifts
      delta = unwrap_shift_result VirtualTime::Search.shift_from_base(time, s, max_shift: max_shift, max_shifts: max_shifts) { |t| omit_on?(t) == true }
      return delta || false
    end

    nil
  end

  def due_on?(time : VirtualTime::TimeOrVirtualTime = Time.local, times = @due)
    due_on_any_date?(time, times) && due_on_any_time?(time, times)
  end

  def due_on_any_date?(time : VirtualTime::TimeOrVirtualTime = Time.local, times = @due)
    matches_any_date?(time, times, true)
  end

  def due_on_any_time?(time : VirtualTime::TimeOrVirtualTime = Time.local, times = @due)
    matches_any_time?(time, times, true)
  end

  def omit_on?(time : VirtualTime::TimeOrVirtualTime = Time.local, times = @omit)
    omit_on_dates?(time, times) && omit_on_times?(time, times)
  end

  def omit_on_dates?(time : VirtualTime::TimeOrVirtualTime = Time.local, times = @omit)
    matches_any_date?(time, times, nil)
  end

  def omit_on_times?(time : VirtualTime::TimeOrVirtualTime = Time.local, times = @omit)
    matches_any_time?(time, times, nil)
  end

  def matches_any_date?(time : VirtualTime::TimeOrVirtualTime, times : Array(VirtualTime), default)
    return default if times.size == 0
    times.each do |vt|
      return true if vt.matches_date?(time)
    end
    nil
  end

  def matches_any_time?(time : VirtualTime::TimeOrVirtualTime, times : Array(VirtualTime), default)
    return default if times.size == 0
    times.each do |vt|
      return true if vt.matches_time?(time)
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
      index = @vdates.to_h { |t| {t.id, t} }

      @vdates.each do |vdate|
        vdate.resolve_dependencies!(index)
      end

      order_vdates_by_dependencies(@vdates)
    end

    # Produces scheduled vdates in [from, to).
    #
    # Parameters:
    # - granularity: how frequently to generate candidates from due rules (defaults to 1 minute)
    # - max_candidates: safety limit to avoid infinite generation for very broad rules
    #
    # Returns: Array(Scheduled), sorted by start time.
    def build(from : Time, to : Time) : Array(Scheduled)
      validate_no_dependency_cycles!

      scheduled_vdates = [] of Scheduled

      ordered = order_vdates_by_dependencies(@vdates)
      scheduled_index = {} of VirtualDate => Scheduled

      ordered.each do |vdate|
        dependency_floor = vdate.depends_on.any? ? earliest_start_time_after_dependencies(vdate, scheduled_index) : nil
        next if vdate.depends_on.any? && dependency_floor.nil?

        candidates = generate_candidates(vdate, from, to)

        candidates.each do |candidate|
          if dependency_floor
            if dependency_floor && dependency_floor > candidate.start
              candidate = Candidate.new(vdate, dependency_floor)
              candidate.explanation.add("Shifted from #{candidate.start} to #{dependency_floor} to satisfy dependency constraints")
            end
          end

          scheduled_vdate = schedule_candidate(candidate, scheduled_vdates, horizon: to)

          # Dependency vdates must never be dropped
          if scheduled_vdate
            scheduled_vdates << scheduled_vdate
            scheduled_index[scheduled_vdate.vdate] = scheduled_vdate
          elsif vdate.depends_on.empty?
            # Non-dependent vdates may fail silently
            next
          else
            raise ArgumentError.new(
              "Failed to schedule dependency vdate #{vdate.id}"
            )
          end
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
      outgoing = Hash(VirtualDate, Array(VirtualDate)).new { |h, k| h[k] = [] of VirtualDate }

      vdates.each do |t|
        indegree[t] = 0
      end

      vdates.each do |t|
        t.depends_on.each do |dep|
          next unless vdates.includes?(dep)
          outgoing[dep] << t
          indegree[t] = indegree[t] + 1
        end
      end

      # Ready set (indegree 0)
      ready = vdates.select { |t| indegree[t] == 0 }

      # Deterministic ordering:
      # - fixed first (true first)
      # - higher priority first
      # - stable tie-breaker by id (string)
      sorter = ->(a : VirtualDate, b : VirtualDate) do
        # 1. Fixed vdates first
        fa = a.fixed ? 0 : 1
        fb = b.fixed ? 0 : 1
        cmp = fa <=> fb
        return cmp if cmp != 0

        # 2. Higher priority first
        cmp = b.priority <=> a.priority
        return cmp if cmp != 0

        # 3. Stable ordering (ID)
        (a.id || "") <=> (b.id || "")
      end

      result = [] of VirtualDate

      while ready.size > 0
        ready.sort!(&sorter)
        n = ready.shift
        result << n

        outgoing[n].each do |m|
          indegree[m] = indegree[m] - 1
          if indegree[m] == 0
            ready << m
          end
        end
      end

      if result.size != vdates.size
        raise ArgumentError.new("Dependency cycle detected")
      end

      result
    end

    # Finds earliest start time based on the vdate alone, not taking into account dependencies.
    # In essence, vdate start = max( earliest_start_time, earliest_start_time_after_dependencies)
    private def earliest_start_time(vdate : VirtualDate, from : Time, to : Time) : Time?
      t = from
      iterations = 0
      max_iterations = 10_000

      while t <= to
        iterations += 1
        raise ArgumentError.new("earliest_start_time exceeded iteration limit") if iterations > max_iterations

        r = vdate.strict_on?(t)

        case r
        when true
          return t
        when Time::Span
          nt = t + r
          return nt if nt <= to
          return nil
        else
          t += 1.minute
        end
      end

      nil
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

    # Finds earliest valid start time according to VirtualDate#on?
    #
    # Does:
    # - Applies omit rules
    # - Optionally expands into multiple candidates (staggered / parallel vdates)
    #
    # Does not do things that happen later in `schedule_candidate`, such as:
    # - Resolve conflicts
    # - Respect dependencies
    # - Parallelism limits
    # - Check deadlines
    # - Shift due to conflicts
    #
    # - Returns a small, bounded list of concrete Time values wrapped as objects
    private def generate_candidates(vdate : VirtualDate, from : Time, to : Time) : Array(Candidate)
      candidates = [] of Candidate

      start = earliest_start_time(vdate, from, to)
      return candidates unless start

      # Non-staggered (backward-compatible) behavior
      unless vdate.stagger && vdate.parallel > 1
        # Apply omit check to the single produced candidate
        candidate = Candidate.new(vdate, start)
        candidate.explanation.add("Initial candidate at #{start}")
        candidates << candidate
        return candidates
      end

      stagger = vdate.stagger.not_nil!
      raise ArgumentError.new("stagger must be positive") if stagger <= 0.seconds

      vdate.parallel.times do |i|
        t = start + stagger * i
        break if t > to

        next if vdate.omit_on?(t)

        candidate = Candidate.new(vdate, t)
        # candidate.explanation.add("Matched due rule at #{t} (staggered)")
        candidate.explanation.add("Initial staggered candidate ##{i + 1} at #{t} (stagger=#{stagger})")
        candidates << candidate
      end

      candidates
    end

    # Schedules a vdate, resolving conflicts by shifting forward (using vdate.shift when Time::Span),
    # respecting vdate.fixed and max_shift/max_shifts.
    def schedule_candidate(candidate : Candidate, scheduled_vdates : Array(Scheduled), *, horizon : Time) : Scheduled?
      vdate = candidate.vdate
      start = candidate.start
      duration = vdate.duration || 0.seconds

      if duration == 0.seconds
        return nil if start > horizon
        scheduled = Scheduled.new(vdate, start)
        scheduled.explanation.add "Scheduled zero-duration vdate at #{start}"

        if scheduled.explanation.lines.empty?
          scheduled.explanation.add("Scheduled (no additional details)")
        end
        return scheduled
      end

      loop do
        finish = start + duration

        # Horizon guard
        if finish > horizon
          candidate.explanation.add("Rejected: finish #{finish} exceeds horizon #{horizon}")
          return nil
        end

        candidate = Scheduled.new(vdate, start, candidate.explanation)

        if deadline = vdate.deadline
          deadline_time =
            case deadline
            when Time
              deadline
            else
              deadline.to_time(start)
            end

          if finish > deadline_time
            candidate.explanation.add "Rejected: finish #{finish} exceeds hard deadline #{deadline_time}"
            return nil
          end
        end

        # Check parallelism / conflicts
        if acceptable_parallelism?(candidate, scheduled_vdates)
          candidate.explanation.add "Scheduled at #{start}, no conflicts, parallelism OK"

          if candidate.explanation.lines.empty?
            candidate.explanation.add("Scheduled (no additional details)")
          end
          return candidate
        end

        # Conflict exists
        conflict = scheduled_vdates.find do |i|
          overlaps?(start, finish, i.start, i.finish)
        end

        # Fixed vdate rules
        if conflict
          if conflict.vdate.fixed
            # If vdate has dependents, it must be scheduled even if it conflicts
            if has_dependents?(vdate)
              candidate.explanation.add("Scheduled despite conflicts because dependent vdates require it")

              if candidate.explanation.lines.empty?
                candidate.explanation.add("Scheduled (no additional details)")
              end
              return candidate
            end

            # Otherwise respect fixed semantics
            return nil if vdate.fixed

            candidate.explanation.add "Yielded to fixed vdate #{conflict.vdate.id} (#{conflict.start}-#{conflict.finish}), shifted from #{start} to #{conflict.finish}"
            start = conflict.finish
            next
          end

          if vdate.fixed
            scheduled_vdates.delete(conflict)
            candidate.explanation.add "Displaced movable vdate #{conflict.vdate.id} because this vdate is fixed"
            next
          end

          # Priority comparison
          if vdate.priority > conflict.vdate.priority
            scheduled_vdates.delete(conflict)
            candidate.explanation.add "Displaced lower-priority vdate #{conflict.vdate.id} (priority #{conflict.vdate.priority})"
            next
          elsif vdate.priority < conflict.vdate.priority
            candidate.explanation.add "Yielded to higher-priority vdate #{conflict.vdate.id}, shifted from #{start} to #{conflict.finish}"
            start = conflict.finish
            next
          end
        end

        # Equal priority or no decisive conflict → shift forward
        shift_span =
          case s = vdate.shift
          when Time::Span
            s
          else
            1.minute
          end

        candidate.explanation.add("Conflict unresolved; shifted forward by #{shift_span} to #{start + shift_span}")

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

    # Returns whether any vdates depend on this one
    private def has_dependents?(vdate : VirtualDate) : Bool
      @vdates.any? { |t| t.depends_on.includes?(vdate) }
    end

    @[AlwaysInline]
    private def overlaps?(a_start, a_end, b_start, b_end)
      a_start < b_end && b_start < a_end
    end

    # Enforces per-vdate parallelism across overlapping scheduled_vdates sharing flags.
    private def acceptable_parallelism?(candidate : Scheduled, scheduled_vdates : Array(Scheduled)) : Bool
      c_start = candidate.start
      duration = candidate.vdate.duration || 0.seconds
      c_end = c_start + duration

      flags = candidate.flags
      flags = [:__default] if flags.empty?

      flags.each do |flag|
        limit =
          case p = candidate.vdate.parallel
          when Int32
            p
          when Hash(String, Int32)
            p[flag]? || 1
          else
            1
          end

        concurrent = 0

        scheduled_vdates.each do |i|
          i_flags = i.flags
          i_flags = [:__default] if i_flags.empty?
          next unless i_flags.includes?(flag)

          i_start = i.start
          i_end = i_start + (i.vdate.duration || 0.seconds)

          if overlaps?(c_start, c_end, i_start, i_end)
            concurrent += 1
            return false if concurrent + 1 > limit
          end
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

    def fixed : Bool
      vdate.fixed
    end
  end

  # Holds a buffer of string explanations, for scheduling etc.
  struct Explanation
    MAX_LINES = 100

    property lines : Array(String)

    def initialize
      @lines = [] of String
    end

    def add(msg : String)
      if @lines.size > MAX_LINES
        return false
      end

      @lines << msg

      if @lines.size == MAX_LINES
        @lines << "Explanation buffer overflow (limit: #{MAX_LINES} messages)"
        return false
      end

      true
    end

    def to_s
      @lines.join("\n")
    end
  end

  # Files-related stuff (YAML)

  struct VirtualDateFile
    include YAML::Serializable

    property schema_version : Int32
    property vdates : Array(VirtualDate)

    def self.load(yaml : String) : Array(VirtualDate)
      YamlValidator.validate!(yaml)

      doc = YAML::Nodes.parse(yaml)
      node = doc.nodes.first

      case node
      when YAML::Nodes::Mapping
        file = from_yaml(yaml)

        if file.schema_version < Migrator::CURRENT_VERSION
          # ok
        elsif file.schema_version == Migrator::CURRENT_VERSION
          # ok
        else
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

  struct VirtualDateRaw
    include YAML::Serializable

    property id : String
    property due : Array(VirtualTime) = [] of VirtualTime
    property omit : Array(VirtualTime) = [] of VirtualTime
    property duration : Int64? # seconds
    property flags : Array(String)?
    property parallel : Int32?
    property fixed : Bool?
    property depends_on : Array(String)?
  end

  module Migrator
    CURRENT_VERSION = 2

    def self.v1_to_current(raw : Array(VirtualDateRaw)) : Array(VirtualDate)
      vdates = raw.map do |r|
        v = VirtualDate.new
        v.id = r.id
        v.due = r.due
        v.omit = r.omit
        v.duration = (r.duration || 0).seconds
        v.flags = Set(String).new(r.flags || [] of String)
        v.parallel = r.parallel || 1
        v.fixed = r.fixed || false
        v
      end

      resolve_dependencies(vdates, raw)
      vdates
    end

    def self.v2_to_current(raw : Array(VirtualDateRaw)) : Array(VirtualDate)
      # Currently identical to v1, but kept explicit for future changes
      v1_to_current(raw)
    end

    private def self.resolve_dependencies(vdates : Array(VirtualDate), raw : Array(VirtualDateRaw))
      index = vdates.to_h { |t| {t.id, t} }

      raw.each_with_index do |r, i|
        next unless r.depends_on

        r.depends_on.not_nil!.each do |dep_id|
          dep = index[dep_id]?
          raise ArgumentError.new("Unknown dependency '#{dep_id}'") unless dep
          vdates[i].depends_on << dep
        end
      end
    end
  end

  struct YamlError
    getter message : String
    getter line : Int32
    getter column : Int32

    def initialize(@message, node : YAML::Nodes::Node)
      @line = node.start_line + 1
      @column = node.start_column + 1
    end

    def to_s
      "Line #{@line}, column #{@column}: #{@message}"
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
      keys = validate_mapping_keys(
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
        val_node = nodes[i + 1]

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

        keys = validate_mapping_keys(
          vdate_node,
          required: ["id"],
          errors: errors
        )

        nodes = vdate_node.nodes
        i = 0

        while i < nodes.size
          key = nodes[i].as(YAML::Nodes::Scalar).value
          val = nodes[i + 1]

          case key
          when "parallel"
            if val.is_a?(YAML::Nodes::Scalar)
              p = val.value.to_i?
              if p && p < 1
                errors << YamlError.new("'parallel' must be >= 1", val)
              end
            end
          when "duration"
            if val.is_a?(YAML::Nodes::Scalar)
              d = val.value.to_i?
              if d && d < 0
                errors << YamlError.new("'duration' must be >= 0", val)
              end
            end
          end

          i += 2
        end
      end
    end

    private def mapping_to_hash(node : YAML::Nodes::Mapping, errors : Array(YamlError))
      h = {} of String => YAML::Nodes::Node
      seen = {} of String => YAML::Nodes::Scalar

      nodes = node.nodes
      i = 0

      while i < nodes.size
        key_node = nodes[i]
        val_node = nodes[i + 1]

        if key_node.is_a?(YAML::Nodes::Scalar)
          key = key_node.value

          if prev = seen[key]?
            errors << YamlError.new(
              "Duplicate key '#{key}' (previous definition at line #{prev.start_line + 1})",
              key_node
            )
          else
            seen[key] = key_node
          end

          h[key] = val_node
        end

        i += 2
      end

      h
    end
  end

  # Various unspecific helpers below

  def resolve_dependencies!(index : Hash(String, VirtualDate))
    return if @depends_on_ids.empty?

    @depends_on = @depends_on_ids.compact_map do |id|
      index[id]? || raise ArgumentError.new("Unknown dependency '#{id}'")
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
        yaml.scalar value.to_s
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
      rescue
      end

      # 2. VirtualTime rule
      VirtualTime.from_yaml(value)
    end
  end

  class TimeSpanSecondsConverter
    def self.to_yaml(value : Time::Span, yaml : YAML::Nodes::Builder)
      yaml.scalar value.total_seconds.to_i64
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Time::Span
      unless node.is_a?(YAML::Nodes::Scalar)
        node.raise "Expected integer seconds for Time::Span"
      end
      Time::Span.new(seconds: node.value.to_i64)
    end
  end

  class NullableTimeSpanSecondsConverter
    def self.to_yaml(value : Time::Span?, yaml : YAML::Nodes::Builder)
      if value
        yaml.scalar value.total_seconds.to_i64
      else
        yaml.scalar nil
      end
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Time::Span?
      return nil if YAML::Schema::Core.parse_null?(node)
      unless node.is_a?(YAML::Nodes::Scalar)
        node.raise "Expected integer seconds for Time::Span?"
      end
      Time::Span.new(seconds: node.value.to_i64)
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
        yaml.scalar value.total_seconds.to_i64
      end
    end

    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Nil | Bool | Time::Span
      return nil if YAML::Schema::Core.parse_null?(node)

      unless node.is_a?(YAML::Nodes::Scalar)
        node.raise "Expected null, bool, or integer seconds for shift"
      end

      v = node.value

      # Bool
      return true if v == "true"
      return false if v == "false"

      # Seconds (integer)
      unless v =~ /^-?\d+$/
        node.raise "Expected 'true', 'false', or integer seconds for shift, got #{v.inspect}"
      end

      Time::Span.new(seconds: v.to_i64)
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
      lines.join("\r\n") + "\r\n"
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
        "DTEND:#{format_time(inst.finish)}",
        "SUMMARY:#{escape(inst.vdate.id)}",
        "DESCRIPTION:#{escape(description)}",
        categories(inst),
        "END:VEVENT",
      ].compact
    end

    private def self.categories(inst : Scheduled) : String?
      return nil if inst.vdate.flags.empty?
      "CATEGORIES:#{inst.vdate.flags.map { |f| escape(f) }.join(",")}"
    end

    private def self.format_time(t : Time) : String
      ICS_TIME_FORMAT.format(t.to_utc)
    end

    # RFC 5545 escaping
    private def self.escape(s : String) : String
      s
        .gsub("\\", "\\\\")
        .gsub("\n", "\\n")
        .gsub(",", "\\,")
        .gsub(";", "\\;")
    end
  end
end
