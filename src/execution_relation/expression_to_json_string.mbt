///|
// One cursor, its current token and the empty ancestry vector. Decimal and
// Number text and additional ancestry slots are admitted separately.
const SQL_JSON_CURSOR_SLOTS : Int = 20

///|
const SQL_JSON_PARENT_SLOTS : Int = 7

///|
priv enum SqlJsonContainer {
  JsonArray(@admitted.FrozenArray[@admitted.Value])
  JsonObject(@admitted.FrozenArray[(String, @admitted.Value)])
  JsonVector(@admitted.FrozenArray[Double])
  JsonRetired
}

///|
priv struct SqlJsonParent {
  mut container : SqlJsonContainer
  size : Int
  mut index : Int
}

///|
priv enum SqlJsonPhase {
  JsonValue(Value)
  JsonScalar(String, Int)
  JsonQuote(String, Int, Bool)
  JsonBeforeItem
  JsonIndent(Int64, Bool)
  JsonItem
  JsonAfterKey
  JsonClose
  JsonDone
}

///|
priv struct SqlJsonCursor {
  original : Value
  pretty : Bool
  parents : Array[SqlJsonParent]
  mut phase : SqlJsonPhase
  mut highwater : Int
  mut token_slots : Int
}

///|
fn append_sql_json_char(
  state : TextFunctionState,
  scalar : Char,
) -> Result[Unit, EvalIssue] {
  let (units, bytes, wire) = text_function_scalar_widths(scalar)
  append_text_function_codepoint(state, scalar, units, bytes, wire)
}

