///|
priv enum RawJsonScalar {
  JsonRawContinue
  JsonRawMissing
  JsonRawSelected(start~ : Int, end~ : Int, quoted~ : Bool)
}

///|
priv enum JsonNumberPhase {
  JsonNumberStart
  JsonNumberZero
  JsonNumberDigits
  JsonNumberFractionStart
  JsonNumberFraction
  JsonNumberExponentStart
  JsonNumberExponentSign
  JsonNumberExponent
}

///|
priv enum JsonRawPhase {
  JsonRawValue(Int)
  JsonRawItem(Bool)
  JsonRawKey(Int)
  JsonRawColon(Int)
  JsonRawAfterValue
  JsonRawQuotedValue(Int, Bool)
  JsonRawNumber(Int, Bool, JsonNumberPhase)
}

///|
priv struct JsonRawParent {
  object : Bool
  level : Int
  mut index : Int64
}

///|
priv struct JsonRawScalarCursor {
  text : String
  parents : Array[JsonRawParent]
  mut phase : JsonRawPhase
  mut position : Int
  mut highwater : Int
}

///|
const JSON_RAW_PARENT_SLOTS : Int = 6

///|
fn json_raw_space(unit : Int) -> Bool {
  unit == 32 || unit == 9 || unit == 10 || unit == 13
}

///|
fn json_raw_literal(cursor : JsonRawScalarCursor, literal : String) -> Bool {
  let from = cursor.position
  if cursor.text.length() - from < literal.length() {
    return false
  }
  // Only the fixed JSON literal spellings pass here.
  for slot in 0..<literal.length() {
    if cursor.text[from + slot] != literal[slot] {
      return false
    }
  }
  cursor.position += literal.length()
  true
}

///|
fn advance_json_raw_number(
  cursor : JsonRawScalarCursor,
  start : Int,
  selected : Bool,
  phase : JsonNumberPhase,
  unit : Int,
) -> RawJsonScalar {
  let digit = json_value_digit(unit)
  let next = match phase {
    JsonNumberStart => {
      if !digit {
        return JsonRawMissing
      }
      Some(if unit == 48 { JsonNumberZero } else { JsonNumberDigits })
    }
    JsonNumberZero | JsonNumberDigits =>
      if digit {
        if phase is JsonNumberZero {
          return JsonRawMissing
        }
        Some(JsonNumberDigits)
      } else if unit == 46 {
        Some(JsonNumberFractionStart)
      } else if unit == 101 || unit == 69 {
        Some(JsonNumberExponentStart)
      } else {
        None
      }
    JsonNumberFractionStart => {
      if !digit {
        return JsonRawMissing
      }
      Some(JsonNumberFraction)
    }
    JsonNumberFraction =>
      if digit {
        Some(JsonNumberFraction)
      } else if unit == 101 || unit == 69 {
        Some(JsonNumberExponentStart)
      } else {
        None
      }
    JsonNumberExponentStart | JsonNumberExponentSign =>
      if digit {
        Some(JsonNumberExponent)
      } else if phase is JsonNumberExponentStart && (unit == 43 || unit == 45) {
        Some(JsonNumberExponentSign)
      } else {
        return JsonRawMissing
      }
    JsonNumberExponent => if digit { Some(JsonNumberExponent) } else { None }
  }
  match next {
    Some(next) => {
      cursor.position += 1
      cursor.phase = JsonRawNumber(start, selected, next)
      JsonRawContinue
    }
    None =>
      if selected {
        JsonRawSelected(start~, end=cursor.position, quoted=false)
      } else {
        cursor.phase = JsonRawAfterValue
        JsonRawContinue
      }
  }
}

///|
fn start_json_raw_container(
  cursor : JsonRawScalarCursor,
  level : Int,
  object : Bool,
  workspace : RowWorkspace,
  expression : @lower.Expression,
) -> Result[RawJsonScalar, EvalIssue] {
  if cursor.parents.length() == cursor.highwater {
    if !reserve_slots(workspace, JSON_RAW_PARENT_SLOTS) {
      return Err({ kind: WorkspaceLimit, expression, })
    }
    cursor.highwater += 1
  }
  cursor.parents.push({ object, level, index: 0L, })
  cursor.position += 1
  cursor.phase = JsonRawItem(true)
  Ok(JsonRawContinue)
}

