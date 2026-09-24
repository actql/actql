///|
/// Compute navigation in the checked complete partition order while retaining
/// the original occurrence order in the result.
fn[T : RelationRows] evaluate_lag_rows(
  kernel : @lower.PreparedKernel,
  input : T,
  output_id : String,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  if max_rows < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit ||
    workspace.peak < workspace.live {
    return Err(InvalidRowLimits)
  }
  guard @lower.kernel_lag(kernel) is Some((field, output_name, offset)) else {
    return Err(InvalidRows)
  }
  let names = input.field_names()
  let width = names.length()
  let count = IndexedRows::row_count(input)
  if count > max_rows ||
    !reserve_slots(workspace, width) ||
    !reserve_slots(workspace, count) ||
    !reserve_slots(workspace, count) {
    return Err(RowLimit)
  }
  let ordinals : Map[String, Int] = Map([])
  for index in 0..<width {
    if !spend_control(control, 1) || !spend_control_text(control, names[index]) {
      return Err(RowLimit)
    }
    if ordinals.contains(names[index]) {
      return Err(InvalidRows)
    }
    ordinals[names[index]] = index
  }
  let source_name = @schema.reference_name(field)
  if !spend_control_text(control, source_name) ||
    !spend_control_text(control, output_name) {
    return Err(RowLimit)
  }
  guard ordinals.get(source_name) is Some(source_column) else {
    return Err(InvalidRows)
  }
  let partition_count = @lower.kernel_lag_partition_count(kernel)
  let order_count = @lower.kernel_sort_term_count(kernel)
  if !reserve_slots(workspace, partition_count) ||
    !reserve_slots(workspace, order_count) ||
    !spend_control(control, partition_count + order_count) {
    return Err(RowLimit)
  }
  let partitions : Array[ColumnOrder] = []
  let complete : Array[ColumnOrder] = []
  for index in 0..<partition_count {
    let name = @schema.reference_name(
      @lower.kernel_lag_partition_at(kernel, index).unwrap(),
    )
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    guard ordinals.get(name) is Some(column) else { return Err(InvalidRows) }
    let term = { column, descending: false, nulls_first: true, }
    partitions.push(term)
    complete.push(term)
  }
  for index in 0..<order_count {
    let (field, descending, nulls_first) = @lower.kernel_sort_term_at(
      kernel, index,
    ).unwrap()
    let name = @schema.reference_name(field)
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    guard ordinals.get(name) is Some(column) else { return Err(InvalidRows) }
    complete.push({ column, descending, nulls_first, })
  }
  let sorted = match stable_order_indices(input, complete, control, workspace) {
    Ok(indices) => indices
    Err(issue) => return Err(ordering_row_issue(issue))
  }
  let lagged = Array::make(count, Null)
  let mut start = 0
  for position in 0..<sorted.length() {
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    if position > 0 {
      let same = match
        compare_row_indices(
          input,
          sorted[position - 1],
          sorted[position],
          partitions,
          control,
        ) {
        Ok(value) => value == 0
        Err(issue) => return Err(ordering_row_issue(issue))
      }
      if !same {
        start = position
      }
    }
    let within = position - start
    if Int64::from_int(within) >= offset {
      lagged[sorted[position]] = IndexedRows::read_cell(
        input,
        sorted[position - offset.to_int()],
        source_column,
      )
    }
  }
  let output_width = width + 1
  if !reserve_slots(workspace, output_width) ||
    !spend_control(control, output_width) {
    return Err(RowLimit)
  }
  let output_names = names.copy()
  output_names.push(output_name)
  let rows : Array[Array[Value]] = []
  for row in 0..<count {
    if IndexedRows::row_width(input, row) != width {
      return Err(InvalidRows)
    }
    if !spend_control(control, 1) ||
      !spend_control(control, width + 1) ||
      !reserve_slots(workspace, width + 1) {
      return Err(RowLimit)
    }
    let values = Array::makei(width, column => {
      IndexedRows::read_cell(input, row, column)
    })
    values.push(lagged[row])
    if !retain_row(values, output_names, output) {
      return Err(RowLimit)
    }
    rows.push(values)
  }
  Ok({ owner: input.checked_owner(), id: output_id, names: output_names, rows, })
}
