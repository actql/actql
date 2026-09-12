///|
/// The complete order comes from the owned checked kernel. Stable input-relative
/// ties are implemented by the index merge, not by an extra identity key.
fn evaluate_sort_rows(
  kernel : @lower.PreparedKernel,
  input : Table,
  output_id : String,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  let indices = match
    evaluate_sort_selection(kernel, input, max_rows, control, output, workspace) {
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
fn[T : RelationRows] evaluate_sort_selection(
  kernel : @lower.PreparedKernel,
  input : T,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Array[Int], RowIssue] {
  if max_rows < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit ||
    workspace.peak < workspace.live {
    return Err(InvalidRowLimits)
  }
  let names = input.field_names()
  let width = names.length()
  let count_rows = IndexedRows::row_count(input)
  if count_rows > max_rows ||
    !reserve_slots(workspace, count_rows) ||
    !reserve_slots(workspace, width) ||
    !reserve_slots(workspace, width) {
    return Err(RowLimit)
  }
  let ordinals : Map[String, Int] = Map([])
  for i = 0; i < width; i = i + 1 {
    if !spend_control(control, 1) || !spend_control_text(control, names[i]) {
      return Err(RowLimit)
    }
    if ordinals.contains(names[i]) {
      return Err(InvalidRows)
    }
    ordinals[names[i]] = i
  }
  for row = 0; row < count_rows; row = row + 1 {
    if IndexedRows::row_width(input, row) != width {
      return Err(InvalidRows)
    }
    if !spend_control(control, 1) || !reserve_slots(workspace, width) {
      return Err(RowLimit)
    }
  }
  let count = @lower.kernel_sort_term_count(kernel)
  if !reserve_slots(workspace, count) || !spend_control(control, count) {
    return Err(RowLimit)
  }
  let order : Array[ColumnOrder] = []
  for i = 0; i < count; i = i + 1 {
    let (field, descending, nulls_first) = @lower.kernel_sort_term_at(kernel, i).unwrap()
    let name = @schema.reference_name(field)
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    guard ordinals.get(name) is Some(column) else { return Err(InvalidRows) }
    order.push({ column, descending, nulls_first, })
  }
  let indices = match stable_order_indices(input, order, control, workspace) {
    Ok(indices) => indices
    Err(InvalidInput) => return Err(InvalidRows)
    Err(Limit) => return Err(RowLimit)
    Err(Scalar(e)) => return Err(Comparison(e))
  }
  if !reserve_slots(workspace, indices.length()) ||
    !reserve_slots(workspace, width) ||
    !spend_control(control, width) {
    return Err(RowLimit)
  }
  for index in indices {
    let row = IndexedRow::{ table: input, row: index, }
    if !spend_control(control, 1) ||
      !spend_control(control, width) ||
      !reserve_slots(workspace, width) ||
      !retain_row(row, names, output) {
      return Err(RowLimit)
    }
  }
  Ok(indices)
}