///|
fn append_sql_json_ascii(
  state : TextFunctionState,
  token : String,
) -> Result[Unit, EvalIssue] {
  // Only fixed punctuation or escape sequences pass here.
  for unit in token {
    match append_sql_json_char(state, unit.to_int().unsafe_to_char()) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  Ok(())
}

///|
fn append_sql_json_quoted_char(
  state : TextFunctionState,
  scalar : Char,
) -> Result[Unit, EvalIssue] {
  let token = match scalar {
    '"' => "\\\""
    '\\' => "\\\\"
    '\u0008' => "\\b"
    '\u000c' => "\\f"
    '\u000a' => "\\n"
    '\u000d' => "\\r"
    '\u0009' => "\\t"
    _ => ""
  }
  if !token.is_empty() {
    return append_sql_json_ascii(state, token)
  }
  let value = scalar.to_int()
  if value >= 0x20 {
    return append_sql_json_char(state, scalar)
  }
  match append_sql_json_ascii(state, "\\u00") {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let hex = "0123456789abcdef"
  match append_sql_json_char(state, hex[value >> 4].to_int().unsafe_to_char()) {
    Err(issue) => return Err(issue)
    Ok(_) =>
      append_sql_json_char(state, hex[value & 15].to_int().unsafe_to_char())
  }
}

///|
fn reserve_sql_json_leaf(
  json : SqlJsonCursor,
  state : TextFunctionState,
  workspace : RowWorkspace,
  slots : Int,
) -> Result[Unit, EvalIssue] {
  if !reserve_slots(workspace, slots) {
    return Err({ kind: WorkspaceLimit, expression: state.expression, })
  }
  json.token_slots = slots
  Ok(())
}

///|
fn finish_sql_json_leaf(json : SqlJsonCursor, workspace : RowWorkspace) -> Unit {
  release_slots(workspace, json.token_slots)
  json.token_slots = 0
  json.phase = JsonBeforeItem
}

///|
fn open_sql_json_container(
  json : SqlJsonCursor,
  state : TextFunctionState,
  workspace : RowWorkspace,
  container : SqlJsonContainer,
  size : Int,
  delimiter : Char,
) -> Result[Unit, EvalIssue] {
  if json.parents.length() == json.highwater {
    // A vacated slot is cleared but its vector capacity can be reused.
    if !reserve_slots(workspace, SQL_JSON_PARENT_SLOTS) {
      return Err({ kind: WorkspaceLimit, expression: state.expression, })
    }
    json.highwater += 1
  }
  json.parents.push({ container, size, index: 0, })
  json.phase = JsonBeforeItem
  append_sql_json_char(state, delimiter)
}

///|
fn sql_json_decimal(value : @admitted.DecimalValue) -> (String, Bool) {
  let text = @admitted.decimal_wire_text(value)
  let mut end = text.length()
  if value.scale > 0 {
    let integer_end = end - value.scale - 1
    while end > integer_end + 1 && text[end - 1] == '0' {
      end -= 1
    }
    if end > integer_end + 1 {
      return (text[:end].to_owned(), true)
    }
    end = integer_end
  }
  let start = if text.has_prefix("-") { 1 } else { 0 }
  let mut magnitude = 0L
  let mut quoted = end - start > 16
  if !quoted {
    for index in start..<end {
      magnitude = magnitude * 10L + (text[index].to_int() - 48).to_int64()
    }
    quoted = magnitude > 9007199254740992L
  }
  (if end == text.length() { text } else { text[:end].to_owned() }, quoted)
}

///|
fn start_sql_json_value(
  json : SqlJsonCursor,
  state : TextFunctionState,
  workspace : RowWorkspace,
  value : Value,
) -> Result[Unit, EvalIssue] {
  match value {
    Null => json.phase = JsonScalar("null", 0)
    Boolean(value) =>
      json.phase = JsonScalar(if value { "true" } else { "false" }, 0)
    Text(text) => {
      json.phase = JsonQuote(text, 0, false)
      return append_sql_json_char(state, '"')
    }
    Number(number) => {
      if number.is_nan() || number.is_inf() {
        return Err({
          kind: Scalar(InvalidOperand),
          expression: state.expression,
        })
      }
      match reserve_sql_json_leaf(json, state, workspace, 29) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      json.phase = JsonScalar(number.to_string(), 0)
    }
    Captured(@admitted.Signed64(number)) => {
      match reserve_sql_json_leaf(json, state, workspace, 24) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      let text = number.to_string()
      if number < -9007199254740992L || number > 9007199254740992L {
        json.phase = JsonQuote(text, 0, false)
        return append_sql_json_char(state, '"')
      }
      json.phase = JsonScalar(text, 0)
    }
    Captured(@admitted.Date(text) | @admitted.Timestamp(text)) => {
      json.phase = JsonQuote(text, 0, false)
      return append_sql_json_char(state, '"')
    }
    Captured(@admitted.Decimal(decimal)) => {
      // Fixed-scale conversion holds a detached sign/digits, padded spelling
      // and separate prefix/suffix, before retaining the final trimmed token.
      match
        reserve_sql_json_leaf(
          json,
          state,
          workspace,
          14 + 7 * (decimal.precision + 3),
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      let (text, quoted) = sql_json_decimal(decimal)
      if quoted {
        json.phase = JsonQuote(text, 0, false)
        return append_sql_json_char(state, '"')
      }
      json.phase = JsonScalar(text, 0)
    }
    Captured(@admitted.Array(items)) =>
      return open_sql_json_container(
        json,
        state,
        workspace,
        JsonArray(items),
        @admitted.element_count(items),
        '[',
      )
    Captured(@admitted.Object(fields)) =>
      return open_sql_json_container(
        json,
        state,
        workspace,
        JsonObject(fields),
        @admitted.element_count(fields),
        '{',
      )
    Captured(@admitted.Vector(items)) =>
      return open_sql_json_container(
        json,
        state,
        workspace,
        JsonVector(items),
        @admitted.element_count(items),
        '[',
      )
    Captured(@admitted.JsonData(value)) =>
      json.phase = JsonValue(capture(value))
    _ =>
      return Err({ kind: Scalar(InvalidOperand), expression: state.expression, })
  }
  Ok(())
}

///|
// One token transition, original Unicode scalar, or indentation space per
// poll. The measuring and building passes borrow the same original value.
fn advance_sql_json(
  json : SqlJsonCursor,
  state : TextFunctionState,
  workspace : RowWorkspace,
) -> Result[Value?, EvalIssue] {
  let invalid = { kind: Scalar(InvalidOperand), expression: state.expression, }
  let step = match json.phase {
    JsonValue(value) => start_sql_json_value(json, state, workspace, value)
    JsonScalar(text, position) =>
      if position == text.length() {
        finish_sql_json_leaf(json, workspace)
        Ok(())
      } else {
        guard text_function_scalar(text, position) is Some((scalar, next, _, _)) else {
          return Err(invalid)
        }
        json.phase = JsonScalar(text, next)
        append_sql_json_char(state, scalar)
      }
    JsonQuote(text, position, key) =>
      if position == text.length() {
        match append_sql_json_char(state, '"') {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
        if key {
          json.phase = JsonAfterKey
        } else {
          finish_sql_json_leaf(json, workspace)
        }
        Ok(())
      } else {
        guard text_function_scalar(text, position) is Some((scalar, next, _, _)) else {
          return Err(invalid)
        }
        json.phase = JsonQuote(text, next, key)
        append_sql_json_quoted_char(state, scalar)
      }
    JsonBeforeItem => {
      guard json.parents.last() is Some(parent) else {
        json.phase = JsonDone
        return Ok(None)
      }
      let closing = parent.index == parent.size
      json.phase = if closing { JsonClose } else { JsonItem }
      if json.pretty && parent.size > 0 {
        let depth = json.parents.length().to_int64() -
          (if closing { 1L } else { 0L })
        json.phase = JsonIndent(depth * 2L, closing)
        append_sql_json_ascii(
          state,
          if !closing && parent.index > 0 {
            ",\n"
          } else {
            "\n"
          },
        )
      } else if !closing && parent.index > 0 {
        append_sql_json_char(state, ',')
      } else {
        Ok(())
      }
    }
    JsonIndent(left, closing) =>
      if left == 0L {
        json.phase = if closing { JsonClose } else { JsonItem }
        Ok(())
      } else {
        json.phase = JsonIndent(left - 1L, closing)
        append_sql_json_char(state, ' ')
      }
    JsonItem => {
      guard json.parents.last() is Some(parent) else { return Err(invalid) }
      match parent.container {
        JsonObject(fields) => {
          guard @admitted.element_at(fields, parent.index) is Some((key, _)) else {
            return Err(invalid)
          }
          json.phase = JsonQuote(key, 0, true)
          append_sql_json_char(state, '"')
        }
        JsonArray(items) => {
          guard @admitted.element_at(items, parent.index) is Some(value) else {
            return Err(invalid)
          }
          parent.index += 1
          json.phase = JsonValue(capture(value))
          Ok(())
        }
        JsonVector(items) => {
          guard @admitted.element_at(items, parent.index) is Some(value) else {
            return Err(invalid)
          }
          parent.index += 1
          json.phase = JsonValue(Number(value))
          Ok(())
        }
        JsonRetired => Err(invalid)
      }
    }
    JsonAfterKey => {
      guard json.parents.last() is Some(parent) &&
        parent.container is JsonObject(fields) &&
        @admitted.element_at(fields, parent.index) is Some((_, value)) else {
        return Err(invalid)
      }
      parent.index += 1
      json.phase = JsonValue(capture(value))
      append_sql_json_ascii(state, if json.pretty { ": " } else { ":" })
    }
    JsonClose => {
      guard json.parents.last() is Some(parent) else { return Err(invalid) }
      let delimiter = if parent.container is JsonObject(_) { '}' } else { ']' }
      parent.container = JsonRetired
      json.parents.truncate(json.parents.length() - 1)
      json.phase = JsonBeforeItem
      append_sql_json_char(state, delimiter)
    }
    JsonDone => {
      if state.building {
        release_slots(workspace, json.highwater * SQL_JSON_PARENT_SLOTS)
        return finish_measured_text_output(state).map(value => Some(value))
      }
      match begin_measured_text_output(state, workspace) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      json.phase = JsonValue(json.original)
      Ok(())
    }
  }
  step.map(_ => None)
}
