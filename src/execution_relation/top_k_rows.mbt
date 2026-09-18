///|
/// Global and partitioned top-k share the checked total ranking order. The
/// partition prefix is canonical ascending/NULLS FIRST and remains separate
/// from the authored ranking terms retained by the lowering boundary.
fn[T : RelationRows] evaluate_top_k_selection(
  kernel : @lower.PreparedKernel,
  input : T,
  count : Int64,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Array[Int], RowIssue] {
  if count < 1L ||
    max_rows < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 ||
    workspace.limit < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit ||
    workspace.peak < workspace.live {
    return Err(InvalidRowLimits)
  }
  let names = input.field_names()
  let width = names.length()
  let rows = IndexedRows::row_count(input)
  if rows > max_rows ||
    !reserve_slots(workspace, rows) ||
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
  for row = 0; row < rows; row = row + 1 {
    if IndexedRows::row_width(input, row) != width {
      return Err(InvalidRows)
    }
    if !spend_control(control, 1) || !reserve_slots(workspace, width) {
      return Err(RowLimit)
    }
  }
  let partitions = @lower.kernel_top_k_partition_count(kernel)
  let terms = @lower.kernel_sort_term_count(kernel)
  if !reserve_slots(workspace, partitions) ||
    !reserve_slots(workspace, terms) ||
    !spend_control(control, partitions) ||
    !spend_control(control, terms) {
    return Err(RowLimit)
  }
  let partition_order : Array[ColumnOrder] = []
  for i = 0; i < partitions; i = i + 1 {
    let field = @lower.kernel_top_k_partition_at(kernel, i).unwrap()
    let name = @schema.reference_name(field)
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    guard ordinals.get(name) is Some(column) else { return Err(InvalidRows) }
    partition_order.push({ column, descending: false, nulls_first: true, })
  }
  let ranking_order : Array[ColumnOrder] = []
  for i = 0; i < terms; i = i + 1 {
    let (field, descending, nulls_first) = @lower.kernel_sort_term_at(kernel, i).unwrap()
    let name = @schema.reference_name(field)
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    guard ordinals.get(name) is Some(column) else { return Err(InvalidRows) }
    ranking_order.push({ column, descending, nulls_first, })
  }
  let complete_order = partition_order.copy()
  for term in ranking_order {
    complete_order.push(term)
  }
  let sorted = match
    stable_order_indices(input, complete_order, control, workspace) {
    Ok(indices) => indices
    Err(InvalidInput) => return Err(InvalidRows)
    Err(Limit) => return Err(RowLimit)
    Err(Scalar(issue)) => return Err(Comparison(issue))
  }
  let selected : Array[Int] = []
  let mut leader = -1
  let mut in_partition = 0L
  for index in sorted {
    let new_partition = if leader < 0 {
      true
    } else if partition_order.is_empty() {
      false
    } else {
      match
        compare_row_indices(input, leader, index, partition_order, control) {
        Ok(comparison) => comparison != 0
        Err(InvalidInput) => return Err(InvalidRows)
        Err(Limit) => return Err(RowLimit)
        Err(Scalar(issue)) => return Err(Comparison(issue))
      }
    }
    if new_partition {
      leader = index
      in_partition = 0L
    }
    if in_partition < count {
      if !reserve_slots(workspace, 1) || !spend_control(control, 1) {
        return Err(RowLimit)
      }
      selected.push(index)
    }
    in_partition += 1L
  }
  if selected.length() > max_rows ||
    !reserve_slots(workspace, selected.length()) ||
    !reserve_slots(workspace, width) ||
    !spend_control(control, width) {
    return Err(RowLimit)
  }
  for name in names {
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
  }
  for index in selected {
    let row = IndexedRow::{ table: input, row: index, }
    if !spend_control(control, 1) ||
      !spend_control(control, RowValues::value_count(row)) ||
      !reserve_slots(workspace, RowValues::value_count(row)) ||
      !retain_row(row, names, output) {
      return Err(RowLimit)
    }
  }
  Ok(selected)
}

///|
fn evaluate_top_k_rows(
  kernel : @lower.PreparedKernel,
  input : Table,
  output_id : String,
  count : Int64,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  let indices = match
    evaluate_top_k_selection(
      kernel, input, count, max_rows, control, output, workspace,
    ) {
    Ok(indices) => indices
    Err(issue) => return Err(issue)
  }
  Ok({
    owner: input.owner,
    id: output_id,
    names: input.names.copy(),
    rows: indices.map(index => input.rows[index]),
  })
}
