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
/// Preserve the distinction between exhausted resources and invalid semantic
/// input at every ordering call site.
fn ordering_row_issue(issue : OrderingIssue) -> RowIssue {
  match issue {
    InvalidInput => InvalidRows
    Limit => RowLimit
    Scalar(issue) => Comparison(issue)
  }
}

///|
fn[T : IndexedRows] compare_row_indices(
  table : T,
  a : Int,
  b : Int,
  order : Array[ColumnOrder],
  control : ControlBudget,
) -> Result[Int, OrderingIssue] {
  compare_row_indices_prefix(table, a, b, order, order.length(), control)
}

///|
/// Compare only the canonical partition prefix of a resolved sort order.
fn[T : IndexedRows] compare_row_indices_prefix(
  table : T,
  a : Int,
  b : Int,
  order : Array[ColumnOrder],
  terms : Int,
  control : ControlBudget,
) -> Result[Int, OrderingIssue] {
  if terms < 0 || terms > order.length() {
    return Err(InvalidInput)
  }
  for index in 0..<terms {
    let term = order[index]
    if !spend_control(control, 1) {
      return Err(Limit)
    }
    let left = table.read_cell(a, term.column)
    let right = table.read_cell(b, term.column)
    match charge_comparison_pair(control, left, right) {
      Ok(_) => ()
      Err(ComparisonChargeLimit) => return Err(Limit)
      Err(ComparisonChargeInvalidOperand) => return Err(Scalar(InvalidOperand))
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
  let state = start_stable_order(table, order, control, workspace)
  while true {
    match advance_stable_order(state) {
      Ok(None) => ()
      Ok(Some(indices)) => return Ok(indices)
      Err(issue) => return Err(issue)
    }
  } nobreak {
    close_stable_order(state)
    Err(InvalidInput)
  }
}
