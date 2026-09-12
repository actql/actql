///|
/// The caller has matched the owned kernel and retained input order. This
/// physical selection never creates order evidence or skips upstream execution.
fn evaluate_take_rows(
  input : Table,
  output_id : String,
  count : Int64,
  offset : Int64,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  let (start, selected) = match
    evaluate_take_selection(
      input, count, offset, max_rows, control, output, workspace,
    ) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok({
    owner: input.owner,
    id: output_id,
    names: input.names.copy(),
    rows: Array::makei(selected, i => input.rows[start + i]),
  })
}

///|
fn[T : RelationRows] evaluate_take_selection(
  input : T,
  count : Int64,
  offset : Int64,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[(Int, Int), RowIssue] {
  if count < 1L ||
    offset < 0L ||
    max_rows < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 ||
    workspace.limit < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit ||
    workspace.peak < workspace.live {
    return Err(InvalidRowLimits)
  }
  let size = IndexedRows::row_count(input)
  let names = input.field_names()
  if size > max_rows ||
    !reserve_slots(workspace, names.length()) ||
    !reserve_slots(workspace, size) {
    return Err(RowLimit)
  }
  // Charge and validate the whole admitted table, not just selected rows.
  for row = 0; row < size; row = row + 1 {
    if !spend_control(control, 1) ||
      !reserve_slots(workspace, IndexedRows::row_width(input, row)) {
      return Err(RowLimit)
    }
    if IndexedRows::row_width(input, row) != names.length() {
      return Err(InvalidRows)
    }
  }
  let start = if offset >= size.to_int64() { size } else { offset.to_int() }
  let remaining = size - start
  let selected = if count >= remaining.to_int64() {
    remaining
  } else {
    count.to_int()
  }
  if !reserve_slots(workspace, names.length()) ||
    !reserve_slots(workspace, selected) ||
    !spend_control(control, names.length()) {
    return Err(RowLimit)
  }
  for name in names {
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
  }
  for i = start; i < start + selected; i = i + 1 {
    let row = IndexedRow::{ table: input, row: i, }
    if !spend_control(control, 1) ||
      !spend_control(control, RowValues::value_count(row)) ||
      !reserve_slots(workspace, RowValues::value_count(row)) ||
      !retain_row(row, names, output) {
      return Err(RowLimit)
    }
  }
  Ok((start, selected))
}
