///|
priv struct ArrayConcatArguments {
  expression : @lower.Expression
  children : Array[@lower.Expression]
  operands : Array[@admitted.FrozenArray[@admitted.Value]?]
  roots : Array[ExpressionRootLease?]
  mut count : Int64
  mut bytes : Int64
  mut has_null : Bool
}

///|
priv struct ArrayConcatState {
  args : ArrayConcatArguments
  builder : @admitted.ArrayBuilder?
  root : ExpressionRootLease?
  mut array_index : Int
  mut item_index : Int
}

///|
fn push_array_concat_operand(
  frame : ExpressionFrame,
  args : ArrayConcatArguments,
  value : Value,
) -> Result[Unit, EvalIssue] {
  let expression = args.expression
  let measured = if frame.scope is Some(scope) {
    match consume_expression_value(scope.budget, value, frame.current_root) {
      Ok(measured) => Some(measured)
      Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
    }
  } else {
    None
  }
  match value {
    Null => {
      args.has_null = true
      args.operands.push(None)
    }
    Captured(@admitted.Array(items)) => {
      let count = @admitted.element_count(items)
      if count > 0 && measured is Some(measure) {
        // Reuse the original array's exact canonical wire measurement.
        // Drop its brackets, then add a separator between nonempty arrays.
        args.bytes += measure.wire_bytes.to_int64() -
          2L +
          (if args.count > 0L { 1L } else { 0L })
      }
      args.count += count.to_int64()
      args.operands.push(Some(items))
    }
    _ => return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  args.roots.push(frame.current_root)
  frame.current_root = None
  if args.children.get(args.operands.length()) is Some(child) {
    frame.stack.push(ArrayConcatArguments(args))
    frame.state = Enter(child)
    return Ok(())
  }
  if args.has_null {
    frame.state = ArrayConcat({
      args,
      builder: None,
      root: None,
      array_index: 0,
      item_index: 0,
    })
    return Ok(())
  }
  // No output backing exists before all original operands have succeeded.
  // Count and wire extent are sums of Int-sized counts, accumulated in Int64.
  if args.count >= (frame.workspace.limit - frame.workspace.live).to_int64() ||
    !reserve_slots(frame.workspace, args.count.to_int() + 1) {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  let root = if frame.scope is Some(scope) {
    let budget = scope.budget
    if args.count >= budget.host_nodes.to_int64() ||
      budget.host_depth < (if args.count == 0L { 1 } else { 2 }) ||
      args.bytes > budget.host_bytes.to_int64() ||
      args.bytes > budget.limits.max_value_bytes ||
      (
        budget.all_expression_roots &&
        budget.root_result_bytes is Some(ceiling) &&
        args.bytes > ceiling
      ) {
      return Err({
        kind: LogicalValue(ValueMeasure(HostMeasureLimit)),
        expression,
      })
    }
    match reserve_logical_bytes(budget, args.bytes) {
      Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
      Ok(root) =>
        match register_scope_root(scope, root) {
          Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
          Ok(root) => Some(root)
        }
    }
  } else {
    None
  }
  guard @admitted.prepare_array_value(args.count.to_int()) is Some(builder) else {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  frame.arrays.push(builder)
  frame.state = ArrayConcat({
    args,
    builder: Some(builder),
    root,
    array_index: 0,
    item_index: 0,
  })
  Ok(())
}

///|
fn advance_array_concat(
  frame : ExpressionFrame,
  state : ArrayConcatState,
) -> Result[Unit, EvalIssue] {
  let args = state.args
  let expression = args.expression
  if state.array_index < args.operands.length() {
    if state.builder is Some(builder) &&
      args.operands[state.array_index] is Some(items) &&
      @admitted.element_at(items, state.item_index) is Some(item) {
      if !@admitted.append_array_item(builder, item) {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      state.item_index += 1
      return Ok(())
    }
    args.operands[state.array_index] = None
    match expression_event_release(args.roots[state.array_index], expression) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    args.roots[state.array_index] = None
    state.array_index += 1
    state.item_index = 0
    return Ok(())
  }
  release_slots(frame.workspace, args.children.length() * 3 + 1)
  if state.builder is Some(builder) {
    guard @admitted.finish_array_value(builder) is Some(value) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    frame.arrays.pop() |> ignore
    release_slots(frame.workspace, args.count.to_int() + 1)
    return measure_assembled_array(
      frame,
      expression,
      Captured(value),
      state.root,
    )
  }
  frame.state = Return(Null)
  Ok(())
}
