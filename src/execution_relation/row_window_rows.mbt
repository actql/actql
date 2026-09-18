///|
fn window_digits(text : String, start : Int, end : Int) -> Int? {
  if start < 0 || end < start || end > text.length() {
    return None
  }
  let mut value = 0
  for i in start..<end {
    if text[i] < '0' || text[i] > '9' {
      return None
    }
    value = value * 10 + text[i].to_int() - 48
  }
  Some(value)
}

///|
// Admission has already checked the canonical fixed-width UTC spelling. This
// defensive reader still rejects malformed physical values and uses the Unix
// epoch required by the window grid rather than the year-zero duration origin.
fn window_timestamp_milliseconds64(text : String) -> Int64? {
  if text.length() != 24 ||
    text[4] != '-' ||
    text[7] != '-' ||
    text[10] != 'T' ||
    text[13] != ':' ||
    text[16] != ':' ||
    text[19] != '.' ||
    text[23] != 'Z' {
    return None
  }
  guard window_digits(text, 0, 4) is Some(year) &&
    window_digits(text, 5, 7) is Some(month) &&
    window_digits(text, 8, 10) is Some(day) &&
    window_digits(text, 11, 13) is Some(hour) &&
    window_digits(text, 14, 16) is Some(minute) &&
    window_digits(text, 17, 19) is Some(second) &&
    window_digits(text, 20, 23) is Some(millisecond) else {
    return None
  }
  if month < 1 ||
    month > 12 ||
    day < 1 ||
    day > 31 ||
    hour > 23 ||
    minute > 59 ||
    second > 59 ||
    millisecond > 999 {
    return None
  }
  let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
  let before_month = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
  let leap_day = if leap && month > 2 { 1 } else { 0 }
  let days = 365 * year +
    (year + 3) / 4 -
    (year + 99) / 100 +
    (year + 399) / 400 +
    before_month[month - 1] +
    day -
    1 +
    leap_day -
    719528
  Some(
    days.to_int64() * 86400000L +
    hour.to_int64() * 3600000L +
    minute.to_int64() * 60000L +
    second.to_int64() * 1000L +
    millisecond.to_int64(),
  )
}

///|
fn window_timestamp_milliseconds(text : String) -> Double? {
  match window_timestamp_milliseconds64(text) {
    Some(value) => Some(value.to_double())
    None => None
  }
}

///|
fn window_time_milliseconds(
  value : Value,
  timestamp : Bool,
  control : ControlBudget,
) -> Double? {
  if timestamp {
    guard value is Captured(@admitted.Timestamp(text)) &&
      spend_control_text(control, text) else {
      return None
    }
    window_timestamp_milliseconds(text)
  } else {
    match value {
      Number(number) if !number.is_nan() && !number.is_inf() => Some(number)
      _ => None
    }
  }
}

///|
fn window_latest_start(
  time : Double,
  step : Double,
  offset : Double,
) -> Double? {
  let shifted = (time - offset) / step
  if shifted.is_nan() || shifted.is_inf() {
    return None
  }
  let start = shifted.floor() * step + offset
  if start.is_nan() || start.is_inf() || start > time {
    None
  } else {
    Some(if start == 0.0 { 0.0 } else { start })
  }
}

///|
priv enum WindowCoordinate {
  ExactFloor(Int64)
  Binary64(Double)
}

///|
priv struct WindowMembership {
  start : Double
  end : Double
}

///|
fn window_time_coordinate(
  value : Value,
  timestamp : Bool,
  control : ControlBudget,
) -> WindowCoordinate? {
  if timestamp {
    guard value is Captured(@admitted.Timestamp(text)) &&
      spend_control_text(control, text) &&
      window_timestamp_milliseconds64(text) is Some(milliseconds) else {
      return None
    }
    Some(ExactFloor(milliseconds))
  } else {
    guard value is Number(number) && !number.is_nan() && !number.is_inf() else {
      return None
    }
    match @scalar.read_safe_integer(number.floor()) {
      Some(floor) => Some(ExactFloor(floor))
      None => Some(Binary64(number))
    }
  }
}