///|
// Visit only the prefix required to find the path. Unselected strings and
// numbers are read in place. An accepted scalar is a range in the original,
// so trailing bytes do not affect it and no whole JSON tree is retained.
fn advance_json_raw_scalar(
  cursor : JsonRawScalarCursor,
  path : JsonValuePath,
  workspace : RowWorkspace,
  expression : @lower.Expression,
) -> Result[RawJsonScalar, EvalIssue] {
  let at = cursor.position
  let text = cursor.text
  let unit = if at == text.length() { -1 } else { text[at].to_int() }
  match cursor.phase {
    JsonRawNumber(start, selected, phase) =>
      return Ok(advance_json_raw_number(cursor, start, selected, phase, unit))
    JsonRawQuotedValue(start, selected) =>
      if unit == 34 {
        cursor.position += 1
        if selected {
          return Ok(JsonRawSelected(start~, end=at, quoted=true))
        }
        cursor.phase = JsonRawAfterValue
        return Ok(JsonRawContinue)
      } else if json_value_quoted_scalar(text, at) is Some((_, next)) {
        cursor.position = next
        return Ok(JsonRawContinue)
      } else {
        return Ok(JsonRawMissing)
      }
    JsonRawKey(key_offset) => {
      guard cursor.parents.last() is Some(parent) else {
        return Ok(JsonRawMissing)
      }
      if unit == 34 {
        let match_level = match path.parts.get(parent.level) {
          Some(JsonMember(end~, ..)) if end == key_offset => parent.level + 1
          _ => -1
        }
        cursor.position += 1
        cursor.phase = JsonRawColon(match_level)
      } else if json_value_quoted_scalar(text, at) is Some((scalar, next)) {
        let matched = match
          json_value_key_scalar(path, parent.level, key_offset) {
          Some((name, end)) if name == scalar => end
          _ => -1
        }
        cursor.position = next
        cursor.phase = JsonRawKey(matched)
      } else {
        return Ok(JsonRawMissing)
      }
      return Ok(JsonRawContinue)
    }
    _ => ()
  }
  if json_raw_space(unit) {
    cursor.position += 1
    return Ok(JsonRawContinue)
  }
  match cursor.phase {
    JsonRawValue(level) => {
      let selected = level == path.parts.length()
      match unit {
        123 | 91 =>
          if selected {
            return Ok(JsonRawMissing)
          } else {
            return start_json_raw_container(
              cursor,
              level,
              unit == 123,
              workspace,
              expression,
            )
          }
        34 => {
          cursor.position += 1
          cursor.phase = JsonRawQuotedValue(cursor.position, selected)
        }
        digit if digit == 45 || json_value_digit(digit) => {
          let phase = if unit == 45 {
            JsonNumberStart
          } else if unit == 48 {
            JsonNumberZero
          } else {
            JsonNumberDigits
          }
          cursor.position += 1
          cursor.phase = JsonRawNumber(at, selected, phase)
        }
        110 | 116 | 102 => {
          let literal = if unit == 110 {
            "null"
          } else if unit == 116 {
            "true"
          } else {
            "false"
          }
          if !json_raw_literal(cursor, literal) {
            return Ok(JsonRawMissing)
          }
          if selected {
            return Ok(
              if unit == 110 {
                JsonRawMissing
              } else {
                JsonRawSelected(start=at, end=cursor.position, quoted=false)
              },
            )
          }
          cursor.phase = JsonRawAfterValue
        }
        _ => return Ok(JsonRawMissing)
      }
    }
    JsonRawItem(first) => {
      guard cursor.parents.last() is Some(parent) else {
        return Ok(JsonRawMissing)
      }
      let closing = if parent.object { 125 } else { 93 }
      if first && unit == closing {
        ignore(cursor.parents.pop())
        cursor.position += 1
        cursor.phase = JsonRawAfterValue
      } else if parent.object {
        if unit != 34 {
          return Ok(JsonRawMissing)
        }
        let key_offset = match path.parts.get(parent.level) {
          Some(JsonMember(start~, ..)) => start
          _ => -1
        }
        cursor.position += 1
        cursor.phase = JsonRawKey(key_offset)
      } else {
        let level = match path.parts.get(parent.level) {
          Some(JsonIndex(index)) if index == parent.index => parent.level + 1
          _ => -1
        }
        parent.index += 1L
        cursor.phase = JsonRawValue(level)
      }
    }
    JsonRawColon(level) =>
      if unit == 58 {
        cursor.position += 1
        cursor.phase = JsonRawValue(level)
      } else {
        return Ok(JsonRawMissing)
      }
    JsonRawAfterValue => {
      guard cursor.parents.last() is Some(parent) else {
        return Ok(JsonRawMissing)
      }
      let closing = if parent.object { 125 } else { 93 }
      if unit == closing {
        ignore(cursor.parents.pop())
        cursor.position += 1
      } else if unit == 44 {
        cursor.position += 1
        cursor.phase = JsonRawItem(false)
      } else {
        return Ok(JsonRawMissing)
      }
    }
    _ => return Ok(JsonRawMissing)
  }
  Ok(JsonRawContinue)
}
