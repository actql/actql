///|
/// Collection preserves authored member order and filter-before-argument
/// demand. Successful arrays transfer to the enclosing aggregate workspace.
priv struct AggregateContributorExecution[T] {
  input : T
  names : Array[String]
  indices : Array[Int]
  end : Int
  argument : AggregateInput
  filter : @lower.Expression?
  aggregate : Int
  control : ControlBudget
  workspace : RowWorkspace
  scope : ExpressionRoots?
  baseline : Int
  sources : Array[Int]
  values : Array[Value]
  mut position : Int
  mut row_open : Bool
  mut filter_done : Bool
  mut expression : AggregateExpressionExecution[T]?
  mut closed : Bool
}

///|
fn[T] start_aggregate_contributors(
  input : T,
  names : Array[String],
  indices : Array[Int],
  range : AggregateGroupRange,
  argument : AggregateInput,
  filter : @lower.Expression?,
  aggregate : Int,
  control : ControlBudget,
  workspace : RowWorkspace,
  scope : ExpressionRoots?,
) -> AggregateContributorExecution[T] {
  {
    input,
    names,
    indices,
    end: range.end,
    argument,
    filter,
    aggregate,
    control,
    workspace,
    scope,
    baseline: workspace.live,
    sources: [],
    values: [],
    position: range.start,
    row_open: false,
    filter_done: false,
    expression: None,
    closed: false,
  }
}

///|
fn[T] close_aggregate_contributors(
  state : AggregateContributorExecution[T],
) -> Unit {
  if state.closed {
    return
  }
  if state.expression is Some(expression) {
    close_aggregate_expression(expression)
  }
  state.expression = None
  state.sources.clear()
  state.values.clear()
  release_slots(state.workspace, state.workspace.live - state.baseline)
  state.closed = true
}

///|
fn[T : IndexedRows] advance_aggregate_contributors(
  state : AggregateContributorExecution[T],
) -> Result[(Array[Int], Array[Value])?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_aggregate_contributors_impl(state)
  if result is Err(_) {
    close_aggregate_contributors(state)
  }
  result
}

///|
fn[T : IndexedRows] advance_aggregate_contributors_impl(
  state : AggregateContributorExecution[T],
) -> Result[(Array[Int], Array[Value])?, RowIssue] {
  if state.position == state.end {
    state.closed = true
    return Ok(Some((state.sources, state.values)))
  }
  let source = state.indices[state.position]
  if !state.row_open {
    if !spend_control(state.control, 1) {
      return Err(RowLimit)
    }
    state.row_open = true
    state.filter_done = state.filter is None
    return Ok(None)
  }
  if !state.filter_done {
    guard state.filter is Some(filter) else { return Err(InvalidRows) }
    if state.expression is None {
      state.expression = Some(
        start_aggregate_expression(
          filter,
          state.input,
          state.names,
          source,
          state.aggregate,
          state.control,
          state.workspace,
          state.scope,
        ),
      )
    }
    let accepted = match
      advance_aggregate_expression(state.expression.unwrap()) {
      Err(issue) => return Err(issue)
      Ok(None) => return Ok(None)
      Ok(Some(Boolean(true))) => true
      Ok(Some(Boolean(false) | Null)) => false
      Ok(Some(_)) => return Err(InvalidRows)
    }
    state.expression = None
    if accepted {
      state.filter_done = true
    } else {
      state.position += 1
      state.row_open = false
    }
    return Ok(None)
  }
  let value = match state.argument {
    AggregateInputRows => Null
    AggregateInputField(column) =>
      IndexedRows::read_cell(state.input, source, column)
    AggregateInputExpression(expression) => {
      if state.expression is None {
        state.expression = Some(
          start_aggregate_expression(
            expression,
            state.input,
            state.names,
            source,
            state.aggregate,
            state.control,
            state.workspace,
            state.scope,
          ),
        )
      }
      match advance_aggregate_expression(state.expression.unwrap()) {
        Err(issue) => return Err(issue)
        Ok(None) => return Ok(None)
        Ok(Some(value)) => value
      }
    }
  }
  state.expression = None
  if !reserve_slots(state.workspace, 2) {
    return Err(RowLimit)
  }
  state.sources.push(source)
  state.values.push(value)
  state.position += 1
  state.row_open = false
  Ok(None)
}
