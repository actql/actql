///|
/// These are continuations of the existing expression frame, not another
/// evaluator. Operand roots survive both the sizing and construction passes.
priv struct TextArgumentsState {
  kind : TextFunctionKind
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
  TextSubstring
  TextLeft
  TextRight
  TextLPad
  TextRPad
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
fn is_slice_text_function(kind : TextFunctionKind) -> Bool {
  kind == TextSubstring ||
  kind == TextLeft ||
  kind == TextRight ||
  is_pad_text_function(kind)
}

///|
fn is_pad_text_function(kind : TextFunctionKind) -> Bool {
  kind == TextLPad || kind == TextRPad
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
  trim_explicit : Bool
  mut substring_phase : Int
  mut substring_start : Int64
  mut substring_end : Int64
  mut padding : Int64
  mut padding_remaining : Int64
  mut padding_position : Int
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
  for i, value in values {
    match value {
      Null => null_result = true
      Text(_) if !is_slice_text_function(kind) ||
        i == 0 ||
        (is_pad_text_function(kind) && i == 2) => ()
      Number(_) if (kind == TextSubstring && i > 0) ||
        (is_slice_text_function(kind) && i == 1) => ()
      _ => return Err({ kind: Scalar(InvalidOperand), expression, })
    }
  }
  let mut substring_start = 0L
  let mut substring_end = 9007199254740991L
  if kind == TextSubstring && !null_result {
    guard values[1] is Number(position) &&
      @scalar.read_safe_integer(position) is Some(start) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    substring_start = start
    if values.get(2) is Some(length) {
      guard length is Number(number) &&
        @scalar.read_safe_integer(number) is Some(length) &&
        length >= 0L else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      substring_end = length
    }
  }
  if is_slice_text_function(kind) && kind != TextSubstring && !null_result {
    guard values[1] is Number(number) &&
      @scalar.read_safe_integer(number) is Some(length) &&
      length >= 0L else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    substring_start = if kind == TextRight { -length } else { 1L }
    substring_end = length
    if is_pad_text_function(kind) && values.get(2) is Some(Text("")) {
      return Err({ kind: Scalar(InvalidOperand), expression, })
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
    search: if is_pad_text_function(kind) {
      if values.get(2) is Some(pattern) {
        text(pattern)
      } else {
        " "
      }
    } else if kind == TextReplace ||
      kind == TextStrpos ||
      (is_trim_text_function(kind) && values.length() == 2) {
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
    reserved: if kind == TextReplace || is_slice_text_function(kind) {
      values.length() * 3 + 3
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
    trim_explicit: is_trim_text_function(kind) && values.length() == 2,
    substring_phase: if is_slice_text_function(kind) {
      1
    } else {
      0
    },
    substring_start,
    substring_end,
    padding: 0L,
    padding_remaining: 0L,
    padding_position: 0,
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
  if state.substring_phase == 1 {
    if state.position == state.input.length() {
      let count = state.count.to_int64()
      if is_pad_text_function(state.kind) {
        state.padding = (state.substring_end - count).max(0L)
        state.padding_remaining = state.padding
      }
      let position = state.substring_start
      let start = if position > 0L {
        (position - 1L).min(count)
      } else if position == 0L || position < -count {
        0L
      } else {
        count + position
      }
      // Clamp before addition, keeping even the largest admitted indices exact.
      state.substring_start = start
      state.substring_end = start + state.substring_end.min(count - start)
      state.substring_phase = 2
      state.position = 0
      state.count = 0
      return Ok(None)
    }
    guard text_function_scalar(state.input, state.position)
      is Some((_, next, _, _)) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    state.position = next
    state.count += 1
    return Ok(None)
  }
  if state.substring_phase == 2 {
    if state.count.to_int64() == state.substring_start {
      state.trim_start = state.position
    }
    if state.count.to_int64() == state.substring_end {
      state.trim_end = state.position
      state.position = state.trim_start
      state.substring_phase = 3
      return Ok(None)
    }
    guard text_function_scalar(state.input, state.position)
      is Some((_, next, _, _)) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    state.position = next
    state.count += 1
    return Ok(None)
  }
  // Repeat only one pattern scalar per charged poll. Both the exact sizing
  // pass and construction pass use this cursor; no repeated string is ever
  // allocated before its logical bytes and workspace have been admitted.
  if state.padding_remaining > 0L &&
    (state.kind == TextLPad || state.position == state.trim_end) {
    state.padding_position = match
      append_text_function_scalar(state, state.search, state.padding_position) {
      Ok(next) => next
      Err(issue) => return Err(issue)
    }
    state.padding_remaining -= 1L
    if state.padding_position == state.search.length() {
      state.padding_position = 0
    }
    return Ok(None)
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
    // Explicit sets are Unicode scalar membership, not substring matching.
    // Compare at most one set scalar per charged poll. Reuse the retained
    // search cursor, so even repeated/large sets need no unbounded allocation.
    let removable = if state.trim_explicit {
      if state.matched == state.search.length() {
        false
      } else {
        guard text_function_scalar(state.search, state.matched)
          is Some((candidate, set_next, _, _)) else {
          return Err({ kind: Scalar(InvalidOperand), expression, })
        }
        state.matched = set_next
        if candidate != scalar {
          return Ok(None)
        }
        true
      }
    } else {
      trim_white_space(scalar)
    }
    state.matched = 0
    // The opposite boundary stays at the original edge for a one-sided trim.
    // A full cooperative scan validates every scalar without allocating a copy.
    if !removable {
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
  let end = if is_trim_text_function(state.kind) ||
    is_slice_text_function(state.kind) {
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
    state.position = if is_trim_text_function(state.kind) ||
      is_slice_text_function(state.kind) {
      state.trim_start
    } else {
      0
    }
    state.matched = 0
    state.padding_remaining = state.padding
    state.padding_position = 0
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
  if is_trim_text_function(state.kind) || is_slice_text_function(state.kind) {
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
