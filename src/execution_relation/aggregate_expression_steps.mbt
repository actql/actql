///|
/// The caller owns group/source scheduling. This state owns only one source
/// snapshot and the temporary roots of one filter or argument evaluation.
priv struct AggregateExpressionExecution[T] {
  expression : @lower.Expression
  input : T
  names : Array[String]
  row : Int
  aggregate : Int
  control : ControlBudget
  workspace : RowWorkspace
  scope : ExpressionRoots?
  baseline : Int
  snapshot : Map[String, Value]
  mut column : Int
  mut column_entry_charged : Bool
  name_charge : BoundedTextCharge
  mut frame : ExpressionFrame?
  mut closed : Bool
}

///|
fn[T] start_aggregate_expression(
  expression : @lower.Expression,
  input : T,
  names : Array[String],
  row : Int,
  aggregate : Int,
  control : ControlBudget,
  workspace : RowWorkspace,
  scope : ExpressionRoots?,
) -> AggregateExpressionExecution[T] {
  {
    expression,
    input,
    names,
    row,
    aggregate,
    control,
    workspace,
    scope,
    baseline: workspace.live,
    snapshot: Map([]),
    column: 0,
    column_entry_charged: false,
    name_charge: { offset: 0, next: 0, remaining: 0, },
    frame: None,
    closed: false,
  }
}

///|
/// Cancellation releases this evaluation's scratch, never its borrowed row.
fn[T] close_aggregate_expression(
  state : AggregateExpressionExecution[T],
) -> Unit {
  if state.closed {
    return
  }
  if state.frame is Some(frame) && !frame.closed {
    close_expression_frame(frame)
  }
  state.frame = None
  state.snapshot.clear()
  release_slots(state.workspace, state.workspace.live - state.baseline)
  state.closed = true
}

///|
/// One call copies one field or advances one existing semantic expression
/// frame. No group or frame-member loop is hidden in this operation.
fn[T : IndexedRows] advance_aggregate_expression(
  state : AggregateExpressionExecution[T],
) -> Result[Value?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_aggregate_expression_impl(state)
  match result {
    Err(_) | Ok(Some(_)) => close_aggregate_expression(state)
    Ok(None) => ()
  }
  result
}

///|
fn[T : IndexedRows] advance_aggregate_expression_impl(
  state : AggregateExpressionExecution[T],
) -> Result[Value?, RowIssue] {
  if state.column < state.names.length() {
    let name = state.names[state.column]
    if !state.column_entry_charged {
      if !spend_control(state.control, 1) {
        return Err(RowLimit)
      }
      state.column_entry_charged = true
      return Ok(None)
    }
    match advance_bounded_text_charge(state.name_charge, state.control, name) {
      Err(_) => return Err(RowLimit)
      Ok(false) => return Ok(None)
      Ok(true) => ()
    }
    if !reserve_slots(state.workspace, 1) {
      return Err(RowLimit)
    }
    state.snapshot[name] = IndexedRows::read_cell(
      state.input,
      state.row,
      state.column,
    )
    state.column += 1
    state.column_entry_charged = false
    reset_bounded_text_charge(state.name_charge)
    return Ok(None)
  }
  guard state.scope is Some(scope) else {
    return Err(MissingOrderedResourceContext)
  }
  if state.frame is None {
    match charge_logical_work(scope.budget, 1L) {
      Err(issue) => return Err(LogicalRows(issue))
      Ok(_) => ()
    }
    state.frame = match
      expression_frame(
        state.expression,
        state.snapshot,
        [],
        state.control,
        state.workspace,
        Some(expression_roots(scope.budget, state.control.max_frames)),
      ) {
      Ok(frame) => Some(frame)
      Err(issue) => {
        scope.budget.failed = true
        return Err(evaluation_row_issue(state.row, state.aggregate, issue))
      }
    }
    return Ok(None)
  }
  let evaluated = match advance_expression_frame(state.frame.unwrap()) {
    Ok(None) => return Ok(None)
    Ok(Some(value)) => Ok(value)
    Err(issue) => Err(issue)
  }
  match
    release_expression_result(
      state.expression,
      check_expression_result(state.expression, evaluated, Some(scope.budget)),
    ) {
    Ok(value) => Ok(Some(value))
    Err(issue) => Err(evaluation_row_issue(state.row, state.aggregate, issue))
  }
}
