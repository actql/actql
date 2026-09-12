///|
/// Private physical duplicate detection. Sorting is only an index: survivors
/// are emitted in original input order. Column coordinates come from checked
/// preparation, never from name resolution here. Structural payload is ignored
/// unless explicitly included in the comparison columns.
/// Returned indices own their workspace slots. Failure releases only this call's
/// workspace, never rolls back work, and never publishes partial survivors.
fn[T : IndexedRows] distinct_indices(
  table : T,
  columns : Array[Int],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Array[Int], OrderingIssue] {
  if control.remaining < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit {
    return Err(InvalidInput)
  }
  let baseline = workspace.live
  let run = fn() -> Result[Array[Int], OrderingIssue] {
    if !reserve_slots(workspace, columns.length()) ||
      !spend_control(control, columns.length()) {
      return Err(Limit)
    }
    let order = columns.map(column => {
      column,
      descending: false,
      nulls_first: false,
    })
    let sorted = match stable_order_indices(table, order, control, workspace) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    let count = table.row_count()
    if !reserve_slots(workspace, count) || !spend_control(control, count) {
      return Err(Limit)
    }
    let keep = Array::make(count, false)
    for i = 0; i < count; i = i + 1 {
      if !spend_control(control, 1) {
        return Err(Limit)
      }
      let first = if i == 0 {
        true
      } else {
        match
          compare_row_indices(table, sorted[i - 1], sorted[i], order, control) {
          Ok(c) => c != 0
          Err(e) => return Err(e)
        }
      }
      // Stable index ordering makes the first group member the first input row.
      if first {
        keep[sorted[i]] = true
      }
    }
    let result : Array[Int] = []
    for i = 0; i < count; i = i + 1 {
      if !spend_control(control, 1) {
        return Err(Limit)
      }
      if keep[i] {
        if !reserve_slots(workspace, 1) || !spend_control(control, 1) {
          return Err(Limit)
        }
        result.push(i)
      }
    }
    Ok(result)
  }
  let result = run()
  let retained = match result {
    Ok(indices) => indices.length()
    Err(_) => 0
  }
  release_slots(workspace, workspace.live - baseline - retained)
  result
}
