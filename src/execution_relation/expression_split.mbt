///|
/// Dynamic parts use the existing expression root and admitted Array builder.
/// The first pass admits the whole output before any part storage is allocated;
/// the second repeats the bounded search without retaining a boundary array.
priv struct SplitFunctionState {
  expression : @lower.Expression
  roots : Array[ExpressionRootLease?]
  input : String
  delimiter : String
  null_result : Bool
  root : ExpressionRootLease?
  reserved : Int
  mut allocated : Int
  mut position : Int
  mut matched : Int
  mut part_start : Int
  mut part_end : Int
  mut emission : Int
  mut scan_done : Bool
  mut building : Bool
  mut count : Int
  mut units : Int
  mut bytes : Int
  mut weight : Int64
  mut array : @admitted.ArrayBuilder?
  mut text_builder : StringBuilder?
  mut admission : RawTextAdmission?
}

///|
fn start_split_function(
  frame : ExpressionFrame,
  args : TextArgumentsState,
) -> Result[SplitFunctionState, EvalIssue] {
  let expression = args.expression
  let mut null_result = false
  for value in args.values {
    match value {
      Null => null_result = true
      Text(_) => ()
      _ => return Err({ kind: Scalar(InvalidOperand), expression, })
    }
  }
  // State, current String builder, Array builder and retained builder owner.
  if !reserve_slots(frame.workspace, 4) {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  let root = if !null_result && frame.scope is Some(scope) {
    let budget = scope.budget
    // Every non-NULL split has at least one String element, including empty
    // input. Node/depth admission precedes both builders and their storage.
    if budget.host_nodes < 2 ||
      budget.host_depth < 2 ||
      budget.host_bytes < 4 ||
      budget.limits.max_value_bytes < 4L {
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
    match charge_logical_work(budget, 1L) {
      Ok(_) => ()
      Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
    }
    Some(root)
  } else {
    None
  }
  fn text(value : Value) -> String {
    match value {
      Text(text) => text
      _ => ""
    }
  }
  Ok({
    expression,
    roots: args.roots,
    input: text(args.values[0]),
    delimiter: if args.values.get(1) is Some(value) {
      text(value)
    } else {
      ","
    },
    null_result,
    root,
    reserved: args.values.length() * 3 + 5,
    allocated: 0,
    position: 0,
    matched: 0,
    part_start: 0,
    part_end: 0,
    emission: 0,
    scan_done: false,
    building: false,
    count: 0,
    units: 0,
    bytes: 2,
    weight: 1L,
    array: None,
    text_builder: None,
    admission: None,
  })
}

///|
fn size_split_output(
  state : SplitFunctionState,
  bytes : Int,
  weight : Int,
  units : Int,
) -> Result[Unit, EvalIssue] {
  let expression = state.expression
  if bytes > 2147483647 - state.bytes || units > 1073741823 - state.units {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  if state.root is Some(root) {
    match grow_object_root(root, bytes.to_int64()) {
      Ok(_) => ()
      Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
    }
    match charge_logical_work(root.scope.budget, weight.to_int64()) {
      Ok(_) => ()
      Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
    }
  }
  state.bytes += bytes
  state.weight += weight.to_int64()
  state.units += units
  Ok(())
}

///|
fn split_part_boundary(
  state : SplitFunctionState,
  end : Int,
  next : Int,
  final_part : Bool,
) -> Result[Unit, EvalIssue] {
  let expression = state.expression
  if state.building {
    // The sizing pass has already admitted all UTF-16 units and array slots.
    // Exact capacity preserves the pinned builder's transfer-only finish.
    state.text_builder = Some(
      StringBuilder(size_hint=(end - state.part_start) * 2),
    )
    state.emission = state.part_start
    state.part_end = end
  } else {
    if state.count == 2147483646 {
      return Err({ kind: WorkspaceLimit, expression, })
    }
    if state.root is Some(root) &&
      state.count >= root.scope.budget.host_nodes - 1 {
      return Err({
        kind: LogicalValue(ValueMeasure(HostMeasureLimit)),
        expression,
      })
    }
    match size_split_output(state, if state.count == 0 { 2 } else { 3 }, 1, 0) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    state.count += 1
  }
  state.position = next
  state.part_start = next
  state.matched = 0
  state.scan_done = final_part
  Ok(())
}

///|
/// One delimiter code-unit comparison, scalar sizing/emission, or existing
/// admission step per charged poll. Repeated prefixes never hide an uncharged
/// whole-string search. Delimiters match literally and never overlap.
fn advance_split_function(
  frame : ExpressionFrame,
  state : SplitFunctionState,
) -> Result[Value?, EvalIssue] {
  let expression = state.expression
  if state.null_result {
    return Ok(Some(Null))
  }
  if state.admission is Some(admission) {
    match advance_raw_text_admission(admission, frame.budget) {
      Err(_) => return Err({ kind: ControlLimit, expression, })
      Ok(None) => return Ok(None)
      Ok(Some(value)) => {
        guard state.array is Some(array) &&
          @admitted.append_array_item(array, value) else {
          return Err({ kind: Scalar(InvalidOperand), expression, })
        }
        state.admission = None
        return Ok(None)
      }
    }
  }
  if state.text_builder is Some(builder) {
    if state.emission == state.part_end {
      let text = builder.to_string()
      state.text_builder = None
      state.admission = Some(
        match start_raw_text_admission(text, frame.workspace) {
          Ok(admission) => admission
          Err(_) => return Err({ kind: WorkspaceLimit, expression, })
        },
      )
      return Ok(None)
    }
    guard text_function_scalar(state.input, state.emission)
      is Some((scalar, next, _, _)) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    builder.write_char(scalar)
    state.emission = next
    return Ok(None)
  }
  if state.scan_done {
    if state.building {
      guard state.array is Some(array) &&
        @admitted.finish_array_value(array) is Some(value) else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      frame.arrays.pop() |> ignore
      state.array = None
      if state.root is Some(root) {
        root.root.measurement = Some({
          wire_bytes: state.bytes,
          weight: state.weight,
        })
      }
      return Ok(Some(Captured(value)))
    }
    guard checked_row_slots_add(state.units, state.count) is Some(allocated) &&
      reserve_slots(frame.workspace, allocated) else {
      return Err({ kind: WorkspaceLimit, expression, })
    }
    state.allocated = allocated
    guard @admitted.prepare_array_value(state.count) is Some(array) else {
      return Err({ kind: WorkspaceLimit, expression, })
    }
    frame.arrays.push(array)
    state.array = Some(array)
    state.building = true
    state.scan_done = false
    state.position = 0
    state.part_start = 0
    state.matched = 0
    return Ok(None)
  }
  if state.position == state.input.length() {
    // For an empty delimiter, a nonempty input finishes on its final scalar.
    // Empty input still reaches this branch and produces one empty String.
    match split_part_boundary(state, state.position, state.position, true) {
      Ok(_) => return Ok(None)
      Err(issue) => return Err(issue)
    }
  }
  if !state.delimiter.is_empty() &&
    state.delimiter.length() <= state.input.length() - state.position {
    if state.input[state.position + state.matched] ==
      state.delimiter[state.matched] {
      state.matched += 1
      if state.matched == state.delimiter.length() {
        match
          split_part_boundary(
            state,
            state.position,
            state.position + state.matched,
            false,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      }
      return Ok(None)
    }
  }
  state.matched = 0
  guard text_function_scalar(state.input, state.position)
    is Some((_, next, width, wire)) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  if !state.building {
    match size_split_output(state, wire, width, next - state.position) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  if state.delimiter.is_empty() {
    match split_part_boundary(state, next, next, next == state.input.length()) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  } else {
    state.position = next
  }
  Ok(None)
}
