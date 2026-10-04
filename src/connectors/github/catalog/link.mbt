///|
/// Why a `Link` observation was refused. A refused observation is never read
/// as "no next page".
pub(all) enum LinkIssue {
  MalformedLink
  ForeignOrigin
  ForeignResource
  NonAdvancingPage
  LocatorTooLong
} derive(Eq, Debug)

///|
/// The next page of one listing: its exact request path and decoded query
/// pairs (to be encoded once by the common exchange), on the listing's own
/// origin and Resource path, at a strictly later page.
pub(all) struct NextPage {
  path : String
  query : Array[(String, String)]
  page : Int
} derive(Eq, Debug)

///|
fn split_on(text : String, separator : Char) -> Array[String] {
  let parts = []
  let mut start = 0
  for index = 0; index < text.length(); index = index + 1 {
    if text[index] == separator.to_int().to_uint16() {
      parts.push(text.view(start_offset=start, end_offset=index).to_owned())
      start = index + 1
    }
  }
  parts.push(text.view(start_offset=start).to_owned())
  parts
}

///|
fn is_ows(unit : Int) -> Bool {
  unit == 32 || unit == 9
}

///|
/// RFC 9110 `tchar`.
fn is_tchar(unit : Int) -> Bool {
  (unit >= 48 && unit <= 57) ||
  (unit >= 65 && unit <= 90) ||
  (unit >= 97 && unit <= 122) ||
  [33, 35, 36, 37, 38, 39, 42, 43, 45, 46, 94, 95, 96, 124, 126].contains(unit)
}

///|
fn skip_ows(text : String, start : Int) -> Int {
  let mut index = start
  while index < text.length() && is_ows(text[index].to_int()) {
    index = index + 1
  }
  index
}

///|
/// One RFC 8288 `link-value`: its target and the relation types of its first
/// `rel` parameter (later `rel` occurrences are ignored, as §3.3 requires;
/// a value without any `rel` is refused).
priv struct LinkValue {
  target : String
  relations : Array[String]
}

///|
fn lowercase_ascii(text : String) -> String {
  let out = StringBuilder()
  for index = 0; index < text.length(); index = index + 1 {
    let unit = text[index].to_int()
    out.write_char(
      Int::unsafe_to_char(
        if unit >= 65 && unit <= 90 {
          unit + 32
        } else {
          unit
        },
      ),
    )
  }
  out.to_string()
}

///|
/// Parse a whole `Link` field value (RFC 8288 §3, RFC 9110 list syntax).
/// Commas and semicolons inside `<...>` or a quoted string are data, not
/// delimiters. Any syntax error refuses the whole value.
fn parse_link_values(text : String) -> Result[Array[LinkValue], LinkIssue] {
  let values = []
  let mut index = 0
  let length = text.length()
  while true {
    index = skip_ows(text, index)
    if index >= length {
      break
    }
    // Empty list elements are allowed by the list syntax.
    if text[index] == ',' {
      index = index + 1
      continue
    }
    if text[index] != '<' {
      return Err(MalformedLink)
    }
    let target_start = index + 1
    index = target_start
    while index < length && text[index] != '>' {
      let unit = text[index].to_int()
      if unit <= 32 || unit == 127 || unit == 60 {
        return Err(MalformedLink)
      }
      index = index + 1
    }
    if index >= length || index == target_start {
      return Err(MalformedLink)
    }
    let target = text
      .view(start_offset=target_start, end_offset=index)
      .to_owned()
    index = index + 1
    let mut relations : Array[String]? = None
    while true {
      index = skip_ows(text, index)
      if index >= length || text[index] == ',' {
        break
      }
      if text[index] != ';' {
        return Err(MalformedLink)
      }
      index = skip_ows(text, index + 1)
      let name_start = index
      while index < length && is_tchar(text[index].to_int()) {
        index = index + 1
      }
      if index == name_start {
        return Err(MalformedLink)
      }
      let name = lowercase_ascii(
        text.view(start_offset=name_start, end_offset=index).to_owned(),
      )
      index = skip_ows(text, index)
      let mut value : String? = None
      if index < length && text[index] == '=' {
        index = skip_ows(text, index + 1)
        if index < length && text[index] == '"' {
          let quoted = StringBuilder()
          index = index + 1
          let mut closed = false
          while index < length {
            let unit = text[index].to_int()
            if unit == 34 {
              closed = true
              index = index + 1
              break
            }
            if unit == 92 {
              if index + 1 >= length {
                return Err(MalformedLink)
              }
              index = index + 1
            }
            let escaped = text[index].to_int()
            if (escaped < 32 && escaped != 9) || escaped == 127 {
              return Err(MalformedLink)
            }
            quoted.write_char(Int::unsafe_to_char(escaped))
            index = index + 1
          }
          if !closed {
            return Err(MalformedLink)
          }
          value = Some(quoted.to_string())
        } else {
          let value_start = index
          while index < length && is_tchar(text[index].to_int()) {
            index = index + 1
          }
          if index == value_start {
            return Err(MalformedLink)
          }
          value = Some(
            text.view(start_offset=value_start, end_offset=index).to_owned(),
          )
        }
      }
      if name == "rel" && relations is None {
        guard value is Some(types) else { return Err(MalformedLink) }
        let parsed = []
        let mut start = 0
        for position = 0; position <= types.length(); position = position + 1 {
          if position == types.length() || is_ows(types[position].to_int()) {
            if position > start {
              parsed.push(
                lowercase_ascii(
                  types.view(start_offset=start, end_offset=position).to_owned(),
                ),
              )
            }
            start = position + 1
          }
        }
        if parsed.is_empty() {
          return Err(MalformedLink)
        }
        relations = Some(parsed)
      }
    }
    // RFC 8288 §3.3: every link-value carries a `rel` parameter.
    guard relations is Some(types) else { return Err(MalformedLink) }
    values.push({ target, relations: types, })
  }
  Ok(values)
}

