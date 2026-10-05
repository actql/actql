///|
/// Borrow the row until its logical root can be issued. The enclosing driver
/// retains the input/output storage; this owner reserves only measurement
/// custody and never publishes a partially measured root.
priv struct SteppedLogicalRow[T] {
  budget : LogicalBudget
  names : Array[String]
  row : T
  workspace : RowWorkspace
  writer : @encode.Writer
  mut column : Int
  mut key_position : Int
  mut phase : Int
  mut measure : LogicalMeasureCursor?
  mut measure_reserved : Int
  mut wire : SteppedRuntimeWire?
  mut closed : Bool
}

///|
fn[T : RowValues] bounded_small_logical_row(
  names : Array[String],
  row : T,
) -> Bool {
  if names.length() > 8 || names.length() != row.value_count() {
    return false
  }
  for index, name in names {
    if name.length() > 64 ||
      (
        row.value_present(index) &&
        !bounded_small_output_value(row.value_at(index))
      ) {
      return false
    }
  }
  true
}

///|
fn[T : RowValues] start_stepped_logical_row(
  budget : LogicalBudget,
  names : Array[String],
  row : T,
  workspace : RowWorkspace,
) -> Result[SteppedLogicalRow[T], RowIssue] {
  if budget.failed {
    return Err(LogicalRows(FailedLogicalBudget))
  }
  if names.length() != row.value_count() ||
    budget.host_depth < 1 ||
    budget.host_nodes < 1 {
    budget.failed = true
    return Err(LogicalRows(ValueMeasure(HostMeasureLimit)))
  }
  if !reserve_slots(workspace, 2) {
    return Err(RowLimit)
  }
  match charge_logical_work(budget, 1L) {
    Err(issue) => {
      release_slots(workspace, 2)
      return Err(LogicalRows(issue))
    }
    Ok(_) => ()
  }
  let cap = Int64::min(
    budget.limits.max_value_bytes,
    budget.host_bytes.to_int64(),
  ).to_int()
  let writer = try {
    let writer = @encode.measuring_writer(
      cap,
      budget.host_nodes,
      budget.host_depth,
    )
    @encode.begin_object(writer)
    writer
  } catch {
    _ => {
      budget.failed = true
      release_slots(workspace, 2)
      return Err(LogicalRows(ValueMeasure(WireMeasureFailure)))
    }
  }
  Ok({
    budget,
    names,
    row,
    workspace,
    writer,
    column: 0,
    key_position: 0,
    phase: 0,
    measure: None,
    measure_reserved: 0,
    wire: None,
    closed: false,
  })
}

///|
fn[T] close_stepped_logical_row(cursor : SteppedLogicalRow[T]) -> Unit {
  if cursor.closed {
    return
  }
  if cursor.measure is Some(measure) {
    clear_logical_measure(measure)
    cursor.measure = None
  }
  release_slots(cursor.workspace, cursor.measure_reserved)
  cursor.measure_reserved = 0
  if cursor.wire is Some(wire) {
    close_stepped_runtime_wire(wire)
    cursor.wire = None
  }
  @encode.cancel_writer(cursor.writer)
  release_slots(cursor.workspace, 2)
  cursor.closed = true
}

///|
fn logical_measure_frames(cursor : LogicalMeasureCursor) -> Int {
  let wire = match cursor.emit {
    Some(CapturedWire(emit)) => @admitted.wire_emit_pending_frames(emit)
    Some(TextWire(_)) | Some(ScalarWire(_, _)) => 1
    None => 0
  }
  cursor.stack.length() + wire
}

///|
fn[T : RowValues] advance_stepped_logical_row(
  cursor : SteppedLogicalRow[T],
) -> Result[LogicalRoot?, RowIssue] {
  if cursor.closed {
    return Err(InvalidRows)
  }
  let result = advance_stepped_logical_row_impl(cursor)
  match result {
    Ok(Some(_)) | Err(_) => close_stepped_logical_row(cursor)
    Ok(None) => ()
  }
  result
}

