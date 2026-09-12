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
  if count < 1L ||
    offset < 0L ||
    max_rows < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 ||
    workspace.limit < 0 ||
    workspace.live != 0 ||
    workspace.peak != 0 {
    return Err(InvalidRowLimits)
  }
  let size = input.rows.length()
  if size > max_rows ||
    !reserve_slots(workspace, input.names.length()) ||
    !reserve_slots(workspace, size) {
    return Err(RowLimit)
  }
  // Charge and validate the whole admitted table, not just selected rows.
  for row in input.rows {
    if !spend_control(control, 1) || !reserve_slots(workspace, row.length()) {
      return Err(RowLimit)
    }
    if row.length() != input.names.length() {
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
  if !reserve_slots(workspace, input.names.length()) ||
    !reserve_slots(workspace, selected) ||
    !spend_control(control, input.names.length()) {
    return Err(RowLimit)
  }
  for name in input.names {
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
  }
  let rows : Array[Array[Value]] = []
  for i = start; i < start + selected; i = i + 1 {
    let row = input.rows[i]
    if !spend_control(control, 1) ||
      !spend_control(control, row.length()) ||
      !reserve_slots(workspace, row.length()) ||
      !retain_row(row, input.names, output) {
      return Err(RowLimit)
    }
    rows.push(row)
  }
  Ok({ owner: input.owner, id: output_id, names: input.names.copy(), rows, })
}
