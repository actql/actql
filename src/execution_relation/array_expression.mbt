///|
/// A constructor uses the ordinary expression schedule and root owner. Its
/// private builder seals its backing; it never publishes a partial array.
fn start_expression_array(
  frame : ExpressionFrame,
  expression : @lower.Expression,
  children : Array[@lower.Expression],
) -> Result[ArrayExpressionState, EvalIssue] {
  let root = if frame.scope is Some(scope) {
    let budget = scope.budget
    if budget.host_nodes < 1 ||
      budget.host_depth < 1 ||
      budget.host_bytes < 2 ||
      budget.limits.max_value_bytes < 2L {
      return Err({
        kind: LogicalValue(ValueMeasure(HostMeasureLimit)),
        expression,
      })
    }
    let root = match reserve_logical_bytes(budget, 2L) {
      Ok(root) => root
      Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
    }
    match register_scope_root(scope, root) {
      Ok(root) => Some(root)
      Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
    }
  } else {
    None
  }
  guard reserve_slots(frame.workspace, 1) &&
    @admitted.prepare_array_value(children.length()) is Some(builder) else {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  frame.arrays.push(builder)
  frame.object_context += 1
  Ok({ expression, children, builder, roots: [], root, index: 0, })
}

///|
fn append_expression_array_item(
  frame : ExpressionFrame,
  state : ArrayExpressionState,
  value : Value,
) -> Result[Unit, EvalIssue] {
  let expression = state.expression
  if state.root is Some(root) {
    let measured = match
      consume_expression_value(root.scope.budget, value, frame.current_root) {
      Ok(measured) => measured
      Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
    }
    let delta = measured.wire_bytes.to_int64() +
      (if state.index == 0 { 0L } else { 1L })
    match grow_object_root(root, delta) {
      Ok(_) => ()
      Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
    }
  }
  // Reserve the element and its retained root before either append. Child
  // views, the continuation and builder are already reserved on Enter.
  if !reserve_slots(frame.workspace, 2) {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  if value is Text(text) && text.length() > 64 {
    let admission = match start_raw_text_admission(text, frame.workspace) {
      Ok(admission) => admission
      Err(_) => return Err({ kind: WorkspaceLimit, expression, })
    }
    frame.state = ArrayText(state, admission)
    return Ok(())
  }
  let admitted = match admitted_aggregate_item(value, frame.budget) {
    Ok(Some(value)) => value
    Ok(None) => @admitted.null_value()
    Err(_) => return Err({ kind: ControlLimit, expression, })
  }
  append_admitted_expression_array_item(frame, state, admitted)
}

///|
fn append_admitted_expression_array_item(
  frame : ExpressionFrame,
  state : ArrayExpressionState,
  value : @admitted.Value,
) -> Result[Unit, EvalIssue] {
  let expression = state.expression
  if !@admitted.append_array_item(state.builder, value) {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  state.roots.push(frame.current_root)
  frame.current_root = None
  state.index += 1
  if state.children.get(state.index) is Some(child) {
    frame.stack.push(Array(state))
    frame.state = Enter(child)
  } else {
    state.index = 0
    frame.state = FinishArray(state)
  }
  Ok(())
}

///|
fn finish_expression_array(
  frame : ExpressionFrame,
  state : ArrayExpressionState,
) -> Result[Unit, EvalIssue] {
  let expression = state.expression
  if state.roots.get(state.index) is Some(root) {
    match expression_event_release(root, expression) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    state.index += 1
    release_slots(frame.workspace, 1)
    return Ok(())
  }
  guard @admitted.finish_array_value(state.builder) is Some(array) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  frame.arrays.pop() |> ignore
  frame.object_context -= 1
  release_slots(frame.workspace, state.children.length() * 2 + 2)
  let value = Captured(array)
  if state.root is Some(root) {
    let budget = root.scope.budget
    if !reserve_slots(frame.workspace, 9) {
      return Err({ kind: WorkspaceLimit, expression, })
    }
    frame.measurement_slots = 9
    let cursor = match
      start_logical_measure(
        value,
        budget.limits.max_work - budget.work,
        Int64::min(budget.limits.max_value_bytes, budget.host_bytes.to_int64()).to_int(),
        budget.host_nodes,
        budget.host_depth,
      ) {
      Ok(cursor) => cursor
      Err(issue) =>
        return Err({ kind: LogicalValue(ValueMeasure(issue)), expression, })
    }
    frame.state = MeasureArray(state, value, cursor)
  } else {
    frame.state = Return(value)
  }
  Ok(())
}
