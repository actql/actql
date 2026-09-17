///|
/// Preserve append's left-then-right logical order while applying the checked
/// field alignment. This initial layout owns copied rows; later physical views
/// may share immutable storage behind the same typed callback contract.
fn[T : RelationRows] evaluate_append_rows(
  kernel : @lower.PreparedAppendKernel,
  left : T,
  right : T,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  if max_rows < 0 ||
    !physical_equal(
      RelationRows::checked_owner(left),
      @lower.append_kernel_owner(kernel),
    ) ||
    !physical_equal(
      RelationRows::checked_owner(right),
      @lower.append_kernel_owner(kernel),
    ) {
    return Err(OwnerMismatch)
  }
  let left_count = IndexedRows::row_count(left)
  let right_count = IndexedRows::row_count(right)
  if left_count > max_rows || right_count > max_rows - left_count {
    return Err(RowLimit)
  }
  let width = @lower.append_kernel_field_count(kernel)
  if IndexedRows::column_count(left) < width ||
    IndexedRows::column_count(right) < width ||
    !reserve_slots(workspace, left_count + right_count) ||
    !reserve_slots(workspace, left_count + right_count) ||
    !reserve_slots(workspace, width) {
    return Err(RowLimit)
  }
  let left_names = RelationRows::field_names(left)
  let right_names = RelationRows::field_names(right)
  let names : Array[String] = []
  let left_columns : Array[Int] = []
  let right_columns : Array[Int] = []
  for index in 0..<width {
    guard @lower.append_kernel_field_at(kernel, index) is Some((field, li, ri)) &&
      left_names.get(li) == Some(@schema.reference_name(field)) &&
      right_names.get(ri) == Some(@schema.reference_name(field)) else {
      return Err(InputMismatch)
    }
    let name = @schema.reference_name(field)
    if !spend_control(control, 1) ||
      !spend_control_text(control, name) ||
      !reserve_slots(workspace, 2) {
      return Err(RowLimit)
    }
    names.push(name)
    left_columns.push(li)
    right_columns.push(ri)
  }
  let rows : Array[Array[Value]] = []
  let append = fn(input : T, columns : Array[Int]) -> Result[Unit, RowIssue] {
    for row in 0..<IndexedRows::row_count(input) {
      if !spend_control(control, 1) ||
        !spend_control(control, width) ||
        !reserve_slots(workspace, width) ||
        !reserve_slots(workspace, width) {
        return Err(RowLimit)
      }
      let values = Array::makei(width, column => {
        IndexedRows::read_cell(input, row, columns[column])
      })
      if !retain_row(values, names, output) {
        return Err(RowLimit)
      }
      rows.push(values)
    }
    Ok(())
  }
  match append(left, left_columns) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match append(right, right_columns) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok({
    owner: @lower.append_kernel_owner(kernel),
    id: @lower.append_kernel_output(kernel),
    names,
    rows,
  })
}
