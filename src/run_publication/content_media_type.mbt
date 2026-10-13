///|
pub(all) enum ContentMediaTypeIssue {
  Text(@scalar.Utf8AdmissionIssue)
  InvalidSyntax
} derive(Eq, Debug)

///|
fn content_media_token(unit : Int) -> Bool {
  if (unit >= 48 && unit <= 57) ||
    (unit >= 65 && unit <= 90) ||
    (unit >= 97 && unit <= 122) {
    return true
  }
  match unit {
    33
    | 35
    | 36
    | 37
    | 38
    | 39
    | 42
    | 43
    | 45
    | 46
    | 94
    | 95
    | 96
    | 124
    | 126 => true
    _ => false
  }
}

///|
fn content_media_ows(unit : Int) -> Bool {
  unit == 32 || unit == 9
}

///|
fn content_media_lower(
  value : String,
  start : Int,
  end : Int,
  output : StringBuilder,
) -> Unit {
  for index in start..<end {
    let unit = value[index].to_int()
    output.write_char(
      (if unit >= 65 && unit <= 90 { unit + 32 } else { unit }).unsafe_to_char(),
    )
  }
}

///|
// Project the case-insensitive MIME type/subtype and parameter names through
// this existing Content owner. Parameter value bytes, quoting, escapes, order
// and whitespace stay exact; this is not a universal MIME-equivalence test.
// The caller retains the original report as evidence and funds simultaneous
// source/output storage before entry. This data projection issues no Ref,
// authenticity, byte validation, Source completion, or Model permission.
pub fn normalize_content_media_type_case(
  reported : String,
  max_bytes : Int,
) -> Result[String, ContentMediaTypeIssue] {
  match @scalar.admit_utf8_length(reported, max_bytes) {
    Ok(_) => ()
    Err(issue) => return Err(Text(issue))
  }
  let length = reported.length()
  let mut cursor = 0
  let mut needs_fold = false
  while cursor < length && content_media_token(reported[cursor].to_int()) {
    let unit = reported[cursor].to_int()
    if unit >= 65 && unit <= 90 {
      needs_fold = true
    }
    cursor += 1
  }
  if cursor == 0 || cursor >= length || reported[cursor] != '/' {
    return Err(InvalidSyntax)
  }
  cursor += 1
  let subtype = cursor
  while cursor < length && content_media_token(reported[cursor].to_int()) {
    let unit = reported[cursor].to_int()
    if unit >= 65 && unit <= 90 {
      needs_fold = true
    }
    cursor += 1
  }
  if cursor == subtype {
    return Err(InvalidSyntax)
  }
  let head = cursor
  // Validate the complete finite report before allocating its output. No
  // default MIME, last-parameter winner, or malformed suffix repair is used.
  while cursor < length {
    while cursor < length && content_media_ows(reported[cursor].to_int()) {
      cursor += 1
    }
    if cursor == length {
      break
    }
    if reported[cursor] != ';' {
      return Err(InvalidSyntax)
    }
    cursor += 1
    while cursor < length && content_media_ows(reported[cursor].to_int()) {
      cursor += 1
    }
    if cursor == length || reported[cursor] == ';' {
      continue
    }
    let name = cursor
    while cursor < length && content_media_token(reported[cursor].to_int()) {
      let unit = reported[cursor].to_int()
      if unit >= 65 && unit <= 90 {
        needs_fold = true
      }
      cursor += 1
    }
    if cursor == name || cursor == length || reported[cursor] != '=' {
      return Err(InvalidSyntax)
    }
    cursor += 1
    if cursor == length {
      return Err(InvalidSyntax)
    }
    if reported[cursor] == '"' {
      cursor += 1
      let mut closed = false
      while cursor < length {
        let unit = reported[cursor].to_int()
        cursor += 1
        if unit == 34 {
          closed = true
          break
        }
        if unit == 92 {
          if cursor == length {
            return Err(InvalidSyntax)
          }
          let escaped = reported[cursor].to_int()
          if escaped != 9 && (escaped < 32 || escaped == 127) {
            return Err(InvalidSyntax)
          }
          cursor += 1
        } else if unit != 9 && (unit < 32 || unit == 127) {
          return Err(InvalidSyntax)
        }
      }
      if !closed {
        return Err(InvalidSyntax)
      }
    } else {
      let start = cursor
      while cursor < length && content_media_token(reported[cursor].to_int()) {
        cursor += 1
      }
      if cursor == start {
        return Err(InvalidSyntax)
      }
    }
    if cursor < length &&
      reported[cursor] != ';' &&
      !content_media_ows(reported[cursor].to_int()) {
      return Err(InvalidSyntax)
    }
  }
  if !needs_fold {
    return Ok(reported)
  }
  let output = StringBuilder()
  content_media_lower(reported, 0, head, output)
  cursor = head
  let mut unchanged = cursor
  while cursor < length {
    if reported[cursor] != ';' {
      cursor += 1
      continue
    }
    cursor += 1
    while cursor < length && content_media_ows(reported[cursor].to_int()) {
      cursor += 1
    }
    let name = cursor
    while cursor < length && content_media_token(reported[cursor].to_int()) {
      cursor += 1
    }
    if name == cursor {
      continue
    }
    output.write_string(reported.substring(start=unchanged, end=name))
    content_media_lower(reported, name, cursor, output)
    unchanged = cursor
    // Skip a value without interpreting semicolons, names or escapes in it.
    cursor += 1
    if reported[cursor] == '"' {
      cursor += 1
      while reported[cursor] != '"' {
        if reported[cursor] == '\\' {
          cursor += 1
        }
        cursor += 1
      }
      cursor += 1
    } else {
      while cursor < length && content_media_token(reported[cursor].to_int()) {
        cursor += 1
      }
    }
  }
  output.write_string(reported.substring(start=unchanged, end=length))
  Ok(output.to_string())
}
