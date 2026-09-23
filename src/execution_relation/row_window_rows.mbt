///|
fn window_timestamp_milliseconds(text : String) -> Double? {
  match @admitted.timestamp_epoch_milliseconds(text) {
    Some(value) => Some(value.to_double())
    None => None
  }
}

///|
priv enum WindowTimeReadIssue {
  InvalidWindowTime
  WindowTimeResourceLimit
}

///|
fn window_time_row_issue(issue : WindowTimeReadIssue, row : Int) -> RowIssue {
  match issue {
    InvalidWindowTime => WindowTime(row)
    WindowTimeResourceLimit => RowLimit
  }
}

///|
fn window_time_milliseconds(
  value : Value,
  timestamp : Bool,
  control : ControlBudget,
) -> Result[Double, WindowTimeReadIssue] {
  if timestamp {
    guard value is Captured(@admitted.Timestamp(text)) else {
      return Err(InvalidWindowTime)
    }
    if !spend_control_text(control, text) {
      return Err(WindowTimeResourceLimit)
    }
    match window_timestamp_milliseconds(text) {
      Some(value) => Ok(value)
      None => Err(InvalidWindowTime)
    }
  } else {
    match value {
      Number(number) if !number.is_nan() && !number.is_inf() => Ok(number)
      _ => Err(InvalidWindowTime)
    }
  }
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
) -> Result[@grid.Coordinate, WindowTimeReadIssue] {
  if timestamp {
    guard value is Captured(@admitted.Timestamp(text)) else {
      return Err(InvalidWindowTime)
    }
    if !spend_control_text(control, text) {
      return Err(WindowTimeResourceLimit)
    }
    match @admitted.timestamp_epoch_milliseconds(text) {
      Some(milliseconds) => Ok(@grid.from_timestamp_milliseconds(milliseconds))
      None => Err(InvalidWindowTime)
    }
  } else {
    guard value is Number(number) && !number.is_nan() && !number.is_inf() else {
      return Err(InvalidWindowTime)
    }
    match @grid.from_finite_number(number) {
      Some(coordinate) => Ok(coordinate)
      None => Err(InvalidWindowTime)
    }
  }
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
  let size = @bigint.BigInt::from_int64(size_integer)
  let step = @bigint.BigInt::from_int64(step_integer)
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
    let time = match
      window_time_coordinate(
        IndexedRows::read_cell(input, source, time_column),
        @lower.window_requires_epoch_milliseconds(window),
        control,
      ) {
      Ok(value) => value
      Err(issue) => return Err(window_time_row_issue(issue, source))
    }
    let memberships : Array[WindowMembership] = []
    let mut current = @grid.latest_start(time, step_integer, offset_integer)
    while true {
      let end = current + size
      if @grid.compare(time, current) < 0 || @grid.compare(time, end) >= 0 {
        break
      }
      if result.length() >= max_rows ||
        memberships.length() >= max_rows - result.length() ||
        !reserve_slots(workspace, 1) ||
        !spend_control(control, 1) {
        return Err(RowLimit)
      }
      guard @grid.exact_binary64_boundary(current) is Some(start_number) &&
        @grid.exact_binary64_boundary(end) is Some(end_number) else {
        return Err(WindowArithmetic(source))
      }
      memberships.push({ start: start_number, end: end_number, })
      if @lower.window_kind(window) == @window.Fixed {
        break
      }
      current -= step
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
