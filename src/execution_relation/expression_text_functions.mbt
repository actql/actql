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
priv enum TextFunctionKind {
  TextLength
  TextStrpos
  TextReplace
  TextUpper
  TextLower
  TextTrim
  TextLTrim
  TextRTrim
} derive(Eq)

///|
fn is_trim_text_function(kind : TextFunctionKind) -> Bool {
  kind == TextTrim || kind == TextLTrim || kind == TextRTrim
}

///|
priv struct TextFunctionState {
  expression : @lower.Expression
  roots : Array[ExpressionRootLease?]
  kind : TextFunctionKind
  null_result : Bool
  input : String
  search : String
  mut replacement : String
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
  mut preceding_cased : Bool
  mut probing_sigma : Bool
  mut probe_position : Int
  mut trim_scanning : Bool
  mut trim_start : Int
  mut trim_end : Int
}

///|
fn start_text_function(
  expression : @lower.Expression,
  values : Array[Value],
  roots : Array[ExpressionRootLease?],
  kind : TextFunctionKind,
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
  let output_root = if kind != TextLength &&
    kind != TextStrpos &&
    !null_result &&
    scope is Some(scope) {
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
  let input = text(values[0])
  Ok({
    expression,
    roots,
    kind,
    null_result,
    input,
    search: if kind == TextReplace || kind == TextStrpos {
      text(values[1])
    } else {
      ""
    },
    replacement: if kind == TextReplace {
      text(values[2])
    } else {
      ""
    },
    output_root,
    reserved: if kind == TextReplace {
      12
    } else {
      2
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
    preceding_cased: false,
    probing_sigma: false,
    probe_position: 0,
    trim_scanning: is_trim_text_function(kind),
    trim_start: if kind == TextRTrim {
      0
    } else {
      input.length()
    },
    trim_end: if kind == TextRTrim {
      0
    } else {
      input.length()
    },
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
/// One comparison code unit or one scanned/emitted scalar per poll. No substring,
/// whole-string search, normalization, output measurement or replay occurs.
fn advance_text_function(
  state : TextFunctionState,
  workspace : RowWorkspace,
) -> Result[Value?, EvalIssue] {
  let expression = state.expression
  if state.null_result {
    return Ok(Some(Null))
  }
  if state.trim_scanning {
    if state.position == state.input.length() {
      state.trim_scanning = false
      state.position = state.trim_start
      return Ok(None)
    }
    guard text_function_scalar(state.input, state.position)
      is Some((scalar, next, _, _)) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    // The opposite boundary stays at the original edge for a one-sided trim.
    // A full cooperative scan validates every scalar without allocating a copy.
    if !trim_white_space(scalar) {
      if state.kind != TextRTrim && state.trim_start == state.input.length() {
        state.trim_start = state.position
      }
      if state.kind != TextLTrim {
        state.trim_end = next
      }
    }
    state.position = next
    return Ok(None)
  }
  if state.kind == TextLength {
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
  if state.kind == TextStrpos {
    if state.search.length() == 0 {
      return Ok(Some(Number(1.0)))
    }
    if state.search.length() > state.input.length() - state.position {
      return Ok(Some(Number(0.0)))
    }
    // TextFunction pays one control unit before every poll. Repeated-prefix
    // candidates therefore cannot hide quadratic work in an uncharged scan.
    if state.input[state.position + state.matched] ==
      state.search[state.matched] {
      state.matched += 1
      if state.matched == state.search.length() {
        return Ok(Some(Number((state.count + 1).to_double())))
      }
      return Ok(None)
    }
    state.matched = 0
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
  if state.probing_sigma {
    // Unicode 16 Final_Sigma uses possessive Case_Ignorable skipping.
    // Probe only the original input; a witness never changes left context.
    let following_cased = if state.probe_position == state.input.length() {
      false
    } else {
      guard text_function_scalar(state.input, state.probe_position)
        is Some((scalar, next, _, _)) else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      if @scalar.unicode_is_case_ignorable(scalar) {
        state.probe_position = next
        return Ok(None)
      }
      @scalar.unicode_is_cased(scalar)
    }
    state.replacement = if following_cased { "σ" } else { "ς" }
    state.probing_sigma = false
    state.emitting = true
    state.emission = 0
    return Ok(None)
  }
  let end = if is_trim_text_function(state.kind) {
    state.trim_end
  } else {
    state.input.length()
  }
  if state.position == end {
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
    state.position = if is_trim_text_function(state.kind) {
      state.trim_start
    } else {
      0
    }
    state.matched = 0
    state.preceding_cased = false
    state.probing_sigma = false
    state.probe_position = 0
    return Ok(None)
  }
  if state.kind == TextUpper || state.kind == TextLower {
    guard text_function_scalar(state.input, state.position)
      is Some((scalar, next, _, _)) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    if state.kind == TextLower {
      let final_sigma_candidate = scalar == 'Σ' && state.preceding_cased
      if !@scalar.unicode_is_case_ignorable(scalar) {
        state.preceding_cased = @scalar.unicode_is_cased(scalar)
      }
      if final_sigma_candidate {
        // Sigma itself is not case-ignorable. Probes therefore cover
        // disjoint ignorable runs, at most one extra scan per input scalar
        // per pass. Each probe advances under the frame's control budget.
        state.position = next
        state.probe_position = next
        state.probing_sigma = true
        return Ok(None)
      }
    }
    let mapped = if state.kind == TextUpper {
      @scalar.unicode_upper_mapping(scalar)
    } else {
      @scalar.unicode_lower_mapping(scalar)
    }
    if mapped is Some(mapped) {
      // Borrow the fixed mapping. Each expanded scalar is sized/emitted by
      // the existing continuation, never by an unbounded host casing call.
      state.position = next
      state.replacement = mapped
      state.emitting = true
      state.emission = 0
      return Ok(None)
    }
    state.position = match
      append_text_function_scalar(state, state.input, state.position) {
      Ok(next) => next
      Err(issue) => return Err(issue)
    }
    return Ok(None)
  }
  if is_trim_text_function(state.kind) {
    state.position = match
      append_text_function_scalar(state, state.input, state.position) {
      Ok(next) => next
      Err(issue) => return Err(issue)
    }
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

///|
/// Unicode 16.0 PropList White_Space, independent of host-language trim rules.
/// U+0085 belongs to this set; U+FEFF and U+200B do not.
fn trim_white_space(scalar : Char) -> Bool {
  let code = scalar.to_int()
  (code >= 0x0009 && code <= 0x000d) ||
  code == 0x0020 ||
  code == 0x0085 ||
  code == 0x00a0 ||
  code == 0x1680 ||
  (code >= 0x2000 && code <= 0x200a) ||
  code == 0x2028 ||
  code == 0x2029 ||
  code == 0x202f ||
  code == 0x205f ||
  code == 0x3000
}
