///|
/// Bounded sort-merge implementation of checked complete-row EXCEPT/INTERSECT.
/// Sorting is private: survivors are always emitted in left logical order.
fn[L : RelationRows, R : RelationRows] evaluate_set_rows(
  kernel : @lower.PreparedSetKernel,
  left : L,
  right : R,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  let owner = @lower.set_kernel_owner(kernel)
  if !physical_equal(left.checked_owner(), owner) ||
    !physical_equal(right.checked_owner(), owner) {
    return Err(OwnerMismatch)
  }
  if left.relation_id() != @lower.set_kernel_input(kernel, true) ||
    right.relation_id() != @lower.set_kernel_input(kernel, false) {
    return Err(InputMismatch)
  }
  if max_rows < 0 ||
    workspace.limit < 0 ||
    workspace.live != 0 ||
    workspace.peak != 0 ||
    IndexedRows::row_count(left) > max_rows ||
    IndexedRows::row_count(right) > max_rows {
    return Err(InvalidRowLimits)
  }
  let width = @lower.set_kernel_field_count(kernel)
  if width != IndexedRows::column_count(left) ||
    width != IndexedRows::column_count(right) ||
    !reserve_slots(workspace, width * 3) ||
    !spend_control(control, width) {
    return Err(RowLimit)
  }
  let names : Array[String] = []
  let left_columns : Array[Int] = []
  let right_columns : Array[Int] = []
  let left_names = left.field_names()
  let right_names = right.field_names()
  for index in 0..<width {
    guard @lower.set_kernel_field_at(kernel, index)
      is Some((field, left_column, right_column)) else {
      return Err(InvalidRows)
    }
    let name = @schema.reference_name(field)
    if left_names.get(left_column) != Some(name) ||
      right_names.get(right_column) != Some(name) {
      return Err(InputMismatch)
    }
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    names.push(name)
    left_columns.push(left_column)
    right_columns.push(right_column)
  }
  let left_order = match
    stable_complete_order_indices(left, left_columns, control, workspace) {
    Ok(value) => value
    Err(issue) => return Err(ordering_row_issue(issue))
  }
  let right_order = match
    stable_complete_order_indices(right, right_columns, control, workspace) {
    Ok(value) => value
    Err(issue) => return Err(ordering_row_issue(issue))
  }
  if !reserve_slots(workspace, IndexedRows::row_count(left)) ||
    !spend_control(control, IndexedRows::row_count(left)) {
    return Err(RowLimit)
  }
  let keep = Array::make(IndexedRows::row_count(left), false)
  let mut left_position = 0
  let mut right_position = 0
  while left_position < left_order.length() {
    let mut left_end = left_position + 1
    while left_end < left_order.length() {
      let comparison = match
        compare_complete_row_indices(
          left,
          left_order[left_position],
          left_order[left_end],
          left_columns,
          control,
        ) {
        Ok(value) => value
        Err(issue) => return Err(ordering_row_issue(issue))
      }
      if comparison != 0 {
        break
      }
      left_end += 1
    }
    while right_position < right_order.length() {
      let comparison = match
        compare_complete_rows(
          left,
          left_order[left_position],
          left_columns,
          right,
          right_order[right_position],
          right_columns,
          control,
        ) {
        Ok(value) => value
        Err(issue) => return Err(ordering_row_issue(issue))
      }
      if comparison <= 0 {
        break
      }
      let mut next = right_position + 1
      while next < right_order.length() {
        let grouped = match
          compare_complete_row_indices(
            right,
            right_order[right_position],
            right_order[next],
            right_columns,
            control,
          ) {
          Ok(value) => value == 0
          Err(issue) => return Err(ordering_row_issue(issue))
        }
        if !grouped {
          break
        }
        next += 1
      }
      right_position = next
    }
    let mut right_count = 0
    if right_position < right_order.length() {
      let comparison = match
        compare_complete_rows(
          left,
          left_order[left_position],
          left_columns,
          right,
          right_order[right_position],
          right_columns,
          control,
        ) {
        Ok(value) => value
        Err(issue) => return Err(ordering_row_issue(issue))
      }
      if comparison == 0 {
        let mut right_end = right_position + 1
        while right_end < right_order.length() {
          let grouped = match
            compare_complete_row_indices(
              right,
              right_order[right_position],
              right_order[right_end],
              right_columns,
              control,
            ) {
            Ok(value) => value == 0
            Err(issue) => return Err(ordering_row_issue(issue))
          }
          if !grouped {
            break
          }
          right_end += 1
        }
        right_count = right_end - right_position
        right_position = right_end
      }
    }
    let left_count = left_end - left_position
    let selected = match
      (
        @lower.set_kernel_operation(kernel),
        @lower.set_kernel_duplicates(kernel),
      ) {
      (@set.Except, @set.All) => Int::max(left_count - right_count, 0)
      (@set.Intersect, @set.All) => Int::min(left_count, right_count)
      (@set.Except, @set.Distinct) => if right_count == 0 { 1 } else { 0 }
      (@set.Intersect, @set.Distinct) => if right_count > 0 { 1 } else { 0 }
    }
    for index in 0..<selected {
      keep[left_order[left_position + index]] = true
    }
    left_position = left_end
  }
  let rows : Array[Array[Value]] = []
  for row in 0..<IndexedRows::row_count(left) {
    if keep[row] {
      if rows.length() >= max_rows ||
        !reserve_slots(workspace, width) ||
        !spend_control(control, width + 1) {
        return Err(RowLimit)
      }
      let values = Array::makei(width, column => {
        IndexedRows::read_cell(left, row, left_columns[column])
      })
      if !retain_row(values, names, output) {
        return Err(RowLimit)
      }
      rows.push(values)
    }
  }
  Ok({ owner, id: @lower.set_kernel_output(kernel), names, rows, })
}
