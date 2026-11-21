///|
priv enum JsonValuePart {
  JsonMember(start~ : Int, end~ : Int, quoted~ : Bool)
  JsonIndex(Int64)
}

///|
priv enum JsonValuePathPhase {
  JsonPathRoot
  JsonPathSeparator
  JsonPathKey(Int)
  JsonPathQuotedKey(Int)
  JsonPathIndexStart
  JsonPathIndexToken(Int64, Bool, Bool)
  JsonPathIndexTail(Int64)
}

///|
priv struct JsonValuePath {
  text : String
  parts : Array[JsonValuePart]
  mut position : Int
  mut phase : JsonValuePathPhase
}

///|
const JSON_VALUE_PART_SLOTS : Int = 6

///|
fn json_value_digit(unit : Int) -> Bool {
  unit >= 48 && unit <= 57
}

///|
fn json_value_hex(text : String, start : Int) -> Int? {
  if text.length() - start < 4 {
    return None
  }
  let mut value = 0
  for index in start..<(start + 4) {
    let unit = text[index].to_int()
    let digit = if json_value_digit(unit) {
      unit - 48
    } else if unit >= 65 && unit <= 70 {
      unit - 55
    } else if unit >= 97 && unit <= 102 {
      unit - 87
    } else {
      return None
    }
    value = (value << 4) | digit
  }
  Some(value)
}

///|
// Decode the next original scalar in JSON quoted data without constructing a
// substring. The caller handles quote boundaries and reports invalid escapes.
fn json_value_quoted_scalar(text : String, position : Int) -> (Char, Int)? {
  guard position < text.length() else { return None }
  let head = text[position].to_int()
  if head == 34 || head < 32 {
    return None
  }
  if head != 92 {
    return text_function_scalar(text, position).map(item => (item.0, item.1))
  }
  guard text.length() - position >= 2 else { return None }
  let escape = text[position + 1].to_int()
  let next = position + 2
  let point = match escape {
    34 | 47 | 92 => escape
    98 => 8
    102 => 12
    110 => 10
    114 => 13
    116 => 9
    117 => {
      guard json_value_hex(text, next) is Some(first) else { return None }
      let after_hex = next + 4
      if first >= 0xd800 && first <= 0xdbff {
        guard text.length() - after_hex >= 6 &&
          text[after_hex] == '\\' &&
          text[after_hex + 1] == 'u' &&
          json_value_hex(text, after_hex + 2) is Some(second) &&
          second >= 0xdc00 &&
          second <= 0xdfff else {
          return None
        }
        return Some(
          (
            (0x10000 + ((first - 0xd800) << 10) + second - 0xdc00).unsafe_to_char(),
            after_hex + 6,
          ),
        )
      }
      if first >= 0xdc00 && first <= 0xdfff {
        return None
      }
      return Some((first.unsafe_to_char(), after_hex))
    }
    _ => return None
  }
  Some((point.unsafe_to_char(), next))
}

///|
fn json_value_path_space(unit : Int) -> Bool {
  unit == 32 || unit == 9 || unit == 10 || unit == 12 || unit == 13
}

///|
fn json_value_path_key_unit(unit : Int) -> Bool {
  json_value_digit(unit) ||
  (unit >= 65 && unit <= 90) ||
  (unit >= 97 && unit <= 122) ||
  unit == 95 ||
  unit == 45 ||
  unit == 58 ||
  json_value_path_space(unit) ||
  unit >= 128
}

///|
fn json_value_index_other(text : String, offset : Int, unit : Int) -> Int? {
  if unit == 45 || unit == 95 {
    return Some(offset + 1)
  }
  if text_function_scalar(text, offset) is Some((scalar, next, _, _)) &&
    scalar.is_numeric() {
    Some(next)
  } else {
    None
  }
}

