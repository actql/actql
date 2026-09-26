///|
/// Copy only contributor handles, never reevaluate their source expressions.
/// The caller retains the input arrays; successful output transfers its slots.
priv struct AggregatePermutationExecution {
  values : Array[Value]
  order : Array[Int]
  control : ControlBudget
  workspace : RowWorkspace
  baseline : Int
  output : Array[Value]
  indices : Array[Int]
  mut admitted : Bool
  mut closed : Bool
}

///|
fn start_aggregate_permutation(
  values : Array[Value],
  order : Array[Int],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> AggregatePermutationExecution {
  {
    values,
    order,
    control,
    workspace,
    baseline: workspace.live,
    output: [],
    indices: [],
    admitted: false,
    closed: false,
  }
}

///|
fn close_aggregate_permutation(state : AggregatePermutationExecution) -> Unit {
  if state.closed {
    return
  }
  state.output.clear()
  state.indices.clear()
  release_slots(state.workspace, state.workspace.live - state.baseline)
  state.closed = true
}

///|
fn advance_aggregate_permutation(
  state : AggregatePermutationExecution,
) -> Result[(Array[Value], Array[Int])?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_aggregate_permutation_impl(state)
  if result is Err(_) {
    close_aggregate_permutation(state)
  }
  result
}

///|
fn advance_aggregate_permutation_impl(
  state : AggregatePermutationExecution,
) -> Result[(Array[Value], Array[Int])?, RowIssue] {
  let count = state.values.length()
  if !state.admitted {
    if state.order.length() != count {
      return Err(InvalidRows)
    }
    // Both arrays coexist. Reject dimensions before appending either array.
    guard checked_row_slots_add(count, count) is Some(slots) else {
      return Err(RowLimit)
    }
    if !reserve_slots(state.workspace, slots) {
      return Err(RowLimit)
    }
    state.admitted = true
    return Ok(None)
  }
  let index = state.output.length()
  if index == count {
    state.closed = true
    return Ok(Some((state.output, state.indices)))
  }
  let source = state.order[index]
  if source < 0 || source >= count {
    return Err(InvalidRows)
  }
  // Preserve the former local-index charge while bounding both appends.
  if !spend_control(state.control, 1) {
    return Err(RowLimit)
  }
  state.output.push(state.values[source])
  state.indices.push(index)
  Ok(None)
}