///|
fn window_floor_mod(value : Int64, divisor : Int64) -> Int64 {
  let remainder = value % divisor
  if remainder < 0L {
    remainder + divisor
  } else {
    remainder
  }
}

///|
fn window_floor_div(value : Int64, divisor : Int64) -> Int64 {
  let quotient = value / divisor
  if value % divisor < 0L {
    quotient - 1L
  } else {
    quotient
  }
}

///|
fn window_exact_double(value : Int64) -> Double? {
  if value < -9007199254740991L || value > 9007199254740991L {
    None
  } else {
    Some(value.to_double())
  }
}

///|
fn window_latest_start_integer(
  time_floor : Int64,
  step : Int64,
  offset : Int64,
) -> Int64 {
  // Normalize only the arithmetic grid. The authored offset remains unchanged
  // in the checked operation and canonical identity.
  let grid = window_floor_mod(offset, step)
  window_floor_div(time_floor - grid, step) * step + grid
}

///|
// Assign fixed or sliding memberships without allocating from the declared
// expansion bound. Temporary starts are bounded by the remaining output rows.
fn[T : RelationRows] evaluate_window_rows(
  window : @lower.PreparedWindow,
  input : T,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  if max_rows < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 ||
    workspace.limit < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit ||
    workspace.peak < workspace.live {
    return Err(InvalidRowLimits)
  }
  if !physical_equal(
      RelationRows::checked_owner(input),
      @lower.window_owner(window),
    ) {
    return Err(OwnerMismatch)
  }
  if RelationRows::relation_id(input) != @lower.window_input(window) {
    return Err(InputMismatch)
  }
  let prepared = @lower.bound_preparation(@lower.window_owner(window))
  guard @lower.node_at(prepared, @lower.window_step_index(window)) is Some(node) else {
    return Err(InvalidRows)
  }
  let names = RelationRows::field_names(input)
  let width = names.length()
  let output_schema = @lower.node_output_schema(node)
  let output_names = Array::makei(@schema.field_count(output_schema), i => {
    @schema.reference_name(@schema.field_at(output_schema, i).unwrap().name)
  })
  let (start_field, end_field) = @lower.window_boundaries(window)
  let start_name = @schema.reference_name(start_field)
  let end_name = @schema.reference_name(end_field)
  if output_names.length() != width + 2 {
    return Err(InvalidRows)
  }
  let mut time_column = -1
  let time_name = @schema.reference_name(@lower.window_time(window))
  let ordinals : Map[String, Int] = Map([])
  for i = 0; i < width; i = i + 1 {
    if ordinals.contains(names[i]) {
      return Err(InvalidRows)
    }
    if !spend_control(control, 1) || !spend_control_text(control, names[i]) {
      return Err(RowLimit)
    }
    ordinals[names[i]] = i
    if names[i] == time_name {
      if time_column >= 0 {
        return Err(InvalidRows)
      }
      time_column = i
    }
  }
  if time_column < 0 ||
    !spend_control_text(control, start_name) ||
    !spend_control_text(control, end_name) {
    return Err(if time_column < 0 { InvalidRows } else { RowLimit })
  }
  let mut saw_start = false
  let mut saw_end = false
  for name in output_names {
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    if name == start_name {
      if saw_start {
        return Err(InvalidRows)
      }
      saw_start = true
    } else if name == end_name {
      if saw_end {
        return Err(InvalidRows)
      }
      saw_end = true
    } else if !ordinals.contains(name) {
      return Err(InvalidRows)
    }
  }
  if !saw_start || !saw_end {
    return Err(InvalidRows)
  }
  let input_count = IndexedRows::row_count(input)
  if input_count > max_rows ||
    !reserve_slots(workspace, input_count) ||
    !reserve_slots(workspace, width) ||
    !reserve_slots(workspace, output_names.length()) {
    return Err(RowLimit)
  }
  let size_integer = @lower.window_size(window)
  let step_integer = @lower.window_effective_step(window)
  let offset_integer = @lower.window_offset(window)
  if size_integer <= 0L || step_integer <= 0L {
    return Err(InvalidRows)
  }
  let size = size_integer.to_double()
  let step = step_integer.to_double()
  let arithmetic_offset = window_floor_mod(offset_integer, step_integer).to_double()
  let result : Array[Array[Value]] = []
  for source = 0; source < input_count; source = source + 1 {
    if IndexedRows::row_width(input, source) != width ||
      !spend_control(control, 1) ||
      !reserve_slots(workspace, width) {
      return Err(
        if IndexedRows::row_width(input, source) != width {
          InvalidRows
        } else {
          RowLimit
        },
      )
    }
    guard window_time_coordinate(
        IndexedRows::read_cell(input, source, time_column),
        @lower.window_requires_epoch_milliseconds(window),
        control,
      )
      is Some(time) else {
      return Err(WindowTime(source))
    }
    let memberships : Array[WindowMembership] = []
    match time {
      ExactFloor(time_floor) => {
        let mut current = window_latest_start_integer(
          time_floor, step_integer, offset_integer,
        )
        while true {
          if current > 9223372036854775807L - size_integer {
            return Err(WindowArithmetic(source))
          }
          let end = current + size_integer
          if current > time_floor || time_floor >= end {
            break
          }
          if result.length() >= max_rows ||
            memberships.length() >= max_rows - result.length() ||
            !reserve_slots(workspace, 1) ||
            !spend_control(control, 1) {
            return Err(RowLimit)
          }
          guard window_exact_double(current) is Some(start_number) &&
            window_exact_double(end) is Some(end_number) else {
            return Err(WindowArithmetic(source))
          }
          memberships.push({ start: start_number, end: end_number, })
          if @lower.window_kind(window) == @window.Fixed {
            break
          }
          if current < -9223372036854775807L - 1L + step_integer {
            return Err(WindowArithmetic(source))
          }
          current -= step_integer
        }
      }
      Binary64(time) => {
        guard window_latest_start(time, step, arithmetic_offset) is Some(latest) else {
          return Err(WindowArithmetic(source))
        }
        let mut current = latest
        while true {
          let end = current + size
          if end.is_nan() || end.is_inf() || end <= current {
            return Err(WindowArithmetic(source))
          }
          if current > time || time >= end {
            break
          }
          if result.length() >= max_rows ||
            memberships.length() >= max_rows - result.length() ||
            !reserve_slots(workspace, 1) ||
            !spend_control(control, 1) {
            return Err(RowLimit)
          }
          memberships.push({ start: current, end, })
          if @lower.window_kind(window) == @window.Fixed {
            break
          }
          let next = current - step
          if next.is_nan() || next.is_inf() || next >= current {
            return Err(WindowArithmetic(source))
          }
          current = next
        }
      }
    }
    for occurrence = 0
        occurrence < memberships.length()
        occurrence = occurrence + 1 {
      let membership = memberships[memberships.length() - occurrence - 1]
      if !reserve_slots(workspace, output_names.length()) ||
        !spend_control(control, output_names.length()) {
        return Err(RowLimit)
      }
      let row = Array::makei(output_names.length(), column => {
        let name = output_names[column]
        if name == start_name {
          Number(membership.start)
        } else if name == end_name {
          Number(membership.end)
        } else {
          IndexedRows::read_cell(input, source, ordinals.get(name).unwrap())
        }
      })
      if !retain_row(row, output_names, output) {
        return Err(RowLimit)
      }
      result.push(row)
    }
    release_slots(workspace, memberships.length())
  }
  Ok({
    owner: @lower.window_owner(window),
    id: @lower.node_id(node),
    names: output_names,
    rows: result,
  })
}
