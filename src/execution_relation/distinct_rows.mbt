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
  let indices = match
    evaluate_distinct_selection(input, max_rows, control, output, workspace) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok({
    owner: input.owner,
    id: output_id,
    names: input.names.copy(),
    rows: indices.map(i => input.rows[i]),
  })
}

///|
fn[T : RelationRows] evaluate_distinct_selection(
  input : T,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Array[Int], RowIssue] {
  if max_rows < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 ||
    workspace.limit < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit ||
    workspace.peak < workspace.live {
    return Err(InvalidRowLimits)
  }
  let count = IndexedRows::row_count(input)
  let names = input.field_names()
  if count > max_rows ||
    !reserve_slots(workspace, count) ||
    !reserve_slots(workspace, names.length()) {
    return Err(RowLimit)
  }
  for row = 0; row < count; row = row + 1 {
    if !spend_control(control, 1) ||
      !reserve_slots(workspace, IndexedRows::row_width(input, row)) {
      return Err(RowLimit)
    }
  }
  let width = names.length()
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
  for name in names {
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
  }
  for index in indices {
    let row = IndexedRow::{ table: input, row: index, }
    if !spend_control(control, 1) ||
      !spend_control(control, RowValues::value_count(row)) ||
      !reserve_slots(workspace, RowValues::value_count(row)) ||
      !retain_row(row, names, output) {
      return Err(RowLimit)
    }
  }
  Ok(indices)
}
