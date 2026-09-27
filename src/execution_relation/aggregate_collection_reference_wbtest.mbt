///|
/// Reference: identity hashing charged in one step, as before.
fn runtime_value_identity(
  value : Value,
  control : ControlBudget,
  workspace : RowWorkspace,
  limits : ValueLimits,
) -> Result[String, RowIssue] {
  match runtime_value_identity_usage(value, control, workspace, limits) {
    Ok((cid, bytes)) =>
      if !spend_control(control, bytes) {
        Err(RowLimit)
      } else {
        Ok(cid)
      }
    Err(issue) => Err(issue)
  }
}

///|
/// Reference: the atomic form before the step state.
fn atomic_distinct_aggregate_values(
  values : Array[Value],
  control : ControlBudget,
  workspace : RowWorkspace,
  identity_limits : ValueLimits,
) -> Result[Array[Value], RowIssue] {
  let buckets : Map[String, Array[Value]] = Map([])
  let output : Array[Value] = []
  for value in values {
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    let cid = match
      runtime_value_identity(value, control, workspace, identity_limits) {
      Ok(cid) => cid
      Err(issue) => return Err(issue)
    }
    let bucket = match buckets.get(cid) {
      Some(bucket) => bucket
      None => {
        if !reserve_slots(workspace, 1) || !spend_control_text(control, cid) {
          return Err(RowLimit)
        }
        let bucket : Array[Value] = []
        buckets[cid] = bucket
        bucket
      }
    }
    let mut duplicate = false
    for previous in bucket {
      let comparison = match compare_complete_value(previous, value, control) {
        Ok(comparison) => comparison
        Err(issue) => return Err(ordering_row_issue(issue))
      }
      if comparison == 0 {
        duplicate = true
        break
      }
    }
    if !duplicate {
      if !reserve_slots(workspace, 2) {
        return Err(RowLimit)
      }
      bucket.push(value)
      output.push(value)
    }
  }
  Ok(output)
}

///|
/// Reference: the atomic form before the step state.
fn[T : IndexedRows] atomic_ordered_aggregate_values(
  input : T,
  indices : Array[Int],
  range : AggregateGroupRange,
  column : Int,
  order : Array[ColumnOrder],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Array[Value], RowIssue] {
  let members : AggregateRangeRows[T] = {
    input,
    indices,
    start: range.start,
    end: range.end,
  }
  let ordered = match stable_order_indices(members, order, control, workspace) {
    Ok(ordered) => ordered
    Err(issue) => return Err(ordering_row_issue(issue))
  }
  let values : Array[Value] = []
  for position in ordered {
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    let value = IndexedRows::read_cell(members, position, column)
    if !(value is Null) {
      if !reserve_slots(workspace, 1) {
        return Err(RowLimit)
      }
      values.push(value)
    }
  }
  Ok(values)
}