///|
fn[T : RowValues] advance_stepped_logical_row_impl(
  cursor : SteppedLogicalRow[T],
) -> Result[LogicalRoot?, RowIssue] {
  let budget = cursor.budget
  if budget.failed {
    return Err(LogicalRows(FailedLogicalBudget))
  }
  if cursor.measure is Some(measure) {
    match
      advance_charged_logical_measure(
        measure,
        budget,
        cursor.workspace,
        cursor.measure_reserved,
      ) {
      Err(Workspace) => return Err(RowLimit)
      Err(Logical(issue)) => return Err(LogicalRows(issue))
      Ok((measured, reserved)) => {
        cursor.measure_reserved = reserved
        if measured is Some(_) {
          cursor.measure = None
          cursor.phase = 2
        }
      }
    }
    return Ok(None)
  }
  if cursor.wire is Some(wire) {
    match advance_stepped_runtime_wire(wire) {
      Err(Workspace) => return Err(RowLimit)
      Err(Encoding(issue)) => {
        // The cursor retains the exact cause; this boundary intentionally
        // projects every encoding failure to the existing row diagnostic.
        ignore(issue)
        budget.failed = true
        return Err(LogicalRows(ValueMeasure(WireMeasureFailure)))
      }
      Ok(false) => ()
      Ok(true) => {
        cursor.wire = None
        cursor.column += 1
        cursor.key_position = 0
        cursor.phase = 0
      }
    }
    return Ok(None)
  }
  if cursor.column == cursor.names.length() {
    let bytes = try {
      @encode.end_object(cursor.writer)
      @encode.finish_measurement(cursor.writer)
    } catch {
      _ => {
        budget.failed = true
        return Err(LogicalRows(ValueMeasure(WireMeasureFailure)))
      }
    }
    return match reserve_logical_bytes(budget, bytes.to_int64()) {
      Ok(root) => Ok(Some(root))
      Err(issue) => Err(LogicalRows(issue))
    }
  }
  if cursor.phase == 0 {
    if !cursor.row.value_present(cursor.column) {
      cursor.column += 1
      return Ok(None)
    }
    if cursor.column >= budget.host_nodes - 1 {
      budget.failed = true
      return Err(LogicalRows(ValueMeasure(HostMeasureLimit)))
    }
    let name = cursor.names[cursor.column]
    guard step_bounded_text_measure(name, cursor.key_position, bytes => {
        if bytes.to_int64() > budget.limits.max_work - budget.work {
          false
        } else {
          budget.work += bytes.to_int64()
          true
        }
      })
      is Some(next) else {
      budget.failed = true
      return Err(LogicalRows(WorkLimit))
    }
    cursor.key_position = next
    if next == name.length() {
      cursor.phase = 1
    }
    return Ok(None)
  }
  if cursor.phase == 1 {
    let measure = match
      start_charged_logical_measure(
        cursor.row.value_at(cursor.column),
        budget,
        cursor.workspace,
        budget.host_nodes - 1,
        budget.host_depth - 1,
      ) {
      Ok(measure) => measure
      Err(Workspace) => return Err(RowLimit)
      Err(Logical(issue)) => return Err(LogicalRows(issue))
    }
    cursor.measure_reserved = 9
    cursor.measure = Some(measure)
    return Ok(None)
  }
  @encode.key(cursor.writer, cursor.names[cursor.column]) catch {
    _ => {
      budget.failed = true
      return Err(LogicalRows(ValueMeasure(WireMeasureFailure)))
    }
  }
  match
    start_stepped_runtime_wire(
      cursor.row.value_at(cursor.column),
      cursor.writer,
      cursor.workspace,
    ) {
    Ok(wire) => cursor.wire = Some(wire)
    Err(Workspace) => return Err(RowLimit)
    Err(Encoding(_)) => {
      budget.failed = true
      return Err(LogicalRows(ValueMeasure(WireMeasureFailure)))
    }
  }
  Ok(None)
}
