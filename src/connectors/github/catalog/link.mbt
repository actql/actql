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
fn trim(text : String) -> String {
  let mut start = 0
  let mut end = text.length()
  while start < end && (text[start] == ' ' || text[start] == '\t') {
    start = start + 1
  }
  while end > start && (text[end - 1] == ' ' || text[end - 1] == '\t') {
    end = end - 1
  }
  text.view(start_offset=start, end_offset=end).to_owned()
}

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
/// The `rel="next"` target of an RFC 8288 header value, or None when the
/// header has no next relation. Any malformed entry refuses the whole value.
fn next_target(link : String) -> Result[String?, LinkIssue] {
  let mut found = None
  for entry in split_on(link, ',') {
    let parts = split_on(entry, ';')
    let target = trim(parts[0])
    if target.length() < 2 ||
      target[0] != '<' ||
      target[target.length() - 1] != '>' {
      return Err(MalformedLink)
    }
    let mut next = false
    for index = 1; index < parts.length(); index = index + 1 {
      let parameter = trim(parts[index])
      if parameter == "rel=\"next\"" || parameter == "rel=next" {
        next = true
      } else if !parameter.has_prefix("rel=") {
        return Err(MalformedLink)
      }
    }
    if next {
      if found is Some(_) {
        return Err(MalformedLink)
      }
      found = Some(
        target.view(start_offset=1, end_offset=target.length() - 1).to_owned(),
      )
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
