///|
/// Execute the checked left-major Cartesian product without materializing an
/// unprojected intermediate. The singleton assertion is checked before output.
fn[L : RelationRows, R : RelationRows] evaluate_cross_join_rows(
  kernel : @lower.PreparedCrossJoinKernel,
  left : L,
  right : R,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  selected_ceiling? : (Int, Int64)? = None,
) -> Result[Table, RowIssue] {
  let owner = @lower.cross_join_kernel_owner(kernel)
  if !physical_equal(left.checked_owner(), owner) ||
    !physical_equal(right.checked_owner(), owner) {
    return Err(OwnerMismatch)
  }
  if left.relation_id() != @lower.cross_join_kernel_input(kernel, true) ||
    right.relation_id() != @lower.cross_join_kernel_input(kernel, false) {
    return Err(InputMismatch)
  }
  if max_rows < 0 ||
    workspace.live != 0 ||
    workspace.peak != 0 ||
    workspace.limit < 0 {
    return Err(InvalidRowLimits)
  }
  let left_count = IndexedRows::row_count(left)
  let right_count = IndexedRows::row_count(right)
  if left_count > max_rows || right_count > max_rows {
    return Err(RowLimit)
  }
  let profile = @lower.cross_join_kernel_profile(kernel)
  if @lower.cross_join_requires_one_right(profile) && right_count != 1 {
    return Err(InvalidRows)
  }
  let mut ceiling = match @lower.cross_join_kernel_output_limit(kernel) {
    Some(limit) if limit < max_rows.to_int64() => limit.to_int()
    _ => max_rows
  }
  if selected_ceiling is Some((step, bound)) &&
    step == @lower.cross_join_kernel_step(kernel) {
    if bound < 0L {
      return Err(InvalidRowLimits)
    }
    if bound < ceiling.to_int64() {
      ceiling = bound.to_int()
    }
  }
  if right_count != 0 && left_count > ceiling / right_count {
    return Err(RowLimit)
  }
  let resolve = fn(
    names : Array[String],
    field : @schema.FieldName,
  ) -> Result[Int, RowIssue] {
    let reference = @schema.reference_name(field)
    for index, name in names {
      if !spend_control(control, 1) ||
        !spend_control_text(control, reference) ||
        !spend_control_text(control, name) {
        return Err(RowLimit)
      }
      if name == reference {
        return Ok(index)
      }
    }
    Err(InvalidRows)
  }
  let width = @lower.cross_join_field_count(profile)
  let mut retained = 0
  let run = fn() -> Result[Table, RowIssue] {
    let names : Array[String] = []
    let columns : Array[(Bool, Int)] = []
    for index in 0..<width {
      if !reserve_slots(workspace, 3) || !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let field = @lower.cross_join_field_at(profile, index).unwrap()
      let name = @schema.reference_name(field.output)
      if !spend_control_text(control, name) {
        return Err(RowLimit)
      }
      names.push(name)
      retained += 1
      let (on_left, source) = match field.input {
        Qualified(side, name) =>
          (side == @schema.Left, @schema.Unqualified(name))
        _ => return Err(InvalidRows)
      }
      let column = match
        resolve(
          if on_left {
            left.field_names()
          } else {
            right.field_names()
          },
          source,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      columns.push((on_left, column))
    }
    let rows : Array[Array[Value]] = []
    for left_row in 0..<left_count {
      for right_row in 0..<right_count {
        if !spend_control(control, 1) ||
          !spend_control(control, width) ||
          !reserve_slots(workspace, 1 + width) {
          return Err(RowLimit)
        }
        retained += 1 + width
        let row = columns.map(pair => {
          if pair.0 {
            IndexedRows::read_cell(left, left_row, pair.1)
          } else {
            IndexedRows::read_cell(right, right_row, pair.1)
          }
        })
        if !retain_row(row, names, output) {
          return Err(RowLimit)
        }
        rows.push(row)
      }
    }
    Ok({ owner, id: @lower.cross_join_kernel_output(kernel), names, rows, })
  }
  let result = run()
  let keep = match result {
    Ok(_) => retained
    Err(_) => 0
  }
  release_slots(workspace, workspace.live - keep)
  result
}
