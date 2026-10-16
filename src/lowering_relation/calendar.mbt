///|
/// Non-wire lowering material retaining the original checked operation,
/// selected immutable table and exact bound invocation. Runtime occurrence,
/// policy, output and resource admission remain with their existing owners.
struct PreparedCalendar {
  owner : BoundPrepared
  step : Int
  node : PreparedNode
  checked : @calendar.CheckedCalendar
  table : @calendar_transition.Table
  start : String?
  end : String?
  row_bound : Int?
}

///|
pub(all) enum CalendarIssue {
  InvalidCalendarLimits
  InvalidCalendarWiring
  CalendarPreparationLimit
  MissingCalendarParameter(String)
  InvalidCalendarParameter(String)
  CalendarRange(@calendar_options.IssueKind)
} derive(Eq, Debug)

///|
fn calendar_endpoint(
  owner : BoundPrepared,
  endpoint : @calendar_options.Endpoint,
) -> Result[(String, Int, Int), CalendarIssue] {
  match endpoint {
    Literal(text) => Ok((text, 0, 0))
    Parameter(name) => {
      guard parameter_value(owner, name) is Some(bound) else {
        return Err(MissingCalendarParameter(name))
      }
      guard bound.value is @value.Timestamp(text) else {
        return Err(InvalidCalendarParameter(name))
      }
      Ok((text, 1, @utf8.encode(name).length()))
    }
  }
}

///|
fn calendar_range_bound(
  checked : @calendar.CheckedCalendar,
  table : @calendar_transition.Table,
  start : String,
  end : String,
  max_work : Int,
) -> Result[(Int, Int), CalendarIssue] {
  // This is finite static preparation over the already admitted original
  // profile, not an observed-row estimate or an acquisition scanner.
  if max_work < 2 {
    return Err(CalendarPreparationLimit)
  }
  if @calendar_options.validate_range(start, end) is Err(issue) {
    return Err(CalendarRange(issue))
  }
  if start == end {
    return Ok((0, 2))
  }
  let count = @calendar_transition.transition_count(table)
  if count > max_work - 2 {
    return Err(CalendarPreparationLimit)
  }
  let mut minimum = @calendar_transition.initial_offset(table).to_int64()
  let mut maximum = minimum
  for index in 0..<count {
    let offset = @calendar_transition.transition_at(table, index).unwrap().offset_seconds.to_int64()
    minimum = Int64::min(minimum, offset)
    maximum = Int64::max(maximum, offset)
  }
  let width = @value.timestamp_epoch_milliseconds(end).unwrap() -
    @value.timestamp_epoch_milliseconds(start).unwrap() +
    (maximum - minimum) * 1000L
  let minimum_span = match @calendar_options.unit(@calendar.options(checked)) {
    Day => 86400000L
    Week => 604800000L
    Month => 2419200000L
    Quarter => 7776000000L
    Year => 31536000000L
  }
  let interval_bound = width / minimum_span +
    (if width % minimum_span == 0L { 0L } else { 1L }) +
    2L
  guard @calendar.cardinality(checked) is AtMost(domain_bound) else {
    return Err(InvalidCalendarWiring)
  }
  Ok((Int64::min(interval_bound, domain_bound.to_int64()).to_int(), count + 2))
}

