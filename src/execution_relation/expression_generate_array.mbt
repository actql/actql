///|
priv struct GenerateArrayArguments {
  expression : @lower.Expression
  children : Array[@lower.Expression]
  values : Array[Value]
  roots : Array[ExpressionRootLease?]
  mut index : Int
}

///|
priv struct GenerateArrayState {
  expression : @lower.Expression
  roots : Array[ExpressionRootLease?]
  root : ExpressionRootLease?
  start : Int64
  step : Int64
  count : Int
  mut current : Int64
  mut index : Int
  mut bytes : Int
  mut builder : @admitted.ArrayBuilder?
}

///|
fn start_generate_array(
  frame : ExpressionFrame,
  args : GenerateArrayArguments,
) -> Result[GenerateArrayState?, EvalIssue] {
  let expression = args.expression
  if args.values.any(value => value is Null) {
    return Ok(None)
  }
  let step = match args.values.get(2) {
    None => 1L
    Some(Captured(@admitted.Signed64(step))) => step
    Some(_) => return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  guard args.values[0] is Captured(@admitted.Signed64(start)) &&
    args.values[1] is Captured(@admitted.Signed64(end)) &&
    step != 0L else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  guard @admitted.signed64_progression_count(start, end, step) is Some(count) &&
    reserve_slots(frame.workspace, 2) else {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  let root = if frame.scope is Some(scope) {
    let budget = scope.budget
    if budget.host_nodes <= count ||
      budget.host_depth < (if count == 0 { 1 } else { 2 }) ||
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
    let root = match register_scope_root(scope, root) {
      Ok(root) => root
      Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
    }
    match charge_logical_work(budget, count.to_int64() + 1L) {
      Ok(_) => ()
      Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
    }
    Some(root)
  } else {
    None
  }
  Ok(
    Some({
      expression,
      roots: args.roots,
      root,
      start,
      step,
      count,
      current: start,
      index: 0,
      bytes: 2,
      builder: None,
    }),
  )
}

///|
// The int64 wire value is a quoted decimal. Count its sign and digits without
// building a temporary String or taking the absolute value of MIN_INT64.
fn signed64_wire_bytes(value : Int64) -> Int {
  let mut tail = value
  let mut bytes = if value < 0L { 4 } else { 3 }
  while tail >= 10L || tail <= -10L {
    tail = tail / 10L
    bytes += 1
  }
  bytes
}

///|
fn advance_generate_array(
  frame : ExpressionFrame,
  state : GenerateArrayState,
) -> Result[Value?, EvalIssue] {
  let expression = state.expression
  if state.builder is Some(builder) {
    if state.index == state.count {
      guard @admitted.finish_array_value(builder) is Some(array) else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      frame.arrays.pop() |> ignore
      state.builder = None
      if state.root is Some(root) {
        root.root.measurement = Some({
          wire_bytes: state.bytes,
          weight: state.count.to_int64() + 1L,
        })
      }
      return Ok(Some(Captured(array)))
    }
    if !@admitted.append_array_item(
        builder,
        @admitted.signed64_value(state.current),
      ) {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
  } else if state.index == state.count {
    // Both passes have a charged transition per element. Admit the complete
    // exact backing before allocating its first slot.
    guard reserve_slots(frame.workspace, state.count) &&
      @admitted.prepare_array_value(state.count) is Some(builder) else {
      return Err({ kind: WorkspaceLimit, expression, })
    }
    frame.arrays.push(builder)
    state.builder = Some(builder)
    state.current = state.start
    state.index = 0
    return Ok(None)
  } else if state.root is Some(root) {
    let bytes = signed64_wire_bytes(state.current) +
      (if state.index == 0 { 0 } else { 1 })
    match grow_object_root(root, bytes.to_int64()) {
      // Growth has already checked the inherited Int-sized host byte bound.
      Ok(_) => state.bytes += bytes
      Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
    }
  }
  state.index += 1
  // Cardinality was computed from the full unsigned distance. Every next
  // element is inside the admitted endpoints and the last is never advanced.
  if state.index < state.count {
    state.current += state.step
  }
  Ok(None)
}
