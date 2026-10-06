///|
priv struct ObjectNameState {
  object : ObjectExpressionState
  value : Value
  value_bytes : Int64
  mut wire_bytes : Int
  mut offset : Int
  mut phase : Int
}

///|
/// Preserve wire/live refusal before name-control refusal. Neither sizing nor
/// charging publishes the field; both borrowed child and builder roots remain
/// in the existing frame until the append or its confirmed cleanup.
fn advance_object_name(
  frame : ExpressionFrame,
  state : ObjectNameState,
) -> Result[Unit, EvalIssue] {
  let object = state.object
  let expression = object.expression
  let name = object.fields[object.index].0
  if state.phase == 0 {
    if object.root is Some(root) {
      let budget = root.scope.budget
      if state.offset < name.length() {
        guard text_function_scalar(name, state.offset)
          is Some((_, next, _, wire)) &&
          wire <= budget.host_bytes - state.wire_bytes else {
          return Err({
            kind: LogicalValue(ValueMeasure(WireMeasureFailure)),
            expression,
          })
        }
        state.wire_bytes += wire
        state.offset = next
        return Ok(())
      }
      let delta = state.wire_bytes.to_int64() +
        1L +
        state.value_bytes +
        (if object.index == 0 { 0L } else { 1L })
      match grow_object_root(root, delta) {
        Ok(_) => ()
        Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
      }
    }
    if !reserve_slots(frame.workspace, 3) {
      return Err({ kind: WorkspaceLimit, expression, })
    }
    state.phase = 1
    state.offset = 0
    return Ok(())
  }
  if state.phase == 1 {
    if state.offset < name.length() {
      guard text_function_scalar(name, state.offset)
        is Some((_, next, width, _)) &&
        spend_control(frame.budget, width) else {
        return Err({ kind: ControlLimit, expression, })
      }
      state.offset = next
      return Ok(())
    }
    state.phase = 2
    return Ok(())
  }
  release_slots(frame.workspace, 2)
  append_expression_object_field(frame, object, state.value)
}

///|
fn append_expression_object_field(
  frame : ExpressionFrame,
  state : ObjectExpressionState,
  value : Value,
) -> Result[Unit, EvalIssue] {
  let expression = state.expression
  if value is Text(text) && text.length() > 64 {
    let admission = match start_raw_text_admission(text, frame.workspace) {
      Ok(admission) => admission
      Err(_) => return Err({ kind: WorkspaceLimit, expression, })
    }
    frame.state = ObjectText(state, admission)
    return Ok(())
  }
  let admitted = match admitted_aggregate_item(value, frame.budget) {
    Ok(Some(value)) => value
    Ok(None) => @admitted.null_value()
    Err(_) => return Err({ kind: ControlLimit, expression, })
  }
  append_admitted_expression_object_field(frame, state, admitted)
}

///|
fn append_admitted_expression_object_field(
  frame : ExpressionFrame,
  state : ObjectExpressionState,
  admitted : @admitted.Value,
) -> Result[Unit, EvalIssue] {
  let expression = state.expression
  if !@admitted.append_contract_object_field(
      state.builder,
      state.index,
      admitted,
    ) {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  state.roots.push(frame.current_root)
  frame.current_root = None
  state.index += 1
  if state.fields.get(state.index) is Some((_, child)) {
    frame.stack.push(Object(state))
    frame.state = Enter(child)
  } else {
    state.index = 0
    frame.state = FinishObject(state)
  }
  Ok(())
}
