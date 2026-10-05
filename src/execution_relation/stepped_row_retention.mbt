///|
/// Private row-budget traversal. The enclosing operation owns the row and its
/// storage reservation; this cursor owns only its handle and traversal frames.
priv struct SteppedRowRetention {
  row : Array[Value]
  names : Array[String]
  output : ValueBudget
  workspace : RowWorkspace
  mut column : Int
  mut name : Bool
  mut measure : SteppedValueMeasure?
  mut closed : Bool
}

///|
fn bounded_small_retained_row(
  row : Array[Value],
  names : Array[String],
) -> Bool {
  if row.length() > 8 || row.length() != names.length() {
    return false
  }
  for index, value in row {
    if names[index].length() > 64 || !bounded_small_output_value(value) {
      return false
    }
  }
  true
}

///|
fn start_stepped_row_retention(
  row : Array[Value],
  names : Array[String],
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[SteppedRowRetention, RowIssue] {
  if row.length() != names.length() {
    return Err(InvalidRows)
  }
  if !reserve_slots(workspace, 1) {
    return Err(RowLimit)
  }
  if !charge_node(output, 1) {
    release_slots(workspace, 1)
    return Err(RowLimit)
  }
  Ok({
    row,
    names,
    output,
    workspace,
    column: 0,
    name: true,
    measure: None,
    closed: false,
  })
}

///|
fn close_stepped_row_retention(cursor : SteppedRowRetention) -> Unit {
  if cursor.closed {
    return
  }
  if cursor.measure is Some(measure) {
    clear_stepped_measure(measure)
    cursor.measure = None
  }
  release_slots(cursor.workspace, 1)
  cursor.closed = true
}

///|
fn advance_stepped_row_retention(
  cursor : SteppedRowRetention,
) -> Result[Bool, RowIssue] {
  if cursor.closed {
    return Err(InvalidRows)
  }
  if cursor.measure is Some(measure) {
    match advance_stepped_measure_result(measure, cursor.output) {
      SteppedMeasureContinue => ()
      SteppedMeasureLimit | SteppedMeasureWorkspaceLimit => return Err(RowLimit)
      SteppedMeasureComplete => {
        clear_stepped_measure(measure)
        cursor.measure = None
        if cursor.name {
          cursor.name = false
        } else {
          cursor.name = true
          cursor.column += 1
        }
      }
    }
    return Ok(false)
  }
  if cursor.column == cursor.row.length() {
    close_stepped_row_retention(cursor)
    return Ok(true)
  }
  if cursor.name {
    if !reserve_slots(cursor.workspace, 1) {
      return Err(RowLimit)
    }
    cursor.measure = Some({
      frames: [SteppedTextNext(cursor.names[cursor.column], 0)],
      workspace: cursor.workspace,
      workspace_failed: false,
    })
  } else {
    guard start_stepped_measure_result(
        cursor.row[cursor.column],
        cursor.workspace,
      )
      is Some(measure) else {
      return Err(RowLimit)
    }
    cursor.measure = Some(measure)
  }
  Ok(false)
}
