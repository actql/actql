///|
/// Full-row distinct on the schema admitted by the common preparation boundary.
/// Keeps input occurrence order; key-index ordering is not observable.
fn evaluate_distinct_rows(
  input : Table,
  output_id : String,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  if max_rows < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 ||
    workspace.limit < 0 ||
    workspace.live != 0 ||
    workspace.peak != 0 {
    return Err(InvalidRowLimits)
  }
  if input.rows.length() > max_rows ||
    !reserve_slots(workspace, input.rows.length()) ||
    !reserve_slots(workspace, input.names.length()) {
    return Err(RowLimit)
  }
  for row in input.rows {
    if !spend_control(control, 1) || !reserve_slots(workspace, row.length()) {
      return Err(RowLimit)
    }
  }
  let width = input.names.length()
  if !reserve_slots(workspace, width) || !spend_control(control, width) {
    return Err(RowLimit)
  }
  let columns = Array::makei(width, i => i)
  let indices = match distinct_indices(input, columns, control, workspace) {
    Ok(v) => v
    Err(InvalidInput) => return Err(InvalidRows)
    Err(Limit) => return Err(RowLimit)
    Err(Scalar(e)) => return Err(Comparison(e))
  }
  if !reserve_slots(workspace, indices.length()) ||
    !reserve_slots(workspace, width) ||
    !spend_control(control, width) {
    return Err(RowLimit)
  }
  for name in input.names {
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
  }
  let rows : Array[Array[Value]] = []
  for index in indices {
    let row = input.rows[index]
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
