///|
priv enum ChargedLogicalMeasureIssue {
  Workspace
  Logical(LogicalBudgetIssue)
}

///|
/// Row and expression owners borrow the same bounded measurement cursor. The
/// fixed eight slots cover its handles, pending Text state, measuring writer,
/// and overlapping wire handles; the initial traversal frame adds one slot.
fn start_charged_logical_measure(
  value : Value,
  budget : LogicalBudget,
  workspace : RowWorkspace,
  nodes : Int,
  depth : Int,
) -> Result[LogicalMeasureCursor, ChargedLogicalMeasureIssue] {
  if budget.failed {
    return Err(Logical(FailedLogicalBudget))
  }
  if !reserve_slots(workspace, 9) {
    return Err(Workspace)
  }
  let allowance = budget.limits.max_work - budget.work
  match
    start_logical_measure(
      value,
      allowance,
      Int64::min(budget.limits.max_value_bytes, budget.host_bytes.to_int64()).to_int(),
      nodes,
      depth,
    ) {
    Err(issue) => {
      release_slots(workspace, 9)
      budget.failed = true
      Err(Logical(ValueMeasure(issue)))
    }
    Ok(cursor) => {
      budget.work += allowance - cursor.remaining
      Ok(cursor)
    }
  }
}

///|
/// Return the new reservation only on success. Failure releases the speculative
/// successor slot; the caller retains and closes its original custody. Every
/// consumed logical unit remains charged, including a failing transition.
fn advance_charged_logical_measure(
  cursor : LogicalMeasureCursor,
  budget : LogicalBudget,
  workspace : RowWorkspace,
  reserved : Int,
) -> Result[(LogicalValueMeasure?, Int), ChargedLogicalMeasureIssue] {
  if budget.failed {
    return Err(Logical(FailedLogicalBudget))
  }
  // One transition replaces a frame with at most two. Reserve the successor
  // before the existing cursor can allocate it.
  if !reserve_slots(workspace, 1) {
    return Err(Workspace)
  }
  let before = cursor.remaining
  let result = advance_logical_measure(cursor)
  budget.work += before - cursor.remaining
  match result {
    Err(issue) => {
      release_slots(workspace, 1)
      budget.failed = true
      Err(Logical(ValueMeasure(issue)))
    }
    Ok(measured) => {
      let retained = if measured is Some(_) {
        0
      } else {
        8 + logical_measure_frames(cursor)
      }
      release_slots(workspace, reserved + 1 - retained)
      Ok((measured, retained))
    }
  }
}
