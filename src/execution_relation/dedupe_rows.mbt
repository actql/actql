///|
/// Consume checked grouping and order occurrences, resolving physical ordinals
/// once against this exact input. Only the selected immutable rows are retained.
fn evaluate_dedupe_rows(
  kernel : @lower.PreparedKernel,
  input : Table,
  output_id : String,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  let indices = match
    evaluate_dedupe_selection(
      kernel, input, max_rows, control, output, workspace,
    ) {
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
fn[T : RelationRows] evaluate_dedupe_selection(
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
  let checked = @lower.kernel_checked(kernel)
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
  let keys = @relation.dedupe_key_count(checked)
  let terms = @relation.dedupe_order_count(checked)
  if !reserve_slots(workspace, keys) ||
    !reserve_slots(workspace, terms) ||
    !spend_control(control, keys) ||
    !spend_control(control, terms) {
    return Err(RowLimit)
  }
  let by : Array[ColumnOrder] = []
  let order : Array[ColumnOrder] = []
  for i = 0; i < keys; i = i + 1 {
    let name = @schema.reference_name(
      @relation.dedupe_key_at(checked, i).unwrap().field,
    )
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    guard ordinals.get(name) is Some(column) else { return Err(InvalidRows) }
    by.push({ column, descending: false, nulls_first: false, })
  }
  for i = 0; i < terms; i = i + 1 {
    let term = @relation.dedupe_order_at(checked, i).unwrap()
    let name = @schema.reference_name(term.field)
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    guard ordinals.get(name) is Some(column) else { return Err(InvalidRows) }
    order.push({
      column,
      descending: term.direction is Desc,
      nulls_first: term.nulls is First,
    })
  }
  let indices = match dedupe_indices(input, by, order, control, workspace) {
    Ok(indices) => indices
    Err(Ordering(InvalidInput)) => return Err(InvalidRows)
    Err(Ordering(Limit)) => return Err(RowLimit)
    Err(Ordering(Scalar(e))) => return Err(Comparison(e))
    Err(TopTie(a, b)) => return Err(DedupeTopTie(a, b))
    Err(IdentityCollision) => return Err(DedupeIdentityCollision)
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
