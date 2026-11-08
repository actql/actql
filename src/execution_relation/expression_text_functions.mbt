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
  TextByteLength
  TextUnicode
  TextChr
  TextReverse
  TextRepeat
  TextStrpos
  TextTranslate
  TextInstr
  TextReplace
  TextSplit
  TextSubstring
  TextLeft
  TextRight
  TextLPad
  TextRPad
  TextUpper
  TextLower
  TextNfkc
  TextCaseFold
  TextTrim
  TextLTrim
  TextRTrim
  TextContains
  TextUtf8Truncate
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
priv struct Utf8TruncationState {
  max_bytes : Int64
  mut input_bytes : Int64
}

///|
priv struct TextFunctionState {
  expression : @lower.Expression
  roots : Array[ExpressionRootLease?]
  kind : TextFunctionKind
  null_result : Bool
  chr_scalar : Char?
  repetitions : Int
  mut repetitions_remaining : Int
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
  instr_position : Double
  instr_occurrence : Double
  mut instr_phase : Int
  mut instr_remaining : Int
  mut translate_validated : Bool
  mut translate_outer : Int
  mut translate_inner : Int
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
  truncate : Utf8TruncationState?
  normalization : @canonical.NormalizationCursor?
  mut normalization_phase : Int
  mut normalization_input_bytes : Int64
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
      Text(_) if kind != TextChr &&
        (
          (
            !is_slice_text_function(kind) &&
            kind != TextRepeat &&
            kind != TextInstr &&
            kind != TextUtf8Truncate
          ) ||
          (kind == TextInstr && i < 2) ||
          i == 0 ||
          (is_pad_text_function(kind) && i == 2)
        ) => ()
      Number(_) if (kind == TextUtf8Truncate && i == 1) ||
        kind == TextChr ||
        (kind == TextInstr && i >= 2) ||
        (kind == TextSubstring && i > 0) ||
        ((is_slice_text_function(kind) || kind == TextRepeat) && i == 1) => ()
      _ => return Err({ kind: Scalar(InvalidOperand), expression, })
    }
  }
  fn text(value : Value) -> String {
    match value {
      Text(text) => text
      _ => ""
    }
  }
  let input = text(values[0])
  let repeat_count = if kind == TextRepeat && !null_result {
    // Count uses the existing finite integral Number domain. Validate before
    // any narrowing and before the empty-input shortcut, including negatives.
    guard values[1] is Number(number) &&
      @scalar.read_integer_number(number) is Some(count) &&
      count >= 0.0 else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    count
  } else {
    0.0
  }
  let chr_scalar = if kind == TextChr && !null_result {
    // Validate the complete Number before narrowing; no host conversion may
    // wrap a fraction, non-finite value, surrogate or out-of-range code point.
    guard values[0] is Number(number) &&
      @scalar.read_integer_number(number) is Some(point) &&
      point >= 0.0 &&
      point <= 1114111.0 &&
      !(point >= 55296.0 && point <= 57343.0) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    if point == 0.0 {
      None
    } else {
      Some(point.to_int().unsafe_to_char())
    }
  } else {
    None
  }
  let mut instr_position = 1.0
  let mut instr_occurrence = 1.0
  if kind == TextInstr && !null_result {
    if values.get(2) is Some(value) {
      guard value is Number(number) &&
        @scalar.read_integer_number(number) is Some(position) &&
        position != 0.0 else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      instr_position = position
    }
    if values.get(3) is Some(value) {
      guard value is Number(number) &&
        @scalar.read_integer_number(number) is Some(occurrence) &&
        occurrence > 0.0 else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      instr_occurrence = occurrence
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
  let is_normalization = kind == TextNfkc || kind == TextCaseFold
  let normalization_slots = if is_normalization && !null_result {
    // The pinned maximum fully decomposed expansion is 18 scalars. Reserve
    // every retained scalar and a constant-sized expansion before allocating.
    if input.length() > (workspace.limit - workspace.live - 20) / 18 {
      return Err({ kind: WorkspaceLimit, expression, })
    }
    input.length() * 18 + 18
  } else {
    0
  }
  let reserved = (if kind == TextUtf8Truncate { 6 } else { 2 }) +
    normalization_slots
  if is_normalization {
    guard @lower.expression_text_bound(expression) is Some(original) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    let operation = @text_bounds.output_operation(
      @lower.text_bound_output(original),
    )
    if !(if kind == TextNfkc {
        operation is @text_bounds.Nfkc
      } else {
        operation is @text_bounds.CaseFold
      }) {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
  }
  if !reserve_slots(workspace, reserved) {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  let truncate = if kind == TextUtf8Truncate {
    guard @lower.expression_text_bound(expression) is Some(original) &&
      @text_bounds.output_operation(@lower.text_bound_output(original))
      is @text_bounds.Utf8Truncate(_) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    let max_bytes = if null_result {
      0L
    } else {
      guard values[1] is Number(number) &&
        @scalar.read_safe_integer(number) is Some(limit) &&
        limit >= 0L else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      limit
    }
    Some({ max_bytes, input_bytes: 0L, })
  } else {
    None
  }
  let repetitions = if kind == TextRepeat &&
    !null_result &&
    !input.is_empty() &&
    repeat_count > 0.0 {
    // A nonempty repetition must fit the exact UTF-16 workspace and builder
    // representation. Divide integers first so float rounding cannot admit an
    // overflowing product. Only this resource-derived bound permits narrowing;
    // enormous valid counts for an empty String require no count-sized work.
    let maximum = (workspace.limit - workspace.live).min(1073741823) /
      input.length()
    if repeat_count > maximum.to_double() {
      return Err({ kind: WorkspaceLimit, expression, })
    }
    repeat_count.to_int()
  } else {
    0
  }
  let output_root = if kind != TextLength &&
    kind != TextByteLength &&
    kind != TextUnicode &&
    kind != TextStrpos &&
    kind != TextContains &&
    kind != TextInstr &&
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
    let root = match reserve_text_logical_bytes(budget, 2L) {
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
  Ok({
    expression,
    roots,
    kind,
    null_result,
    chr_scalar,
    repetitions,
    repetitions_remaining: repetitions,
    input,
    search: if is_pad_text_function(kind) {
      if values.get(2) is Some(pattern) {
        text(pattern)
      } else {
        " "
      }
    } else if kind == TextReplace ||
      kind == TextStrpos ||
      kind == TextContains ||
      kind == TextTranslate ||
      kind == TextInstr ||
      (is_trim_text_function(kind) && values.length() == 2) {
      text(values[1])
    } else {
      ""
    },
    replacement: if kind == TextReplace || kind == TextTranslate {
      text(values[2])
    } else {
      ""
    },
    output_root,
    reserved: if is_normalization {
      reserved
    } else if truncate is Some(_) {
      6
    } else if kind == TextReplace ||
      kind == TextTranslate ||
      kind == TextInstr ||
      kind == TextRepeat ||
      is_slice_text_function(kind) {
      values.length() * 3 + 3
    } else {
      2
    },
    position: if kind == TextReverse {
      input.length()
    } else {
      0
    },
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
    instr_position,
    instr_occurrence,
    instr_phase: 0,
    instr_remaining: 0,
    translate_validated: false,
    translate_outer: 0,
    translate_inner: 0,
    trim_explicit: is_trim_text_function(kind) && values.length() == 2,
    substring_phase: if truncate is Some(_) {
      4
    } else if is_slice_text_function(kind) {
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
    trim_start: if kind == TextRTrim || truncate is Some(_) {
      0
    } else {
      input.length()
    },
    truncate,
    normalization: if is_normalization && !null_result {
      Some(@canonical.start_normalization(input, kind == TextCaseFold))
    } else {
      None
    },
    normalization_phase: 0,
    normalization_input_bytes: 0L,
    trim_end: if kind == TextRTrim || kind == TextUtf8Truncate {
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
  let scalar = if unit >= 0xd800 && unit <= 0xdbff {
    if offset + 1 >= text.length() {
      return None
    }
    let trailing = text[offset + 1].to_int()
    if trailing < 0xdc00 || trailing > 0xdfff {
      return None
    }
    (0x10000 + ((unit - 0xd800) << 10) + trailing - 0xdc00).unsafe_to_char()
  } else if unit >= 0xdc00 && unit <= 0xdfff {
    return None
  } else {
    unit.unsafe_to_char()
  }
  let (units, width, wire) = text_function_scalar_widths(scalar)
  Some((scalar, offset + units, width, wire))
}

///|
/// Forward/reverse decoding and CHR share UTF-16, UTF-8 and JSON widths.
/// CHR's zero special case is handled before this scalar-only measurement.
fn text_function_scalar_widths(scalar : Char) -> (Int, Int, Int) {
  let point = scalar.to_int()
  let width = if point < 0x80 {
    1
  } else if point < 0x800 {
    2
  } else if point < 0x10000 {
    3
  } else {
    4
  }
  let wire = if point == 34 ||
    point == 92 ||
    point == 8 ||
    point == 9 ||
    point == 10 ||
    point == 12 ||
    point == 13 {
    2
  } else if point < 32 {
    6
  } else {
    width
  }
  (if point < 0x10000 { 1 } else { 2 }, width, wire)
}

///|
fn text_function_previous_scalar(
  text : String,
  end : Int,
) -> (Char, Int, Int, Int)? {
  if end <= 0 || end > text.length() {
    return None
  }
  let last = text[end - 1].to_int()
  let start = if last >= 0xdc00 && last <= 0xdfff { end - 2 } else { end - 1 }
  match text_function_scalar(text, start) {
    Some((scalar, next, width, wire)) if next == end =>
      Some((scalar, start, width, wire))
    _ => None
  }
}

///|
fn append_text_function_codepoint(
  state : TextFunctionState,
  scalar : Char,
  units : Int,
  width : Int,
  wire : Int,
) -> Result[Unit, EvalIssue] {
  let expression = state.expression
  if state.building {
    guard state.builder is Some(builder) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    builder.write_char(scalar)
  } else {
    if units > 1073741823 - state.units || wire > 2147483647 - state.bytes {
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
    state.units += units
    state.bytes += wire
    state.weight += width.to_int64()
  }
  Ok(())
}

///|
fn append_text_function_scalar(
  state : TextFunctionState,
  text : String,
  offset : Int,
) -> Result[Int, EvalIssue] {
  guard text_function_scalar(text, offset) is Some((scalar, next, width, wire)) else {
    return Err({ kind: Scalar(InvalidOperand), expression: state.expression, })
  }
  match
    append_text_function_codepoint(state, scalar, next - offset, width, wire) {
    Err(issue) => Err(issue)
    Ok(_) => Ok(next)
  }
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
  if state.normalization is Some(cursor) {
    return advance_normalization_function(state, cursor, workspace)
  }
  if state.substring_phase == 4 {
    // Validate the complete original input, including the suffix beyond the
    // selected prefix. A small result never hides an input-ceiling violation.
    guard state.truncate is Some(truncate) &&
      @lower.expression_text_bound(expression) is Some(original) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    if state.position == state.input.length() {
      state.substring_phase = 3
      state.position = 0
      return Ok(None)
    }
    guard text_function_scalar(state.input, state.position)
      is Some((_, next, width, _)) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    let (points, bytes) = @text_bounds.input_extent(
      @text_bounds.output_input(@lower.text_bound_output(original)),
    )
    if state.count.to_int64() >= points ||
      width.to_int64() > bytes - truncate.input_bytes {
      return Err({ kind: TextBounds(@text_bounds.InputCeiling), expression, })
    }
    truncate.input_bytes += width.to_int64()
    state.count += 1
    state.position = next
    if truncate.input_bytes <= truncate.max_bytes {
      state.trim_end = next
    }
    return Ok(None)
  }
  if state.kind == TextInstr {
    return advance_instr_function(state)
  }
  if state.kind == TextTranslate && !state.translate_validated {
    return advance_translate_validation(state)
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
  if state.kind == TextLength || state.kind == TextByteLength {
    if state.position == state.input.length() {
      return Ok(
        Some(
          Number(
            if state.kind == TextLength {
              state.count.to_double()
            } else {
              (state.weight - 1L).to_double()
            },
          ),
        ),
      )
    }
    guard text_function_scalar(state.input, state.position)
      is Some((_, next, width, _)) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    state.position = next
    state.count += 1
    // Int64 keeps the exact byte count even when UTF-8 exceeds the number of
    // admitted UTF-16 code units. Every increment remains one charged poll.
    state.weight += width.to_int64()
    return Ok(None)
  }
  if state.kind == TextUnicode {
    if state.input.is_empty() {
      return Ok(Some(Number(0.0)))
    }
    guard text_function_scalar(state.input, 0) is Some((scalar, _, _, _)) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    return Ok(Some(Number(scalar.to_int().to_double())))
  }
  if state.kind == TextChr &&
    state.position == 0 &&
    state.chr_scalar is Some(scalar) {
    let (units, width, wire) = text_function_scalar_widths(scalar)
    match append_text_function_codepoint(state, scalar, units, width, wire) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    state.position = 1
    return Ok(None)
  }
  if state.kind == TextStrpos || state.kind == TextContains {
    if state.search.length() == 0 {
      return Ok(
        Some(
          if state.kind == TextContains {
            Boolean(true)
          } else {
            Number(1.0)
          },
        ),
      )
    }
    if state.search.length() > state.input.length() - state.position {
      return Ok(
        Some(
          if state.kind == TextContains {
            Boolean(false)
          } else {
            Number(0.0)
          },
        ),
      )
    }
    // TextFunction pays one control unit before every poll. Repeated-prefix
    // candidates therefore cannot hide quadratic work in an uncharged scan.
    if state.input[state.position + state.matched] ==
      state.search[state.matched] {
      state.matched += 1
      if state.matched == state.search.length() {
        return Ok(
          Some(
            if state.kind == TextContains {
              Boolean(true)
            } else {
              Number((state.count + 1).to_double())
            },
          ),
        )
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
  if state.kind == TextRepeat &&
    state.position == state.input.length() &&
    state.repetitions_remaining > 1 {
    state.repetitions_remaining -= 1
    state.position = 0
    return Ok(None)
  }
  let end = if state.kind == TextReverse ||
    (state.kind == TextRepeat && state.repetitions == 0) {
    0
  } else if state.kind == TextUtf8Truncate ||
    is_trim_text_function(state.kind) ||
    is_slice_text_function(state.kind) {
    state.trim_end
  } else if state.kind == TextChr {
    if state.chr_scalar is Some(_) {
      1
    } else {
      0
    }
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
    if state.output_root is Some(root) && root.root.text_capacity is Some(_) {
      match
        reserve_measured_text_buffer(root, workspace, state.units, state.bytes) {
        Err(issue) => return Err({ kind: LogicalValue(issue), expression, })
        Ok(_) => ()
      }
      // Fixed Text frame/builder controls were already reserved on entry.
      // UTF-16 payload units are not structural container entries.
      state.allocated = 0
    } else {
      // Explicit finite/unmanaged callers retain their existing slot guard.
      if !reserve_slots(workspace, state.units) {
        return Err({ kind: WorkspaceLimit, expression, })
      }
      state.allocated = state.units
    }
    state.builder = Some(StringBuilder(size_hint=state.units * 2))
    state.building = true
    state.position = if state.kind == TextReverse {
      state.input.length()
    } else if state.kind == TextUtf8Truncate ||
      is_trim_text_function(state.kind) ||
      is_slice_text_function(state.kind) {
      state.trim_start
    } else {
      0
    }
    state.matched = 0
    state.repetitions_remaining = state.repetitions
    state.padding_remaining = state.padding
    state.padding_position = 0
    state.preceding_cased = false
    state.probing_sigma = false
    state.probe_position = 0
    return Ok(None)
  }
  if state.kind == TextTranslate {
    return advance_translate_scalar(state)
  }
  if state.kind == TextReverse {
    guard text_function_previous_scalar(state.input, state.position)
      is Some((scalar, previous, width, wire)) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    match
      append_text_function_codepoint(
        state,
        scalar,
        state.position - previous,
        width,
        wire,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    state.position = previous
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
  if state.kind == TextUtf8Truncate ||
    is_trim_text_function(state.kind) ||
    is_slice_text_function(state.kind) {
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
