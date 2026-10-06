///|
/// Discover one canonical group boundary at a time without copying input
/// rows. The completed range array remains owned by the enclosing group.
priv struct AggregateGroupRangeExecution[T] {
  input : T
  indices : Array[Int]
  order : Array[ColumnOrder]
  max_groups : Int
  control : ControlBudget
  workspace : RowWorkspace
  baseline : Int
  groups : Array[AggregateGroupRange]
  comparison : BoundedRowComparison
  mut position : Int
  mut start : Int
  mut phase : Int
  mut closed : Bool
}

///|
fn[T] start_aggregate_group_ranges(
  input : T,
  indices : Array[Int],
  order : Array[ColumnOrder],
  max_groups : Int,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> AggregateGroupRangeExecution[T] {
  {
    input,
    indices,
    order,
    max_groups,
    control,
    workspace,
    baseline: workspace.live,
    groups: [],
    comparison: {
      left: -1,
      right: -1,
      terms: 0,
      term: 0,
      phase: -1,
      offset: 0,
      charge: { offset: 0, next: 0, remaining: 0, },
      tree: None,
    },
    position: 1,
    start: 0,
    phase: 0,
    closed: false,
  }
}

///|
fn[T] close_aggregate_group_ranges(
  state : AggregateGroupRangeExecution[T],
) -> Unit {
  if state.closed {
    return
  }
  state.groups.clear()
  release_slots(state.workspace, state.workspace.live - state.baseline)
  state.closed = true
}

///|
fn[T : IndexedRows] advance_aggregate_group_ranges(
  state : AggregateGroupRangeExecution[T],
) -> Result[Array[AggregateGroupRange]?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_aggregate_group_ranges_impl(state)
  if result is Err(_) {
    close_aggregate_group_ranges(state)
  }
  result
}

///|
fn[T : IndexedRows] advance_aggregate_group_ranges_impl(
  state : AggregateGroupRangeExecution[T],
) -> Result[Array[AggregateGroupRange]?, RowIssue] {
  match state.phase {
    0 => {
      if state.max_groups < 0 {
        return Err(RowLimit)
      }
      if state.indices.is_empty() {
        if state.order.is_empty() {
          if state.max_groups == 0 ||
            !spend_control(state.control, 1) ||
            !reserve_slots(state.workspace, 1) {
            return Err(RowLimit)
          }
          state.groups.push({ representative: None, start: 0, end: 0, })
        }
        state.closed = true
        return Ok(Some(state.groups))
      }
      state.phase = 1
    }
    1 => {
      if state.position == state.indices.length() {
        state.phase = 2
        return Ok(None)
      }
      let compared = match
        bounded_row_comparison_step_with(
          state.comparison,
          state.order,
          state.control,
          (row, column) => Some(state.input.read_cell(row, column)),
          state.indices[state.position - 1],
          state.indices[state.position],
          state.order.length(),
        ) {
        Ok(None) => return Ok(None)
        Ok(Some(value)) => value
        Err(issue) => return Err(ordering_row_issue(issue))
      }
      if compared == 0 {
        state.position += 1
      } else {
        state.phase = 2
      }
    }
    2 => {
      if state.groups.length() == state.max_groups ||
        !spend_control(state.control, 1) ||
        !reserve_slots(state.workspace, 1) {
        return Err(RowLimit)
      }
      state.groups.push({
        representative: Some(state.indices[state.start]),
        start: state.start,
        end: state.position,
      })
      state.start = state.position
      if state.position == state.indices.length() {
        state.closed = true
        return Ok(Some(state.groups))
      }
      state.position += 1
      state.phase = 1
    }
    _ => return Err(InvalidRows)
  }
  Ok(None)
}
