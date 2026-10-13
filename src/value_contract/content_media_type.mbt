///|
pub(all) enum ContentMediaTypeIssue {
  Utf8(@scalar.Utf8AdmissionIssue)
  InvalidSyntax
  NonCanonicalCase
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
fn validate_content_media_type(
  reported : String,
  max_bytes : Int,
) -> Result[(Int, Bool), ContentMediaTypeIssue] {
  match @scalar.admit_utf8_length(reported, max_bytes) {
    Ok(_) => ()
    Err(issue) => return Err(Utf8(issue))
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
  Ok((head, needs_fold))
}

///|
// Authored/checked descriptors are data, but their case-insensitive names must
// already be canonical. Validation allocates no projected string on refusal;
// opaque parameter values are never passed through identifier normalization.
pub fn admit_content_media_type_descriptor(
  descriptor : String,
  max_bytes : Int,
) -> Result[Unit, ContentMediaTypeIssue] {
  match validate_content_media_type(descriptor, max_bytes) {
    Ok((_, true)) => Err(NonCanonicalCase)
    Ok((_, false)) => Ok(())
    Err(issue) => Err(issue)
  }
}

///|
// Project only case-insensitive MIME names from an actual capture report.
// Preserve parameter values, quoting, escapes, order and whitespace exactly.
// The existing caller owns simultaneous original/projected storage; this
// finite data helper issues no Ref, custody, completion or send authority.
pub fn normalize_content_media_type_case(
  reported : String,
  max_bytes : Int,
) -> Result[String, ContentMediaTypeIssue] {
  let (head, needs_fold) = match
    validate_content_media_type(reported, max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let length = reported.length()
  if !needs_fold {
    return Ok(reported)
  }
  let output = StringBuilder()
  content_media_lower(reported, 0, head, output)
  let mut cursor = head
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
    output.write_view(reported[unchanged:name])
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
  output.write_view(reported[unchanged:length])
  Ok(output.to_string())
}
