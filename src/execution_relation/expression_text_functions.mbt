///|
/// These are continuations of the existing expression frame, not another
/// evaluator. Operand roots survive both the sizing and construction passes.
priv struct TextArgumentsState {
  expression : @lower.Expression
  children : Array[@lower.Expression]
  values : Array[Value]
  roots : Array[ExpressionRootLease?]
  mut index : Int
}

///|
priv struct TextFunctionState {
  expression : @lower.Expression
  roots : Array[ExpressionRootLease?]
  length_only : Bool
  null_result : Bool
  input : String
  search : String
  replacement : String
  output_root : ExpressionRootLease?
  reserved : Int
  mut position : Int
  mut matched : Int
  mut emitting : Bool
  mut emission : Int
  mut building : Bool
  mut count : Int
  mut units : Int
  mut allocated : Int
  mut bytes : Int
  mut weight : Int64
  mut builder : StringBuilder?
}

///|
fn start_text_function(
  expression : @lower.Expression,
  values : Array[Value],
  roots : Array[ExpressionRootLease?],
  length_only : Bool,
  scope : ExpressionRoots?,
  workspace : RowWorkspace,
) -> Result[TextFunctionState, EvalIssue] {
  let mut null_result = false
  for value in values {
    match value {
      Null => null_result = true
      Text(_) => ()
      _ => return Err({ kind: Scalar(InvalidOperand), expression, })
    }
  }
  if !reserve_slots(workspace, 2) {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  let output_root = if !length_only && !null_result && scope is Some(scope) {
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
    let root = match register_scope_root(scope, root) {
      Ok(root) => root
      Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
    }
    match charge_logical_work(budget, 1L) {
      Err(_) =>
        return Err({
          kind: LogicalValue(ValueMeasure(LogicalWorkLimit)),
          expression,
        })
      Ok(_) => ()
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
    roots,
    length_only,
    null_result,
    input: text(values[0]),
    search: if length_only {
      ""
    } else {
      text(values[1])
    },
    replacement: if length_only {
      ""
    } else {
      text(values[2])
    },
    output_root,
    reserved: if length_only {
      2
    } else {
      12
    },
    position: 0,
    matched: 0,
    emitting: false,
    emission: 0,
    building: false,
    count: 0,
    units: 0,
    allocated: 0,
    bytes: 2,
    weight: 1L,
    builder: None,
  })
}

///|
/// Constant-time scalar decoding and canonical JSON width. Values retain their
/// original scalar sequence, including decomposed Unicode and CR/LF.
fn text_function_scalar(text : String, offset : Int) -> (Char, Int, Int, Int)? {
  if offset < 0 || offset >= text.length() {
    return None
  }
  let unit = text[offset].to_int()
  if unit >= 0xd800 && unit <= 0xdbff {
    if offset + 1 >= text.length() {
      return None
    }
    let trailing = text[offset + 1].to_int()
    if trailing < 0xdc00 || trailing > 0xdfff {
      return None
    }
    let scalar = 0x10000 + ((unit - 0xd800) << 10) + trailing - 0xdc00
    return Some((scalar.unsafe_to_char(), offset + 2, 4, 4))
  }
  if unit >= 0xdc00 && unit <= 0xdfff {
    return None
  }
  let width = if unit < 0x80 { 1 } else if unit < 0x800 { 2 } else { 3 }
  let wire = if unit == 34 ||
    unit == 92 ||
    unit == 8 ||
    unit == 9 ||
    unit == 10 ||
    unit == 12 ||
    unit == 13 {
    2
  } else if unit < 32 {
    6
  } else {
    width
  }
  Some((unit.unsafe_to_char(), offset + 1, width, wire))
}

///|
fn append_text_function_scalar(
  state : TextFunctionState,
  text : String,
  offset : Int,
) -> Result[Int, EvalIssue] {
  let expression = state.expression
  guard text_function_scalar(text, offset) is Some((scalar, next, width, wire)) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  if state.building {
    guard state.builder is Some(builder) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    builder.write_char(scalar)
  } else {
    if next - offset > 1073741823 - state.units ||
      wire > 2147483647 - state.bytes {
      return Err({ kind: WorkspaceLimit, expression, })
    }
    if state.output_root is Some(root) {
      match grow_object_root(root, wire.to_int64()) {
        Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
        Ok(_) => ()
      }
      match charge_logical_work(root.scope.budget, width.to_int64()) {
        Err(_) =>
          return Err({
            kind: LogicalValue(ValueMeasure(LogicalWorkLimit)),
            expression,
          })
        Ok(_) => ()
      }
    }
    state.units += next - offset
    state.bytes += wire
    state.weight += width.to_int64()
  }
  Ok(next)
}

///|
/// One comparison code unit or one emitted scalar per poll. No substring,
/// whole-string search, normalization, output measurement or replay occurs.
fn advance_text_function(
  state : TextFunctionState,
  workspace : RowWorkspace,
) -> Result[Value?, EvalIssue] {
  let expression = state.expression
  if state.null_result {
    return Ok(Some(Null))
  }
  if state.length_only {
    if state.position == state.input.length() {
      return Ok(Some(Number(state.count.to_double())))
    }
    guard text_function_scalar(state.input, state.position)
      is Some((_, next, _, _)) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    state.position = next
    state.count += 1
    return Ok(None)
  }
  if state.emitting {
    if state.emission == state.replacement.length() {
      state.emitting = false
      return Ok(None)
    }
    state.emission = match
      append_text_function_scalar(state, state.replacement, state.emission) {
      Ok(next) => next
      Err(issue) => return Err(issue)
    }
    return Ok(None)
  }
  if state.position == state.input.length() {
    if state.building {
      guard state.builder is Some(builder) else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      // Exact native capacity makes finalization an ownership transfer, not a
      // second full copy. JS uses the pinned builder's retained String.
      let result = builder.to_string()
      state.builder = None
      if state.output_root is Some(root) {
        root.root.measurement = Some({
          wire_bytes: state.bytes,
          weight: state.weight,
        })
      }
      return Ok(Some(Text(result)))
    }
    // All output bytes were admitted before allocating the exact UTF-16
    // buffer. Reservation belongs to this frame through the final result.
    if !reserve_slots(workspace, state.units) {
      return Err({ kind: WorkspaceLimit, expression, })
    }
    state.allocated = state.units
    state.builder = Some(StringBuilder(size_hint=state.units * 2))
    state.building = true
    state.position = 0
    state.matched = 0
    return Ok(None)
  }
  if !state.search.is_empty() &&
    state.search.length() <= state.input.length() - state.position {
    if state.input[state.position + state.matched] ==
      state.search[state.matched] {
      state.matched += 1
      if state.matched == state.search.length() {
        state.position += state.search.length()
        state.matched = 0
        state.emitting = true
        state.emission = 0
      }
      return Ok(None)
    }
  }
  state.matched = 0
  state.position = match
    append_text_function_scalar(state, state.input, state.position) {
    Ok(next) => next
    Err(issue) => return Err(issue)
  }
  Ok(None)
}