///|
fn prepare_calendar_node(
  owner : BoundPrepared,
  index : Int,
  max_rows~ : Int,
  max_cells~ : Int,
  max_bindings~ : Int,
  max_name_bytes~ : Int,
  max_work~ : Int,
) -> Result[(PreparedCalendar, Int, Int, Int), CalendarIssue] {
  if max_rows < 0 ||
    max_cells < 0 ||
    max_bindings < 0 ||
    max_name_bytes < 0 ||
    max_work < 1 {
    return Err(InvalidCalendarLimits)
  }
  guard owner.prepared.nodes.get(index) is Some(node) &&
    node.payload is CalendarValue(checked) else {
    return Err(InvalidCalendarWiring)
  }
  let options = @calendar.options(checked)
  guard @calendar_profile.zone(
      @calendar.profile(checked),
      @calendar_options.timezone(options),
    )
    is Some(table) else {
    return Err(InvalidCalendarWiring)
  }
  let mut bindings = 0
  let mut names = 0
  let mut work = 1
  let (start, end, row_bound) = match @calendar_options.input(options) {
    Field(..) => {
      if node.inputs.length() != 1 {
        return Err(InvalidCalendarWiring)
      }
      (None, None, None)
    }
    Range(start~, end~) => {
      if !node.inputs.is_empty() {
        return Err(InvalidCalendarWiring)
      }
      let (a, ab, an) = match calendar_endpoint(owner, start) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let (z, zb, zn) = match calendar_endpoint(owner, end) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      bindings = ab + zb
      names = an + zn
      if bindings > max_bindings || names > max_name_bytes {
        return Err(CalendarPreparationLimit)
      }
      let (count, used) = match
        calendar_range_bound(checked, table, a, z, max_work - work) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      work += used
      if count > max_rows || count > max_cells / 2 {
        return Err(CalendarPreparationLimit)
      }
      (Some(a), Some(z), Some(count))
    }
  }
  Ok(
    (
      { owner, step: index, node, checked, table, start, end, row_bound, },
      bindings,
      names,
      work,
    ),
  )
}

///|
pub fn calendar_owner(value : PreparedCalendar) -> BoundPrepared {
  value.owner
}

///|
pub fn calendar_checked(value : PreparedCalendar) -> @calendar.CheckedCalendar {
  value.checked
}

///|
/// Match the original resolved requirement's checked site without exposing
/// the preparation's pipeline to a backend. Identity is not execution authority.
pub fn calendar_matches_occurrence(
  value : PreparedCalendar,
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  operation : @calendar.CheckedCalendar,
) -> Bool {
  physical_equal(value.owner.prepared.owner, pipeline) &&
  value.step == step &&
  physical_equal(value.checked, operation)
}

///|
pub fn calendar_table(value : PreparedCalendar) -> @calendar_transition.Table {
  value.table
}

///|
pub fn calendar_step(value : PreparedCalendar) -> Int {
  value.step
}

///|
pub fn calendar_start(value : PreparedCalendar) -> String? {
  value.start
}

///|
pub fn calendar_end(value : PreparedCalendar) -> String? {
  value.end
}

///|
pub fn calendar_row_bound(value : PreparedCalendar) -> Int? {
  value.row_bound
}

///|
fn emit_calendar_node(
  value : PreparedCalendar,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let options = @calendar.options(value.checked)
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, value.node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in value.node.inputs {
    @encode.string_value(out, input)
  }
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, operation(value.node))
  @encode.key(out, "params")
  @encode.begin_object(out)
  match @calendar_options.input(options) {
    Range(..) => {
      @encode.key(out, "end")
      @encode.string_value(out, value.end.unwrap())
    }
    Field(into~, ..) => {
      @encode.key(out, "into")
      @encode.string_value(out, into)
    }
  }
  @encode.key(out, "profile")
  @encode.begin_object(out)
  @encode.key(out, "conversion_law")
  @encode.string_value(out, "actql-calendar-boundaries/0.1")
  @encode.key(out, "table_bytes_cid")
  @encode.string_value(
    out,
    @calendar_profile.cid(@calendar.profile(value.checked)),
  )
  @encode.key(out, "tzdb_version")
  @encode.string_value(
    out,
    @calendar_profile.tzdb_version(@calendar.profile(value.checked)),
  )
  @encode.end_object(out)
  match @calendar_options.input(options) {
    Range(..) => {
      @encode.key(out, "start")
      @encode.string_value(out, value.start.unwrap())
    }
    Field(time~, ..) => {
      @encode.key(out, "time")
      @encode.string_value(out, time)
    }
  }
  @encode.key(out, "timezone")
  @encode.string_value(out, @calendar_options.timezone(options))
  @encode.key(out, "unit")
  @encode.string_value(
    out,
    match @calendar_options.unit(options) {
      Day => "day"
      Week => "week"
      Month => "month"
      Quarter => "quarter"
      Year => "year"
    },
  )
  if @calendar_options.week_start(options) is Some(week) {
    @encode.key(out, "week_start")
    @encode.string_value(out, if week == Monday { "monday" } else { "sunday" })
  }
  @encode.end_object(out)
  @encode.end_object(out)
}
