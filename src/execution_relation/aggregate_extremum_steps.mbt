///|
/// Select a `min` or `max` contributor one comparison step at a time. Text
/// comparisons charge and compare one UTF-16 unit per advance with the same
/// complete-value charges and order as the draining fold.
priv struct AggregateExtremum {
  values : Array[Value]
  minimum : Bool
  control : ControlBudget
  comparison : BoundedCompleteValueComparison
  mut index : Int
  mut selected : Value
  mut closed : Bool
}

///|
fn start_aggregate_extremum(
  values : Array[Value],
  minimum : Bool,
  control : ControlBudget,
) -> AggregateExtremum {
  {
    values,
    minimum,
    control,
    comparison: { phase: -1, offset: 0, },
    index: 1,
    selected: if values.is_empty() {
      Null
    } else {
      values[0]
    },
    closed: false,
  }
}

///|
fn close_aggregate_extremum(state : AggregateExtremum) -> Unit {
  state.closed = true
}

///|
fn advance_aggregate_extremum(
  state : AggregateExtremum,
) -> Result[Value?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  if state.index >= state.values.length() {
    state.closed = true
    return Ok(Some(state.selected))
  }
  let comparison = match
    bounded_complete_value_comparison_step(
      state.comparison,
      state.values[state.index],
      state.selected,
      state.control,
    ) {
    Ok(None) => return Ok(None)
    Ok(Some(value)) => value
    Err(issue) => {
      close_aggregate_extremum(state)
      return Err(ordering_row_issue(issue))
    }
  }
  if (state.minimum && comparison < 0) || (!state.minimum && comparison > 0) {
    state.selected = state.values[state.index]
  }
  state.index += 1
  Ok(None)
}
