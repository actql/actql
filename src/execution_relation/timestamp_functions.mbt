///|
/// Progress in the original expression's checked pattern, never a reparsed
/// pattern or an alternate clock/timezone parser. Its fixed array and controls
/// are reserved by start_text_function before construction.
priv struct TimestampFunctionState {
  pattern : @timestamp.Pattern
  parts : FixedArray[Int]
  mut phase : Int
  mut component : Int
  mut digit : Int
  mut offset : Int
  mut input_bytes : Int64
}

///|
fn timestamp_token_index(token : String) -> Int {
  match token {
    "yyyy" => 0
    "MM" => 1
    "dd" => 2
    "HH" => 3
    "mm" => 4
    "ss" => 5
    "SSS" => 6
    _ => -1
  }
}

///|
fn timestamp_token_offset(token : String) -> Int {
  match token {
    "yyyy" => 0
    "MM" => 5
    "dd" => 8
    "HH" => 11
    "mm" => 14
    "ss" => 17
    "SSS" => 20
    _ => -1
  }
}

///|
fn timestamp_canonical_character(
  parts : FixedArray[Int],
  position : Int,
) -> Char {
  let (part, digit, width) = match position {
    0..=3 => (0, position, 4)
    5..=6 => (1, position - 5, 2)
    8..=9 => (2, position - 8, 2)
    11..=12 => (3, position - 11, 2)
    14..=15 => (4, position - 14, 2)
    17..=18 => (5, position - 17, 2)
    20..=22 => (6, position - 20, 3)
    _ => return "0000-00-00T00:00:00.000Z"[position].to_int().unsafe_to_char()
  }
  let mut divisor = 1
  for _ in 0..<(width - digit - 1) {
    divisor *= 10
  }
  "0123456789"[parts[part] / divisor % 10].to_int().unsafe_to_char()
}

///|
fn timestamp_pattern_character(
  state : TextFunctionState,
  timestamp : TimestampFunctionState,
) -> Char? {
  guard @timestamp.component_at(timestamp.pattern, timestamp.component)
    is Some(component) else {
    return None
  }
  match component {
    @timestamp.Literal(text) =>
      Some(text[timestamp.digit].to_int().unsafe_to_char())
    @timestamp.Token(token) => {
      let offset = timestamp_token_offset(token)
      if offset < 0 || offset + timestamp.digit >= state.input.length() {
        None
      } else {
        Some(state.input[offset + timestamp.digit].to_int().unsafe_to_char())
      }
    }
  }
}

///|
fn advance_timestamp_pattern_position(
  timestamp : TimestampFunctionState,
) -> Unit {
  match @timestamp.component_at(timestamp.pattern, timestamp.component) {
    Some(@timestamp.Token(token)) | Some(@timestamp.Literal(token)) => {
      timestamp.digit += 1
      if timestamp.digit == token.length() {
        timestamp.digit = 0
        timestamp.component += 1
      }
    }
    None => ()
  }
}

///|
/// One input scalar, pattern unit or emitted output unit per poll. The caller
/// retains operand roots and applies its existing current/work/cancel fences.
fn advance_timestamp_function(
  state : TextFunctionState,
  timestamp : TimestampFunctionState,
  workspace : RowWorkspace,
) -> Result[Value?, EvalIssue] {
  let expression = state.expression
  guard @lower.expression_text_bound(expression) is Some(original) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  let output = @lower.text_bound_output(original)
  if timestamp.phase == 0 {
    if state.position < state.input.length() {
      guard text_function_scalar(state.input, state.position)
        is Some((_, next, width, _)) else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      let (points, bytes) = @text_bounds.input_extent(
        @text_bounds.output_input(output),
      )
      if state.count.to_int64() >= points ||
        width.to_int64() > bytes - timestamp.input_bytes {
        return Err({ kind: TextBounds(@text_bounds.InputCeiling), expression, })
      }
      timestamp.input_bytes += width.to_int64()
      state.count += 1
      state.position = next
      return Ok(None)
    }
    state.position = 0
    if state.kind == TextFormatTimestamp {
      if state.input.length() < 24 ||
        @admitted.timestamp_instant(state.input) is None {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      timestamp.phase = 2
    } else {
      timestamp.phase = 1
    }
    return Ok(None)
  }
  if timestamp.phase == 1 {
    match @timestamp.component_at(timestamp.pattern, timestamp.component) {
      None => {
        if timestamp.offset != state.input.length() {
          return Err({ kind: Scalar(InvalidOperand), expression, })
        }
        timestamp.phase = 2
        timestamp.component = 0
        timestamp.digit = 0
        return Ok(None)
      }
      Some(component) => {
        if timestamp.offset >= state.input.length() {
          return Err({ kind: Scalar(InvalidOperand), expression, })
        }
        let unit = state.input[timestamp.offset]
        match component {
          @timestamp.Literal(text) =>
            if unit != text[timestamp.digit] {
              return Err({ kind: Scalar(InvalidOperand), expression, })
            }
          @timestamp.Token(token) => {
            let part = timestamp_token_index(token)
            if part < 0 || unit < '0' || unit > '9' {
              return Err({ kind: Scalar(InvalidOperand), expression, })
            }
            timestamp.parts[part] = timestamp.parts[part] * 10 +
              unit.to_int() -
              48
          }
        }
        timestamp.offset += 1
        advance_timestamp_pattern_position(timestamp)
        return Ok(None)
      }
    }
  }
  let character = if state.kind == TextParseTimestamp {
    if state.position < 24 {
      Some(timestamp_canonical_character(timestamp.parts, state.position))
    } else {
      None
    }
  } else {
    timestamp_pattern_character(state, timestamp)
  }
  if character is Some(character) {
    if !state.building &&
      state.units.to_int64() >= @text_bounds.output_bytes(output) {
      return Err({ kind: TextBounds(@text_bounds.OutputCeiling), expression, })
    }
    match append_text_function_codepoint(state, character, 1, 1, 1) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    state.position += 1
    if state.kind == TextFormatTimestamp {
      advance_timestamp_pattern_position(timestamp)
    }
    return Ok(None)
  }
  if !state.building {
    // The sizing pass charged the output logical root. Reserve both the
    // builder and final immutable String overlap before allocating either.
    if !reserve_slots(workspace, state.units * 2) {
      return Err({ kind: WorkspaceLimit, expression, })
    }
    state.allocated = state.units * 2
    state.builder = Some(StringBuilder(size_hint=state.units * 2))
    state.building = true
    state.position = 0
    timestamp.component = 0
    timestamp.digit = 0
    return Ok(None)
  }
  guard state.builder is Some(builder) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  let result = builder.to_string()
  state.builder = None
  if state.kind == TextParseTimestamp &&
    @admitted.timestamp_instant(result) is None {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  if state.output_root is Some(root) {
    root.root.measurement = Some({
      wire_bytes: state.bytes,
      weight: state.weight,
    })
  }
  Ok(
    Some(
      if state.kind == TextParseTimestamp {
        match
          @admitted.checked_timestamp_value(
            result,
            @contract.with_nullability(
              @lower.expression_contract(expression),
              false,
            ),
          ) {
          Some(checked) => capture(checked.value)
          None => return Err({ kind: Scalar(InvalidOperand), expression, })
        }
      } else {
        Text(result)
      },
    ),
  )
}