///|
/// The `next` target of an RFC 8288 header value. `Ok(None)` only when the
/// whole value parsed and no link-value carries the `next` relation; a
/// malformed value, or more than one `next` target, refuses the observation.
fn next_target(link : String) -> Result[String?, LinkIssue] {
  let values = match parse_link_values(link) {
    Ok(values) => values
    Err(issue) => return Err(issue)
  }
  let mut found = None
  for value in values {
    if value.relations.contains("next") {
      if found is Some(_) {
        return Err(MalformedLink)
      }
      found = Some(value.target)
    }
  }
  Ok(found)
}

///|
fn hex_value(unit : Int) -> Int? {
  if unit >= 48 && unit <= 57 {
    Some(unit - 48)
  } else if unit >= 65 && unit <= 70 {
    Some(unit - 55)
  } else if unit >= 97 && unit <= 102 {
    Some(unit - 87)
  } else {
    None
  }
}

///|
/// Decode one query component of a provider locator. Unreserved characters
/// stay as they are; `%XX` escapes decode to printable ASCII. Anything else,
/// an invalid escape, or a decoded control or non-ASCII byte refuses the
/// link. The decoded value is handed to the common request encoder, which
/// encodes it exactly once.
fn decode_component(text : String) -> String? {
  let decoded = StringBuilder()
  let mut index = 0
  while index < text.length() {
    let unit = text[index].to_int()
    if unit == 37 {
      if index + 2 >= text.length() {
        return None
      }
      let value = match
        (
          hex_value(text[index + 1].to_int()),
          hex_value(text[index + 2].to_int()),
        ) {
        (Some(high), Some(low)) => high * 16 + low
        _ => return None
      }
      if value < 32 || value > 126 {
        return None
      }
      decoded.write_char(Int::unsafe_to_char(value))
      index = index + 3
      continue
    }
    let unreserved = (unit >= 48 && unit <= 57) ||
      (unit >= 65 && unit <= 90) ||
      (unit >= 97 && unit <= 122) ||
      unit == 45 ||
      unit == 46 ||
      unit == 95 ||
      unit == 126 ||
      unit == 44
    if !unreserved {
      return None
    }
    decoded.write_char(Int::unsafe_to_char(unit))
    index = index + 1
  }
  Some(decoded.to_string())
}

///|
fn query_pairs(query : String) -> Result[Array[(String, String)], LinkIssue] {
  let pairs = []
  if query.length() == 0 {
    return Ok(pairs)
  }
  for entry in split_on(query, '&') {
    let pair = split_on(entry, '=')
    if pair.length() != 2 || pair[0].length() == 0 {
      return Err(MalformedLink)
    }
    match (decode_component(pair[0]), decode_component(pair[1])) {
      (Some(name), Some(value)) => pairs.push((name, value))
      _ => return Err(MalformedLink)
    }
  }
  Ok(pairs)
}

///|
/// The next page of the listing at `origin` + `path`, currently at `page`,
/// from its observed `Link` header. None means the provider stated no next
/// page. The returned locator stays on the same origin and Resource path and
/// advances the page; the Host re-checks origin, scope and authorization
/// before sending it.
pub fn next_page(
  link : String?,
  origin : String,
  path : String,
  page : Int,
  max_locator_units : Int,
) -> Result[NextPage?, LinkIssue] {
  guard link is Some(value) else { return Ok(None) }
  let target = match next_target(value) {
    Ok(Some(target)) => target
    Ok(None) => return Ok(None)
    Err(issue) => return Err(issue)
  }
  if target.length() > max_locator_units {
    return Err(LocatorTooLong)
  }
  if !target.has_prefix(origin + "/") {
    return Err(ForeignOrigin)
  }
  let relative = target.view(start_offset=origin.length()).to_owned()
  let pieces = split_on(relative, '?')
  if pieces.length() != 2 {
    return Err(MalformedLink)
  }
  if pieces[0] != path {
    return Err(ForeignResource)
  }
  let query = match query_pairs(pieces[1]) {
    Ok(query) => query
    Err(issue) => return Err(issue)
  }
  let mut next = None
  for pair in query {
    if pair.0 == "page" {
      if next is Some(_) {
        return Err(MalformedLink)
      }
      next = match decimal(pair.1) {
        Some(number) if number <= 1000000L => Some(number.to_int())
        _ => return Err(MalformedLink)
      }
    }
  }
  match next {
    Some(number) if number > page => Ok(Some({ path, query, page: number, }))
    Some(_) => Err(NonAdvancingPage)
    None => Err(MalformedLink)
  }
}
