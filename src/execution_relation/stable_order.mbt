///|
/// Resolved physical column coordinates, never an authored or wire order IR.
priv struct ColumnOrder {
  column : Int
  descending : Bool
  nulls_first : Bool
}

///|
priv enum OrderingIssue {
  InvalidInput
  Limit
  Scalar(ScalarIssue)
}

///|
fn[T : IndexedRows] compare_row_indices(
  table : T,
  a : Int,
  b : Int,
  order : Array[ColumnOrder],
  control : ControlBudget,
) -> Result[Int, OrderingIssue] {
  for term in order {
    if !spend_control(control, 1) {
      return Err(Limit)
    }
    let left = table.read_cell(a, term.column)
    let right = table.read_cell(b, term.column)
    if !charge_comparison_operand(control, left) ||
      !charge_comparison_operand(control, right) {
      return Err(Limit)
    }
    let comparison = match (left, right) {
      (Null, Null) => 0
      (Null, _) => if term.nulls_first { -1 } else { 1 }
      (_, Null) => if term.nulls_first { 1 } else { -1 }
      _ => {
        let c = match compare(left, right) {
          Ok(c) => c
          Err(e) => return Err(Scalar(e))
        }
        if term.descending {
          -c
        } else {
          c
        }
      }
    }
    if comparison != 0 {
      return Ok(comparison)
    }
  }
  // The caller's complete resolved terms are authoritative. No hidden CID key.
  Ok(0)
}

///|
/// Stable bottom-up merge of row indices. Input rows are never copied/mutated.
/// Returned indices remain charged to workspace; caller owns that lifetime.
/// On failure only this call's workspace is released; work never rolls back.
fn[T : IndexedRows] stable_order_indices(
  table : T,
  order : Array[ColumnOrder],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Array[Int], OrderingIssue] {
  if control.remaining < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit {
    return Err(InvalidInput)
  }
  let baseline = workspace.live
  let count = table.row_count()
  let run = fn() -> Result[Array[Int], OrderingIssue] {
    if !reserve_slots(workspace, order.length()) {
      return Err(Limit)
    }
    for term in order {
      if !spend_control(control, 1) {
        return Err(Limit)
      }
      if term.column < 0 || term.column >= table.column_count() {
        return Err(InvalidInput)
      }
    }
    for row = 0; row < count; row = row + 1 {
      if !spend_control(control, 1) {
        return Err(Limit)
      }
      if table.row_width(row) != table.column_count() {
        return Err(InvalidInput)
      }
    }
    if !reserve_slots(workspace, count) || !spend_control(control, count) {
      return Err(Limit)
    }
    let mut source = Array::makei(count, i => i)
    if count < 2 || order.is_empty() {
      return Ok(source)
    }
    if !reserve_slots(workspace, count) || !spend_control(control, count) {
      return Err(Limit)
    }
    let mut target = Array::make(count, 0)
    let mut width = 1
    while width < count {
      let mut start = 0
      while start < count {
        let middle = start + Int::min(width, count - start)
        let end = middle + Int::min(width, count - middle)
        let mut left = start
        let mut right = middle
        for out = start; out < end; out = out + 1 {
          if !spend_control(control, 1) {
            return Err(Limit)
          }
          let choose_left = if left == middle {
            false
          } else if right == end {
            true
          } else {
            match
              compare_row_indices(
                table,
                source[left],
                source[right],
                order,
                control,
              ) {
              Ok(c) => c <= 0
              Err(e) => return Err(e)
            }
          }
          if choose_left {
            target[out] = source[left]
            left += 1
          } else {
            target[out] = source[right]
            right += 1
          }
        }
        start = end
      }
      let previous = source
      source = target
      target = previous
      if width > count / 2 {
        break
      }
      width *= 2
    }
    Ok(source)
  }
  let result = run()
  let retained = match result {
    Ok(_) => count
    Err(_) => 0
  }
  release_slots(workspace, workspace.live - baseline - retained)
  result
}
