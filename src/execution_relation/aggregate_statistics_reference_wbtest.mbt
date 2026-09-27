///|
/// Reference: the atomic form before the step state.
fn atomic_sort_aggregate_values(
  values : Array[Value],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Unit, RowIssue] {
  if !reserve_slots(workspace, values.length()) {
    return Err(RowLimit)
  }
  let mut issue : RowIssue? = None
  values.sort_by((left, right) => {
    if issue is Some(_) {
      return 0
    }
    match compare_complete_value(left, right, control) {
      Ok(comparison) => comparison
      Err(value) => {
        issue = Some(ordering_row_issue(value))
        0
      }
    }
  })
  release_slots(workspace, values.length())
  match issue {
    Some(issue) => Err(issue)
    None => Ok(())
  }
}

///|
/// Reference: the atomic form before the step state.
fn atomic_canonical_numeric_values(
  values : Array[Value],
  control : ControlBudget,
  workspace : RowWorkspace,
  identity_limits : ValueLimits,
) -> Result[Array[Double], RowIssue] {
  let entries : Array[(String, Double)] = []
  if !reserve_slots(workspace, values.length()) ||
    !reserve_slots(workspace, values.length()) {
    return Err(RowLimit)
  }
  for value in values {
    guard value is Number(number) && !number.is_nan() && !number.is_inf() else {
      return Err(InvalidRows)
    }
    let cid = match
      runtime_value_identity(value, control, workspace, identity_limits) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    entries.push((cid, number))
  }
  let mut failed = false
  entries.sort_by((left, right) => {
    if failed ||
      !spend_control_text(control, left.0) ||
      !spend_control_text(control, right.0) {
      failed = true
      0
    } else {
      @canonical.compare_utf16(left.0, right.0)
    }
  })
  if failed {
    return Err(RowLimit)
  }
  Ok(entries.map(entry => entry.1))
}
