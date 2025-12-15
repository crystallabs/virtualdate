require "virtualtime"

# VirtualDate builds on VirtualTime to represent due/omit rules plus higher-level scheduling semantics.
class VirtualDate
  VERSION_MAJOR    = 1
  VERSION_MINOR    = 1
  VERSION_REVISION = 0
  VERSION          = [VERSION_MAJOR, VERSION_MINOR, VERSION_REVISION].join '.'

  include YAML::Serializable

  # Absolute begin date/time. Item is never "on" before this date.
  @[YAML::Field(converter: VirtualDate::VirtualTimeOrTimeConverter)]
  property begin : VirtualTime::TimeOrVirtualTime?

  # Absolute end date/time. Item is never "on" after this date.
  @[YAML::Field(converter: VirtualDate::VirtualTimeOrTimeConverter)]
  property end : VirtualTime::TimeOrVirtualTime?

  # List of VirtualTimes on which the item is "on"/due/active.
  property due = [] of VirtualTime

  # List of VirtualTimes on which the item should be "omitted".
  property omit = [] of VirtualTime

  # Decision about an item to make if it falls on an omitted date/time.
  #
  # Allowed values are:
  # - nil: treat the item as non-applicable/not-scheduled on the specified date/time
  # - false: treat the item as not due due to falling on an omitted date/time, after a reschedule was not attempted or was not able to find another spot
  # - true: treat the item as due regardless of falling on an omitted date/time
  # - Time::Span: shift the scheduled date/time by specified time span. Can be negative or positive.
  @[YAML::Field(converter: VirtualDate::ShiftConverter)]
  property shift : Nil | Bool | Time::Span = false

  # Max amount of total time by which item can be shifted before it's considered unschedulable (false)
  @[YAML::Field(converter: VirtualDate::NullableTimeSpanSecondsConverter)]
  property max_shift : Time::Span?

  # Max amount of shift attempts, before it's considered unschedulable (false)
  property max_shifts = 1500

  # Fixed override of `#on?` for this item. If set, takes precedence over begin/end/due/omit.
  # Same union as `#shift`.
  @[YAML::Field(converter: VirtualDate::ShiftConverter)]
  property on : Nil | Bool | Time::Span

  @[YAML::Field(converter: VirtualDate::TimeSpanSecondsConverter)]
  property duration : Time::Span = 0.seconds

  # Flags/categories (e.g. meeting, task, or passive/active/unimportant, or color-coded, or anything). Used by Scheduler for parallelism.
  property flags = Set(String).new

  # Max number of overlapping tasks that share at least one common flag with this task.
  # Example: flags={meeting}, parallel=2 means up to 2 meetings can overlap.
  property parallel : Int32 = 1

  # Higher wins conflict resolution when Scheduler must choose.
  property priority : Int32 = 0

  # If true, Scheduler treats this task as non-movable due to conflicts (still movable by omit-rescheduling rules if you keep shift != false).
  property fixed : Bool = false

  # Optional dependencies: scheduler will try to place this task after all dependencies.
  # (Used only by Scheduler; VirtualDate itself does not enforce this.)
  @[YAML::Field(ignore: true)]
  property depends_on = [] of VirtualDate

  # Serialized form
  @[YAML::Field(key: "depends_on")]
  property depends_on_ids = [] of String

  # Staggered parallel scheduling
  @[YAML::Field(converter: VirtualDate::NullableTimeSpanSecondsConverter)]
  property stagger : Time::Span? = nil

  # Identifier (important for dependencies)
  property id : String

  # Hard deadline — task MUST finish before this time or fails scheduling
  @[YAML::Field(converter: VirtualTimeOrTimeConverter)]
  property deadline : VirtualTime::TimeOrVirtualTime? = nil

  # Soft deadline — scheduler prefers finishing before this
  @[YAML::Field(converter: VirtualTimeOrTimeConverter)]
  property soft_deadline : VirtualTime::TimeOrVirtualTime? = nil

  def resolve_dependencies!(index : Hash(String, VirtualDate))
    @depends_on = @depends_on_ids.compact_map do |id|
      index[id]?
    end
  end

  def initialize(@id : String? = "")
  end

  class VirtualTimeOrTimeConverter
    def self.to_yaml(
      value : VirtualTime::TimeOrVirtualTime?,
      yaml : YAML::Nodes::Builder,
    )
      case value
      when Time
        yaml.scalar value.to_s
      when VirtualTime
        yaml.scalar value.to_yaml
      when Nil
        yaml.scalar nil
      end
    end

    def self.from_yaml(
      ctx : YAML::ParseContext,
      node : YAML::Nodes::Node,
    ) : VirtualTime::TimeOrVirtualTime?
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

  # Checks whether the item is "on" on the specified date/time.
  #
  # Return values:
  # nil        - item is not "on" / not due / not scheduled
  # true       - item is "on" (due and not omitted)
  # false      - item is due but omitted and no reschedule requested or possible
  # Time::Span - the span to add to asked date to reach earliest/closest time when item is "on"
  #
  # IMPORTANT (legacy behavior): If the item is rescheduled away from the asked time,
  # `on?` returns a Time::Span, but querying `on?` at the rescheduled time will not
  # necessarily return true. Use `#resolve` or `#effective_on?` for that.
  def on?(time : VirtualTime::TimeOrVirtualTime = Time.local, *, max_shift = @max_shift, max_shifts = @max_shifts, hint = time.is_a?(Time) ? time : Time.local) : Nil | Bool | Time::Span
    # If `@on` is non-nil, it dictates the item's status.
    @on.try { |status| return status }

    # Absolute begin/end filtering. If they are VirtualTime by chance, then
    # they are not used for `a <= T <= z` comparison but simply they musth
    # match `T` in the usual sense.
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
      return reschedule_delta(time, s, max_shift: max_shift, max_shifts: max_shifts) { |t| omit_on?(t) == true }
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

  # Resolves the asked time to an effective scheduled Time.
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
    r = on?(time, max_shift: max_shift, max_shifts: max_shifts, hint: hint)
    case r
    when Time::Span
      t = time.is_a?(Time) ? time : time.to_time(hint)
      t + r
    else
      r
    end
  end

  # Returns true if the task is effectively scheduled at `time`, i.e. either:
  # - it is on at `time` directly, OR
  # - it is due at some base time that resolves (via shifting) to exactly `time`
  #
  # For omit-driven shifting (Time::Span), we can search candidate base times by reversing the shift.
  # This is deterministic and bounded by max_shifts/max_shift.
  def effective_on?(time : Time, *, max_shift = @max_shift, max_shifts = @max_shifts) : Bool
    # Direct check
    direct = on?(time, max_shift: max_shift, max_shifts: max_shifts, hint: time)
    return true if direct == true

    s = @shift
    return false unless s.is_a?(Time::Span)
    return false if s.total_nanoseconds == 0

    # Inverse search: look for a base time t0 such that t0 + delta == time.
    # We search in the reverse direction by stepping by `-s`.
    # This works because legacy `on?` always returns delta as multiples of shift steps
    # under omit-driven rescheduling.
    base = time
    steps = 0

    loop do
      steps += 1
      break if steps > max_shifts

      base -= s

      # Enforce max_shift window if provided
      if max_shift && (time - base).total_nanoseconds.abs > max_shift.total_nanoseconds
        break
      end

      r = on?(base, max_shift: max_shift, max_shifts: max_shifts, hint: base)
      case r
      when Time::Span
        return true if base + r == time
      when true
        # base itself is on; does not imply time is on
      else
        # nil/false ignore
      end
    end

    false
  end

  # Returns Time::Span when a valid non-omitted time is found, or false if unschedulable.
  private def reschedule_delta(time : Time, shift : Time::Span, *, max_shift : Time::Span?, max_shifts : Int32, &omit : Time -> Bool) : Bool | Time::Span
    return false if shift.total_nanoseconds == 0

    original = time
    current = time
    shifts = 0

    loop do
      shifts += 1
      current += shift

      return false if shifts > max_shifts

      if max_shift &&
         (current - original).total_nanoseconds.abs > max_shift.total_nanoseconds
        return false
      end

      if omit.call(current)
        next
      end

      return current - original
    end
  end

  struct Occurrence
    getter task : VirtualDate
    getter start : Time
    getter explanation : VirtualDate::ScheduleExplanation

    def initialize(@task : VirtualDate, @start : Time)
      @explanation = VirtualDate::ScheduleExplanation.new
    end
  end

  # A concrete scheduled occurrence of a VirtualDate task.
  class TaskInstance
    getter task : VirtualDate
    getter start : Time
    getter finish : Time
    property explanation : VirtualDate::ScheduleExplanation

    def initialize(@task : VirtualDate, @start : Time, explanation = nil)
      @finish = @start + task.duration
      @explanation = VirtualDate::ScheduleExplanation.new
      @explanation.add explanation if explanation
    end

    def flags : Array(String)
      task.flags.to_a
    end

    def parallel : Hash(String, Int32)
      case p = task.parallel
      when Int32
        flags.each_with_object({} of String => Int32) { |f, h| h[f] = p }
      when Hash(String, Int32)
        p
      else
        {} of String => Int32
      end
    end

    def fixed : Bool
      task.fixed
    end
  end

  # A simple, deterministic scheduler for VirtualDate tasks.
  #
  # This scheduler:
  # - generates candidate occurrences from `task.due` VirtualTimes
  # - resolves omit-driven shifts via `VirtualDate#resolve`
  # - enforces conflicts using `duration`, `flags`, `parallel`
  # - reschedules forward on conflicts when possible
  #
  # Notes:
  # - This is an “advanced baseline” scheduler; it is intentionally conservative and predictable.
  # - If you need global optimality (e.g. minimizing total displacement), you would add a second pass
  #   or switch to a constraint solver.
  class Scheduler
    property tasks : Array(VirtualDate)

    def initialize(@tasks = [] of VirtualDate)
      index = @tasks.to_h { |t| {t.id, t} }

      @tasks.each do |task|
        task.resolve_dependencies!(index)
      end
    end

    # Produces scheduled instances in [from, to).
    #
    # Parameters:
    # - granularity: how frequently to generate occurrences from due rules (defaults to 1 minute)
    # - max_occurrences_per_task: safety limit to avoid infinite generation for very broad rules
    #
    # Returns: Array(TaskInstance), sorted by start time.
    def build(from : Time, to : Time) : Array(TaskInstance)
      instances = [] of TaskInstance

      ordered = topo_sort_tasks(@tasks).sort_by do |t|
        {
          t.fixed ? 0 : 1, # fixed first
          -t.priority,     # then priority
        }
      end

      ordered.each do |task|
        # HARD DEPENDENCY GATE
        if task.depends_on.any?
          unless dependency_floor_time(task, instances)
            # Dependencies not yet satisfied → do NOT attempt scheduling
            next
          end
        end

        occurrences = generate_occurrences(task, from, to)

        occurrences.each do |occ|
          if task.depends_on.any?
            dep_floor = dependency_floor_time(task, instances).not_nil!
            occ = Occurrence.new(task, dep_floor) if dep_floor > occ.start
          end

          placed = place_instance(occ, instances, horizon: to)

          # CRITICAL: dependency tasks must never be dropped
          if placed
            instances << placed
          elsif task.depends_on.empty?
            # Non-dependent tasks may fail silently
            next
          else
            raise ArgumentError.new(
              "Failed to schedule dependency task #{task.id}"
            )
          end
        end
      end
      # ordered.each do |task|
      #  occurrences = generate_occurrences(task, from, to)

      #  occurrences.each do |occ|
      #    # Dependency floor: cannot start before latest dependency finishes
      #    if task.depends_on.size > 0
      #      dep_floor = dependency_floor_time(task, instances) # , ordered)
      #      # If deps not scheduled, skip (or raise). Specs expect they will be schedulable.
      #      next unless dep_floor

      #      if dep_floor > occ.start
      #        occ.explanation.add(
      #          "Delayed until dependencies finished at #{dep_floor}"
      #        )
      #        occ = Occurrence.new(task, dep_floor).tap do |o|
      #          o.explanation.lines.concat(occ.explanation.lines)
      #        end
      #      end
      #    end

      #    placed = place_instance(
      #      occ,
      #      instances,
      #      horizon: to
      #    )

      #    instances << placed if placed
      #  end
      # end

      instances.sort_by!(&.start)
      instances
    end

    private def topo_sort_tasks(tasks : Array(VirtualDate)) : Array(VirtualDate)
      # Build adjacency + indegree
      indegree = Hash(VirtualDate, Int32).new(0)
      outgoing = Hash(VirtualDate, Array(VirtualDate)).new { |h, k| h[k] = [] of VirtualDate }

      tasks.each do |t|
        indegree[t] = 0
      end

      tasks.each do |t|
        t.depends_on.each do |dep|
          next unless tasks.includes?(dep)
          outgoing[dep] << t
          indegree[t] = indegree[t] + 1
        end
      end

      # Ready set (indegree 0)
      ready = tasks.select { |t| indegree[t] == 0 }

      # Deterministic ordering:
      # - fixed first (true first)
      # - higher priority first
      # - stable tie-breaker by id (string)
      sorter = ->(a : VirtualDate, b : VirtualDate) do
        # 1) Fixed tasks first
        fa = a.fixed ? 0 : 1
        fb = b.fixed ? 0 : 1
        cmp = fa <=> fb
        return cmp if cmp != 0

        # 2) Higher priority first
        cmp = b.priority <=> a.priority
        return cmp if cmp != 0

        # 3) Stable ordering (ID)
        (a.id || "") <=> (b.id || "")
      end

      #  sorter = ->(a : VirtualDate, b : VirtualDate) do
      #    fa = a.fixed ? 0 : 1
      #    fb = b.fixed ? 0 : 1
      #    cmp = fa <=> fb
      #    next cmp if cmp != 0
      #
      #    cmp = b.priority <=> a.priority
      #    next cmp if cmp != 0
      #
      #    (a.id || "") <=> (b.id || "")
      #  end

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

      if result.size != tasks.size
        raise ArgumentError.new("Dependency cycle detected")
      end

      result
    end

    #    private def topo_sort_tasks(tasks : Array(VirtualDate)) : Array(VirtualDate)
    #      result = [] of VirtualDate
    #      temp = Set(VirtualDate).new
    #      perm = Set(VirtualDate).new
    #
    #      visit = uninitialized Proc(VirtualDate, Nil)
    #
    #      visit = ->(t : VirtualDate) do
    #        return if perm.includes?(t)
    #        raise ArgumentError.new("Dependency cycle detected at #{t.id}") if temp.includes?(t)
    #
    #        temp.add(t)
    #        t.depends_on.each do |d|
    #          visit.call(d)
    #        end
    #        temp.delete(t)
    #
    #        perm.add(t)
    #        result << t
    #        nil
    #      end
    #
    #      tasks.each do |t|
    #        visit.call(t)
    #      end
    #
    #      result
    #    end

    private def dependency_floor_time(
      task : VirtualDate,
      instances : Array(TaskInstance),
    ) : Time?
      finishes = [] of Time

      task.depends_on.each do |dep_task|
        inst = instances.find { |i| i.task == dep_task }
        return nil unless inst

        finishes << inst.finish
      end

      finishes.max?
    end

    private def instance_finish(inst : TaskInstance) : Time
      inst.start + (inst.task.duration || 0.seconds)
    end

    private def generate_occurrences(
      task : VirtualDate,
      from : Time,
      to : Time,
    ) : Array(Occurrence)
      occs = [] of Occurrence

      start = earliest_start_time(task, from, to)
      return occs unless start

      # Non-staggered (backward-compatible) behavior
      unless task.stagger && task.parallel > 1
        # Apply omit check to the single produced occurrence
        return occs if task.omit_on?(start)
        occ = Occurrence.new(task, start)
        occ.explanation.add("Matched due rule at #{start}")
        occs << occ
        return occs
      end

      stagger = task.stagger.not_nil!
      raise ArgumentError.new("stagger must be positive") if stagger <= 0.seconds

      task.parallel.times do |i|
        t = start + stagger * i
        break if t > to

        next if task.omit_on?(t)

        occ = Occurrence.new(task, t)
        occ.explanation.add("Matched due rule at #{t} (staggered)")
        occs << occ
      end

      occs
    end

    private def earliest_start_time(
      task : VirtualDate,
      from : Time,
      to : Time,
    ) : Time?
      t = from

      while t <= to
        r = task.on?(t)

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

    private def earliest_start_for(task : VirtualDate, from : Time) : Time
      case r = task.on?(from)
      when Time::Span
        from + r
      else
        from
      end
    end

    # True if `task` is considered “on” at `time` in the produced schedule.
    def on_in_schedule?(instances : Array(TaskInstance), task : VirtualDate, time : Time) : Bool
      instances.any? do |i|
        next false unless i.task == task

        if i.start == i.finish
          time == i.start
        else
          i.start <= time && time < i.finish
        end
      end
    end

    private def resolve_to_time(task : VirtualDate, candidate : Time) : Time?
      r = task.resolve(candidate, hint: candidate)
      case r
      when Time
        r
      when true
        candidate
      else
        nil
      end
    end

    private def explain(inst : TaskInstance, msg : String)
      inst.explanation.add "- #{msg}\n"
    end

    def overlaps?(a : TaskInstance, b : TaskInstance)
      a_start = a.start
      a_end = a.start + (a.task.duration || 0.seconds)

      b_start = b.start
      b_end = b.start + (b.task.duration || 0.seconds)

      a_start < b_end && b_start < a_end
    end

    # Places an instance, resolving conflicts by shifting forward (using task.shift when Time::Span),
    # respecting task.fixed and max_shift/max_shifts.
    def place_instance(
      occ : Occurrence,
      instances : Array(TaskInstance),
      *,
      horizon : Time,
    ) : TaskInstance?
      task = occ.task
      start = occ.start
      duration = task.duration || 0.seconds

      loop do
        finish = start + duration

        # Horizon guard
        return nil if finish > horizon

        candidate = TaskInstance.new(task, start)

        if deadline = task.deadline
          deadline_time =
            case deadline
            when Time
              deadline
            else
              deadline.to_time(start)
            end

          if finish > deadline_time
            candidate.explanation.add "- Rejected: finish #{finish} exceeds hard deadline #{deadline_time}\n"
            return nil
          end
        end

        # Check parallelism / conflicts
        if acceptable_parallelism?(candidate, instances)
          candidate.explanation.add "- Scheduled at #{start} without conflicts\n"
          return candidate
        end

        # Conflict exists
        conflict = instances.find do |i|
          i_start = i.start
          i_end = i.finish
          (start < i_end) && (i_start < finish)
        end

        # Fixed task rules
        if conflict
          if conflict.task.fixed
            # If task has dependents, it must be placed even if it conflicts
            if has_dependents?(task)
              candidate.explanation.add "Placed despite conflicts because other tasks depend on it"
              return candidate
            end

            # Otherwise respect fixed semantics
            return nil if task.fixed

            candidate.explanation.add "- Yielded to fixed task #{conflict.task.id}, moved after #{conflict.finish}\n"
            start = conflict.finish
            next
          end

          if task.fixed
            instances.delete(conflict)
            candidate.explanation.add "- Displaced movable task #{conflict.task.id} (this task is fixed)\n"
            next
          end

          # Priority comparison
          if task.priority > conflict.task.priority
            instances.delete(conflict)
            candidate.explanation.add "- Displaced lower-priority task #{conflict.task.id}\n"
            next
          elsif task.priority < conflict.task.priority
            candidate.explanation.add "- Yielded to higher-priority task #{conflict.task.id}, moved after #{conflict.finish}\n"
            start = conflict.finish
            next
          end
        end

        # Equal priority or no decisive conflict → shift forward
        shift_span =
          case s = task.shift
          when Time::Span
            s
          else
            1.minute
          end

        candidate.explanation.add "- Conflict unresolved, shifted forward by #{shift_span}\n"

        start += shift_span
      end
    end

    #    def place_instance(
    #      occ : Occurrence,
    #      instances : Array(TaskInstance),
    #      *,
    #      horizon : Time,
    #    ) : TaskInstance?
    #      task = occ.task
    #      start = occ.start
    #      duration = task.duration
    #
    #      loop do
    #        finish = start + duration
    #        return nil if finish > horizon
    #
    #        candidate = TaskInstance.new(task, start)
    #
    #        conflicts =
    #          instances.select do |i|
    #            overlaps?(candidate, i)
    #          end
    #
    #        blocking_fixed = conflicts.any?(&.fixed)
    #
    #        if conflicts.empty?
    #          candidate.add_explanation(
    #            "Scheduled at due time (no conflicts)"
    #          )
    #          return candidate
    #        end
    #
    #        if blocking_fixed
    #          if task.fixed
    #            candidate.add_explanation(
    #              "Blocked by existing fixed task; cannot move"
    #            )
    #            return nil
    #          end
    #
    #          candidate.add_explanation(
    #            "Shifted due to conflict with fixed task"
    #          )
    #        elsif acceptable_parallelism?(candidate, instances)
    #          candidate.add_explanation(
    #            "Allowed by parallelism rules"
    #          )
    #          return candidate
    #        else
    #          candidate.add_explanation(
    #            "Shifted due to parallelism limit"
    #          )
    #        end
    #
    #				conflict = conflicting_instance(candidate, instances)
    #				if conflict
    #					if conflict.task.fixed
    #						return nil if task.fixed
    #						# movable loses to fixed
    #						start = conflict.finish
    #						explain(candidate, "Moved after fixed task #{conflict.task.id}")
    #						next
    #					end
    #
    #					if task.fixed
    #						displace(conflict, instances)
    #						explain(candidate, "Displaced movable task #{conflict.task.id}")
    #						next
    #					end
    #
    #					if task.priority > conflict.task.priority
    #						displace(conflict, instances)
    #						explain(candidate, "Displaced lower-priority task #{conflict.task.id}")
    #						next
    #					end
    #
    #					if task.priority < conflict.task.priority
    #						start = conflict.finish
    #						explain(candidate, "Yielded to higher-priority task #{conflict.task.id}")
    #						next
    #					end
    #
    #					# Equal priority → shift forward
    #					start += effective_shift(task)
    #					explain(candidate, "Equal priority conflict, shifted forward")
    #					next
    #				end
    #
    #      end
    #    end

    private def has_dependents?(task : VirtualDate) : Bool
      @tasks.any? { |t| t.depends_on.includes?(task) }
    end

    private def effective_shift(task : VirtualDate) : Time::Span
      case s = task.shift
      when Time::Span
        s
      else
        1.minute
      end
    end

    private def deadline_penalty(task : VirtualDate, finish : Time) : Int32
      return 0 unless sd = task.soft_deadline

      sd_time = materialize_deadline(sd, finish)
      return 0 if finish <= sd_time

      ((finish - sd_time).total_minutes).to_i
    end

    private def conflicting_instance(
      candidate : TaskInstance,
      instances : Array(TaskInstance),
    ) : TaskInstance?
      instances.find do |i|
        overlap?(candidate, i) &&
          !acceptable_parallelism?(candidate, [i])
      end
    end

    private def displace(
      inst : TaskInstance,
      instances : Array(TaskInstance),
    )
      instances.delete(inst)
    end

    private def materialize_deadline(
      dl : VirtualTime::TimeOrVirtualTime,
      hint : Time,
    ) : Time
      case dl
      when Time
        dl
      else
        dl.to_time(hint)
      end
    end

    # Enforces per-task parallelism across overlapping instances sharing flags.
    private def acceptable_parallelism?(
      candidate : TaskInstance,
      instances : Array(TaskInstance),
    ) : Bool
      c_start = candidate.start
      c_end = candidate.start + (candidate.task.duration || 0.seconds)

      flags = candidate.flags
      if flags.empty?
        flags = [:__default]
      end

      flags.each do |flag|
        limit =
          case p = candidate.task.parallel
          when Int32
            p
          when Hash(String, Int32)
            p[flag]? || 1
          else
            1
          end

        concurrent =
          instances.count do |i|
            i_flags = i.flags
            i_flags = [:__default] if i_flags.empty?

            next false unless i_flags.includes?(flag)

            i_start = i.start
            i_end = i.start + (i.task.duration || 0.seconds)

            # half-open overlap
            (c_start < i_end) && (i_start < c_end)
          end

        return false if concurrent + 1 > limit
      end

      true
    end

    # Generates candidate occurrence times for `task` using its due VirtualTimes.
    private def each_candidate_occurrence(
      task : VirtualDate,
      from : Time,
      to : Time,
      granularity : Time::Span,
      max_occurrences : Int32,
      &block : Time -> Nil
    ) : Nil
      # No due rules => task matches any time; we treat that as “candidate at from” only to avoid explosion.
      if task.due.size == 0
        yield from
        return
      end

      produced = 0

      task.due.each do |vt|
        # Create a stream of occurrences using VirtualTime's own successor stepping.
        # We anchor at `from - 1ns` to ensure first succ is >= from.
        t = from - 1.nanosecond

        loop do
          break if produced >= max_occurrences
          begin
            t = vt.succ(t) # next matching time after t
          rescue ArgumentError
            break
          end

          break if t >= to
          yield t
          produced += 1

          # Prevent extremely dense rules from locking the scheduler:
          # advance at least by granularity - 1ns to make progress while letting vt.succ re-align.
          t = t + granularity - 1.nanosecond
        end
      end
    end
  end

  struct VirtualDateFile
    include YAML::Serializable

    property schema_version : Int32
    property tasks : Array(VirtualDate)

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

        file.tasks
      when YAML::Nodes::Sequence
        # Legacy format: bare task list
        Array(VirtualDate).from_yaml(yaml)
      else
        raise ArgumentError.new(
          "Invalid YAML root (expected mapping with schema_version or task list)"
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
      tasks = raw.map do |r|
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

      resolve_dependencies(tasks, raw)
      tasks
    end

    def self.v2_to_current(raw : Array(VirtualDateRaw)) : Array(VirtualDate)
      # Currently identical to v1, but kept explicit for future changes
      v1_to_current(raw)
    end

    private def self.resolve_dependencies(
      tasks : Array(VirtualDate),
      raw : Array(VirtualDateRaw),
    )
      index = tasks.to_h { |t| {t.id, t} }

      raw.each_with_index do |r, i|
        next unless r.depends_on

        r.depends_on.not_nil!.each do |dep_id|
          dep = index[dep_id]?
          raise ArgumentError.new("Unknown dependency '#{dep_id}'") unless dep
          tasks[i].depends_on << dep
        end
      end
    end
  end

  struct ValidationError
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

      errors = [] of ValidationError

      unless root.is_a?(YAML::Nodes::Mapping)
        errors << ValidationError.new("Root must be a mapping", root)
        raise_errors(errors)
      end

      validate_root_mapping(root, errors)

      raise_errors(errors) unless errors.empty?
    end

    private def raise_errors(errors)
      msg = errors.map(&.to_s).join("\n")
      raise ArgumentError.new("Invalid YAML:\n#{msg}")
    end

    private def validate_root_mapping(
      node : YAML::Nodes::Mapping,
      errors : Array(ValidationError),
    )
      map = mapping_to_hash(node, errors)

      unless map["schema_version"]?
        errors << ValidationError.new("Missing 'schema_version'", node)
      end

      unless map["tasks"]?.is_a?(YAML::Nodes::Sequence)
        errors << ValidationError.new("'tasks' must be a sequence", node)
        return
      end

      validate_tasks(map["tasks"].as(YAML::Nodes::Sequence), errors)
    end

    private def validate_tasks(
      seq : YAML::Nodes::Sequence,
      errors : Array(ValidationError),
    )
      seq.nodes.each do |task_node|
        unless task_node.is_a?(YAML::Nodes::Mapping)
          errors << ValidationError.new("Each task must be a mapping", task_node)
          next
        end

        task = mapping_to_hash(task_node, errors)

        unless task["id"]?.is_a?(YAML::Nodes::Scalar)
          errors << ValidationError.new("Task missing 'id'", task_node)
        end

        if task["parallel"]?.try &.as(YAML::Nodes::Scalar)
          p = task["parallel"].as(YAML::Nodes::Scalar).value.to_i?
          if p && p < 1
            errors << ValidationError.new("'parallel' must be >= 1", task["parallel"])
          end
        end

        if task["duration"]?.try &.as(YAML::Nodes::Scalar)
          d = task["duration"].as(YAML::Nodes::Scalar).value.to_i?
          if d && d < 0
            errors << ValidationError.new("'duration' must be >= 0", task["duration"])
          end
        end
      end
    end

    private def mapping_to_hash(
      node : YAML::Nodes::Mapping,
      errors : Array(ValidationError),
    )
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
            errors << ValidationError.new(
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

  struct ScheduleExplanation
    property lines : Array(String)

    def initialize
      @lines = [] of String
    end

    def add(msg : String)
      @lines << msg
    end

    def to_s
      @lines.join("\n")
    end
  end

  module ICS
    ICS_TIME_FORMAT = Time::Format.new("%Y%m%dT%H%M%SZ")

    def self.export(
      instances : Array(TaskInstance),
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

      instances.each do |inst|
        lines.concat event(inst, now)
      end

      lines << "END:VCALENDAR"
      lines.join("\r\n") + "\r\n"
    end

    private def self.event(inst : TaskInstance, now : Time) : Array(String)
      uid = "#{inst.task.id}-#{inst.start.to_unix}@virtualdate"

      description = String.build do |io|
        io << inst.explanation
        unless inst.task.flags.empty?
          io << "\nFlags: " << inst.task.flags.join(", ")
        end
      end

      [
        "BEGIN:VEVENT",
        "UID:#{escape(uid)}",
        "DTSTAMP:#{format_time(now)}",
        "DTSTART:#{format_time(inst.start)}",
        "DTEND:#{format_time(inst.finish)}",
        "SUMMARY:#{escape(inst.task.id)}",
        "DESCRIPTION:#{escape(description)}",
        categories(inst),
        "END:VEVENT",
      ].compact
    end

    private def self.categories(inst : TaskInstance) : String?
      return nil if inst.task.flags.empty?
      "CATEGORIES:#{inst.task.flags.map { |f| escape(f) }.join(",")}"
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
