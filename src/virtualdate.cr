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

  # Soft deadline — scheduler prefers finishing before this
  @[YAML::Field(converter: VirtualDate::VirtualTimeOrTimeConverter)]
  property soft_deadline : VirtualTime::TimeOrVirtualTime? = nil

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

    # 2. Only Time::Span shifts can produce inverse reachability
    shift = @shift
    return false unless shift.is_a?(Time::Span)
    return false if shift.total_nanoseconds == 0

    # TODO write a log about this
    return false if max_shifts && max_shifts <= 0
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
      return false if max_shifts && max_shifts <= 0
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

  # A simple, deterministic scheduler for VirtualDate tasks.
  #
  # This scheduler:
  # - Generates candidate candidates from `task.due` VirtualTimes
  # - Resolves omit-driven shifts via `VirtualDate#resolve`
  # - Enforces conflict resolution using `duration`, `flags`, `parallel`
  # - Reschedules forward on conflicts when possible
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

    # Produces scheduled tasks in [from, to).
    #
    # Parameters:
    # - granularity: how frequently to generate candidates from due rules (defaults to 1 minute)
    # - max_candidates: safety limit to avoid infinite generation for very broad rules
    #
    # Returns: Array(ScheduledTask), sorted by start time.
    def build(from : Time, to : Time) : Array(ScheduledTask)
      scheduled_tasks = [] of ScheduledTask

      ordered = order_tasks_by_dependencies(@tasks)
      scheduled_index = {} of VirtualDate => ScheduledTask

      ordered.each do |task|
        dependency_floor = task.depends_on.any? ? earliest_start_time_after_dependencies(task, scheduled_index) : nil
        next if task.depends_on.any? && dependency_floor.nil?

        candidates = generate_candidates(task, from, to)

        candidates.each do |candidate|
          if dependency_floor
            candidate = Candidate.new(task, dependency_floor) if dependency_floor > candidate.start
          end

          scheduled_task = schedule_candidate(candidate, scheduled_tasks, horizon: to)

          # Dependency tasks must never be dropped
          if scheduled_task
            scheduled_tasks << scheduled_task
            scheduled_index[scheduled_task.task] = scheduled_task
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

      scheduled_tasks.sort_by!(&.start)
      scheduled_tasks
    end

    # Sort by dependencies. Tasks with no dependencies have indegree == 0.
    # E.g. ready = tasks.select { |t| indegree[t] == 0 }
    private def order_tasks_by_dependencies(tasks : Array(VirtualDate)) : Array(VirtualDate)
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
        # 1. Fixed tasks first
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

      if result.size != tasks.size
        raise ArgumentError.new("Dependency cycle detected")
      end

      result
    end

    # Finds earliest time a task can start, but not before its dependencies
    # are completed.
    private def earliest_start_time_after_dependencies(task : VirtualDate, scheduled_index : Hash(VirtualDate, VirtualDate::ScheduledTask)) : Time?
      finishes = [] of Time

      task.depends_on.each do |dep_task|
        inst = scheduled_index[dep_task]?
        return nil unless inst
        finishes << inst.finish
      end

      finishes.max?
    end

    # Returns start + duration
    private def instance_finish(inst : ScheduledTask) : Time
      inst.start + (inst.task.duration || 0.seconds)
    end

    # Finds earliest valid start time according to VirtualDate#on?
    #
    # Does:
    # - Applies omit rules
    # - Optionally expands into multiple candidates (staggered / parallel tasks)
    #
    # Does not do things that happen later in `schedule_candidate`, such as:
    # - Resolve conflicts
    # - Respect dependencies
    # - Parallelism limits
    # - Check deadlines
    # - Shift due to conflicts
    #
    # - Returns a small, bounded list of concrete Time values wrapped as objects
    private def generate_candidates(task : VirtualDate, from : Time, to : Time) : Array(Candidate)
      candidates = [] of Candidate

      start = earliest_start_time(task, from, to)
      return candidates unless start

      # Non-staggered (backward-compatible) behavior
      unless task.stagger && task.parallel > 1
        # Apply omit check to the single produced candidate
        candidate = Candidate.new(task, start)
        candidate.explanation.add("Matched due rule at #{start}")
        candidates << candidate
        return candidates
      end

      stagger = task.stagger.not_nil!
      raise ArgumentError.new("stagger must be positive") if stagger <= 0.seconds

      task.parallel.times do |i|
        t = start + stagger * i
        break if t > to

        next if task.omit_on?(t)

        candidate = Candidate.new(task, t)
        candidate.explanation.add("Matched due rule at #{t} (staggered)")
        candidates << candidate
      end

      candidates
    end

    # Finds earliest start time based on the task alone, not taking into account dependencies.
    # In essence, task start = max( earliest_start_time, earliest_start_time_after_dependencies)
    private def earliest_start_time(task : VirtualDate, from : Time, to : Time) : Time?
      t = from
      iterations = 0
      max_iterations = 10_000

      while t <= to
        iterations += 1
        raise ArgumentError.new("earliest_start_time exceeded iteration limit") if iterations > max_iterations

        r = task.strict_on?(t)

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

    # True if `task` is considered “on” at `time` in the produced schedule.
    def on_in_schedule?(scheduled_tasks : Array(ScheduledTask), task : VirtualDate, time : Time) : Bool
      scheduled_tasks.any? do |i|
        next false unless i.task == task

        if i.start == i.finish
          time == i.start
        else
          i.start <= time && time < i.finish
        end
      end
    end

    # Schedules an instance, resolving conflicts by shifting forward (using task.shift when Time::Span),
    # respecting task.fixed and max_shift/max_shifts.
    def schedule_candidate(candidate : Candidate, scheduled_tasks : Array(ScheduledTask), *, horizon : Time) : ScheduledTask?
      task = candidate.task
      start = candidate.start
      duration = task.duration || 0.seconds

      if duration == 0.seconds
        return nil if start > horizon
        scheduled = ScheduledTask.new(task, start)
        scheduled.explanation.add "- Scheduled instant task at #{start}\n"
        return scheduled
      end

      loop do
        finish = start + duration

        # Horizon guard
        return nil if finish > horizon

        candidate = ScheduledTask.new(task, start)

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
        if acceptable_parallelism?(candidate, scheduled_tasks)
          candidate.explanation.add "- Scheduled at #{start} without conflicts\n"
          return candidate
        end

        # Conflict exists
        conflict = scheduled_tasks.find do |i|
          overlaps?(start, finish, i.start, i.finish)
        end

        # Fixed task rules
        if conflict
          if conflict.task.fixed
            # If task has dependents, it must be scheduled even if it conflicts
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
            scheduled_tasks.delete(conflict)
            candidate.explanation.add "- Displaced movable task #{conflict.task.id} (this task is fixed)\n"
            next
          end

          # Priority comparison
          if task.priority > conflict.task.priority
            scheduled_tasks.delete(conflict)
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

    # Returns whether any tasks depend on this one
    private def has_dependents?(task : VirtualDate) : Bool
      @tasks.any? { |t| t.depends_on.includes?(task) }
    end

    @[AlwaysInline]
    private def overlaps?(a_start, a_end, b_start, b_end)
      a_start < b_end && b_start < a_end
    end

    # Enforces per-task parallelism across overlapping scheduled_tasks sharing flags.
    private def acceptable_parallelism?(candidate : ScheduledTask, scheduled_tasks : Array(ScheduledTask)) : Bool
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
          scheduled_tasks.count do |i|
            i_flags = i.flags
            i_flags = [:__default] if i_flags.empty?

            next false unless i_flags.includes?(flag)

            # Half-open overlap
            overlaps? c_start, c_end, i.start, i.start + (i.task.duration || 0.seconds)
          end

        return false if concurrent + 1 > limit
      end

      true
    end
  end

  # A candidate for scheduling, points to task, time, and an explanation buffer
  struct Candidate
    getter task : VirtualDate
    getter start : Time
    getter explanation : VirtualDate::Explanation

    def initialize(@task : VirtualDate, @start : Time)
      @explanation = VirtualDate::Explanation.new
    end
  end

  # A concrete scheduled candidate of a VirtualDate task.
  class ScheduledTask
    getter task : VirtualDate
    getter start : Time
    getter finish : Time
    property explanation : VirtualDate::Explanation

    def initialize(@task : VirtualDate, @start : Time, explanation = nil)
      @finish = @start + task.duration
      @explanation = VirtualDate::Explanation.new
      @explanation.add explanation if explanation
    end

    def flags : Array(String)
      task.flags.to_a
    end

    def fixed : Bool
      task.fixed
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
      @lines << msg
      if @lines.size >= MAX_LINES
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

    private def self.resolve_dependencies(tasks : Array(VirtualDate), raw : Array(VirtualDateRaw))
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

    private def validate_root_mapping(node : YAML::Nodes::Mapping, errors : Array(YamlError))
      map = mapping_to_hash(node, errors)

      unless map["schema_version"]?
        errors << YamlError.new("Missing 'schema_version'", node)
      end

      unless map["tasks"]?.is_a?(YAML::Nodes::Sequence)
        errors << YamlError.new("'tasks' must be a sequence", node)
        return
      end

      validate_tasks(map["tasks"].as(YAML::Nodes::Sequence), errors)
    end

    private def validate_tasks(seq : YAML::Nodes::Sequence, errors : Array(YamlError))
      seq.nodes.each do |task_node|
        unless task_node.is_a?(YAML::Nodes::Mapping)
          errors << YamlError.new("Each task must be a mapping", task_node)
          next
        end

        task = build_tasks_hash(task_node, errors)

        unless task["id"]?.is_a?(YAML::Nodes::Scalar)
          errors << YamlError.new("Task missing 'id'", task_node)
        end

        if task["parallel"]?.try &.as(YAML::Nodes::Scalar)
          p = task["parallel"].as(YAML::Nodes::Scalar).value.to_i?
          if p && p < 1
            errors << YamlError.new("'parallel' must be >= 1", task["parallel"])
          end
        end

        if task["duration"]?.try &.as(YAML::Nodes::Scalar)
          d = task["duration"].as(YAML::Nodes::Scalar).value.to_i?
          if d && d < 0
            errors << YamlError.new("'duration' must be >= 0", task["duration"])
          end
        end
      end
    end

    private def build_tasks_hash(node : YAML::Nodes::Mapping, errors : Array(YamlError)) : Hash(String, YAML::Nodes::Node)
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
    @depends_on = @depends_on_ids.compact_map do |id|
      index[id]?
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
      scheduled_tasks : Array(ScheduledTask),
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

      scheduled_tasks.each do |inst|
        lines.concat event(inst, now)
      end

      lines << "END:VCALENDAR"
      lines.join("\r\n") + "\r\n"
    end

    private def self.event(inst : ScheduledTask, now : Time) : Array(String)
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

    private def self.categories(inst : ScheduledTask) : String?
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