///|
fn append_json_value_part(
  path : JsonValuePath,
  part : JsonValuePart,
  workspace : RowWorkspace,
  expression : @lower.Expression,
) -> Result[Bool, EvalIssue] {
  if !reserve_slots(workspace, JSON_VALUE_PART_SLOTS) {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  path.parts.push(part)
  path.phase = JsonPathSeparator
  Ok(false)
}

///|
fn advance_json_value_path(
  path : JsonValuePath,
  workspace : RowWorkspace,
  expression : @lower.Expression,
) -> Result[Bool, EvalIssue] {
  let at = path.position
  let text = path.text
  let unit = if at == text.length() { -1 } else { text[at].to_int() }
  let invalid = { kind: Scalar(InvalidOperand), expression, }
  match path.phase {
    JsonPathRoot =>
      if unit == 36 {
        path.position += 1
        path.phase = JsonPathSeparator
      } else {
        return Err(invalid)
      }
    JsonPathSeparator =>
      match unit {
        -1 => return Ok(true)
        46 => {
          path.position += 1
          if path.position < text.length() && text[path.position] == '"' {
            path.position += 1
            path.phase = JsonPathQuotedKey(path.position)
          } else {
            path.phase = JsonPathKey(path.position)
          }
        }
        91 => {
          path.position += 1
          path.phase = JsonPathIndexStart
        }
        _ => return Err(invalid)
      }
    JsonPathKey(start) =>
      if json_value_path_key_unit(unit) &&
        text_function_scalar(text, at) is Some((_, next, _, _)) {
        path.position = next
      } else if start != at {
        return append_json_value_part(
          path,
          JsonMember(start~, end=at, quoted=false),
          workspace,
          expression,
        )
      } else {
        return Err(invalid)
      }
    JsonPathQuotedKey(start) =>
      if unit == 34 {
        path.position += 1
        return append_json_value_part(
          path,
          JsonMember(start~, end=at, quoted=true),
          workspace,
          expression,
        )
      } else {
        // A backslash and the next scalar form one lexical unit.
        let scalar_at = if unit == 92 { at + 1 } else { at }
        guard text_function_scalar(text, scalar_at) is Some((_, next, _, _)) else {
          return Err(invalid)
        }
        path.position = next
      }
    JsonPathIndexStart =>
      if json_value_path_space(unit) {
        path.position += 1
      } else if json_value_digit(unit) {
        path.position += 1
        path.phase = JsonPathIndexToken((unit - 48).to_int64(), false, true)
      } else if unit == 45 {
        path.position += 1
        path.phase = JsonPathIndexToken(0L, true, false)
      } else if json_value_index_other(text, at, unit) is Some(next) {
        path.position = next
        path.phase = JsonPathIndexToken(-1L, false, false)
      } else {
        return Err(invalid)
      }
    JsonPathIndexToken(index, negative, digits) =>
      if json_value_digit(unit) {
        // An index greater than an Int-sized original array cannot match.
        let next = if index < 0L {
          -1L
        } else {
          (index * 10L + (unit - 48).to_int64()).min(2147483648L)
        }
        path.position += 1
        path.phase = JsonPathIndexToken(next, negative, true)
      } else if json_value_index_other(text, at, unit) is Some(next) {
        path.position = next
        path.phase = JsonPathIndexToken(-1L, negative, digits)
      } else if json_value_path_space(unit) || unit == 93 {
        let parsed = if !digits || (negative && index != 0L) {
          -1L
        } else {
          index
        }
        path.phase = JsonPathIndexTail(parsed)
      } else {
        return Err(invalid)
      }
    JsonPathIndexTail(index) =>
      if json_value_path_space(unit) {
        path.position += 1
      } else if unit == 93 {
        path.position += 1
        return append_json_value_part(
          path,
          JsonIndex(index),
          workspace,
          expression,
        )
      } else {
        return Err(invalid)
      }
  }
  Ok(false)
}

///|
fn json_value_key_scalar(
  path : JsonValuePath,
  level : Int,
  offset : Int,
) -> (Char, Int)? {
  guard path.parts.get(level) is Some(JsonMember(end~, quoted~, ..)) &&
    offset >= 0 &&
    offset < end else {
    return None
  }
  // Only a backslash before a quote within the member is removed.
  if quoted &&
    end - offset >= 2 &&
    path.text[offset] == '\\' &&
    path.text[offset + 1] == '"' {
    return Some(('"', offset + 2))
  }
  text_function_scalar(path.text, offset).map(item => (item.0, item.1))
}
