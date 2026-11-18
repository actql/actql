///|
/// Pure closed GET declaration DATA. These bounds describe construction and
/// transport shape, never a Run, Account, read grant or Resource reservation.
pub(all) struct RowSourceGetReadLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_path_bytes : Int
  max_query_pairs : Int
  max_query_value_units : Int
  max_header_name_bytes : Int
  max_header_value_bytes : Int
}

///|
pub(all) enum RowSourceGetReadIssue {
  InvalidLimits
  InvalidRead
  InvalidPath
  InvalidQuery
  DuplicateParameter
  InvalidPageSize
  InvalidHeader
  InvalidCursor
  ForeignRead
} derive(Eq, Debug)

///|
/// Retained original parser backing and checked request fields in this SAME
/// namespace. No physical handle or mutable cursor/permission state is added.
struct RowSourceGetRead {
  origin : Ref[Unit]
  raw : Bytes
  root : @decode.Cursor
  path : String
  query : Array[(String, String)]
  cursor_parameter : String?
  page_size : (String, Int)?
  version_header : (String, String)?
  limits : RowSourceGetReadLimits
}

///|
/// Outgoing request DATA only. The Host still owns encoding, credential
/// resolution/current checks, send, response charge and physical retirement.
struct RowSourceGetPageRequest {
  origin : Ref[Unit]
  path : String
  query : Array[Array[String]]
  headers : Array[Array[String]]
}

///|
priv suberror GetReadStop {
  GetReadStop(RowSourceGetReadIssue)
}

///|
fn get_read_parameter(name : String) -> Bool {
  if name.is_empty() {
    return false
  }
  for index in 0..<name.length() {
    let c = name[index]
    let alpha = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
    if !alpha && (index == 0 || !((c >= '0' && c <= '9') || c == '_')) {
      return false
    }
  }
  true
}

///|
fn get_read_no_control(text : String, space : Bool) -> Bool {
  if @scalar.unicode_scalar_count(text) is None {
    return false
  }
  for index in 0..<text.length() {
    let c = text[index]
    if c <= (if space { ' ' } else { '\u{001f}' }) || c == '\u{007f}' {
      return false
    }
  }
  true
}

///|
fn get_read_path(path : String, bound : Int) -> Bool {
  if !path.has_prefix("/") ||
    path.has_prefix("//") ||
    !get_read_no_control(path, true) ||
    @scalar.admit_utf8_length(path, bound) is Err(_) {
    return false
  }
  for index in 0..<path.length() {
    // Keep the author's existing exact URL-path contract: no implicit
    // WHATWG percent-encoding or dot-segment normalization is permitted.
    let c = path[index]
    if c > '~' ||
      c == '\\' ||
      c == '?' ||
      c == '#' ||
      c == '"' ||
      c == '<' ||
      c == '>' ||
      c == '`' ||
      c == '{' ||
      c == '}' {
      return false
    }
    if path[index] == '%' && index <= path.length() - 3 {
      let a = path[index + 1]
      let b = path[index + 2]
      if (a == '2' && (b == 'f' || b == 'F' || b == 'e' || b == 'E')) ||
        (a == '5' && (b == 'c' || b == 'C')) {
        return false
      }
    }
  }
  let mut segment = 1
  let mut end = 1
  while end <= path.length() {
    if end == path.length() || path[end] == '/' {
      let length = end - segment
      if (length == 1 && path[segment] == '.') ||
        (length == 2 && path[segment] == '.' && path[segment + 1] == '.') {
        return false
      }
      if end == path.length() {
        break
      }
      segment = end + 1
    }
    end += 1
  }
  true
}

///|
fn get_read_header(
  name : String,
  value : String,
  limits : RowSourceGetReadLimits,
) -> Bool {
  if !name.has_suffix("version") ||
    @scalar.admit_utf8_length(name, limits.max_header_name_bytes) is Err(_) ||
    value.is_empty() ||
    value.has_prefix(" ") ||
    value.has_suffix(" ") ||
    @scalar.admit_utf8_length(value, limits.max_header_value_bytes) is Err(_) {
    return false
  }
  let mut segment = 0
  for index in 0..<name.length() {
    let c = name[index]
    if c == '-' {
      if segment == 0 {
        return false
      }
      segment = 0
    } else if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
      segment += 1
    } else {
      return false
    }
  }
  if segment != 7 {
    return false
  }
  for index in 0..<value.length() {
    let c = value[index]
    if c < ' ' || c > '~' {
      return false
    }
  }
  true
}

///|
fn get_read_text(
  object : @decode.ObjectView,
  name : String,
) -> String raise GetReadStop {
  guard @decode.lookup(object, name) is Some(value) &&
    @decode.text(value) is Ok(text) else {
    raise GetReadStop(InvalidRead)
  }
  text
}

///|
fn get_read_name_taken(
  query : Array[(String, String)],
  cursor : String?,
  name : String,
) -> Bool {
  if cursor == Some(name) {
    return true
  }
  for pair in query {
    if pair.0 == name {
      return true
    }
  }
  false
}

///|
/// Admit once before any request construction. Original strings/order remain
/// exact; unknown/duplicate fields or ambiguous mappings refuse the whole read.
pub fn admit_row_source_get_read(
  bytes : Bytes,
  cursor_parameter : String?,
  limits : RowSourceGetReadLimits,
) -> Result[RowSourceGetRead, RowSourceGetReadIssue] {
  if !get_read_limits_valid(limits) || bytes.length() > limits.max_bytes {
    return Err(InvalidLimits)
  }
  if cursor_parameter is Some(name) && !get_read_parameter(name) {
    return Err(InvalidCursor)
  }
  let original = Bytes::makei(bytes.length(), index => bytes[index])
  let source = match
    @source.parse_json_bytes_preserving(original, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidRead)
  }
  let root = match
    @decode.admit(source, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidRead)
  }
  try {
    guard @decode.closed_object(root, [
        "method", "path", "query", "pageSize", "versionHeader",
      ])
      is Ok(read) else {
      raise GetReadStop(InvalidRead)
    }
    if get_read_text(read, "method") != "GET" {
      raise GetReadStop(InvalidRead)
    }
    let path = get_read_text(read, "path")
    if !get_read_path(path, limits.max_path_bytes) {
      raise GetReadStop(InvalidPath)
    }
    let query : Array[(String, String)] = []
    if @decode.lookup(read, "query") is Some(values) {
      guard @decode.array_length(values) is Some(count) &&
        count <= limits.max_query_pairs else {
        raise GetReadStop(InvalidQuery)
      }
      for index in 0..<count {
        guard @decode.element_at(values, index) is Some(pair) &&
          @decode.array_length(pair) == Some(2) &&
          @decode.element_at(pair, 0) is Some(key) &&
          @decode.text(key) is Ok(name) &&
          @decode.element_at(pair, 1) is Some(cell) &&
          @decode.text(cell) is Ok(value) else {
          raise GetReadStop(InvalidQuery)
        }
        if !get_read_parameter(name) ||
          value.length() > limits.max_query_value_units ||
          !get_read_no_control(value, false) {
          raise GetReadStop(InvalidQuery)
        }
        if get_read_name_taken(query, cursor_parameter, name) {
          raise GetReadStop(DuplicateParameter)
        }
        query.push((name, value))
      }
    }
    let page_size = if @decode.lookup(read, "pageSize") is Some(value) {
      guard @decode.closed_object(value, ["parameter", "limit"]) is Ok(size) &&
        @decode.lookup(size, "limit") is Some(raw_limit) &&
        @decode.int32(raw_limit) is Ok(limit) &&
        limit > 0 else {
        raise GetReadStop(InvalidPageSize)
      }
      let parameter = get_read_text(size, "parameter")
      if !get_read_parameter(parameter) {
        raise GetReadStop(InvalidPageSize)
      }
      if get_read_name_taken(query, cursor_parameter, parameter) {
        raise GetReadStop(DuplicateParameter)
      }
      Some((parameter, limit))
    } else {
      None
    }
    let version_header = if @decode.lookup(read, "versionHeader") is Some(value) {
      guard @decode.closed_object(value, ["name", "value"]) is Ok(header) else {
        raise GetReadStop(InvalidHeader)
      }
      let name = get_read_text(header, "name")
      let value = get_read_text(header, "value")
      if !get_read_header(name, value, limits) {
        raise GetReadStop(InvalidHeader)
      }
      Some((name, value))
    } else {
      None
    }
    let extra = (if page_size is Some(_) { 1 } else { 0 }) +
      (if cursor_parameter is Some(_) { 1 } else { 0 })
    if extra > limits.max_query_pairs ||
      query.length() > limits.max_query_pairs - extra {
      raise GetReadStop(InvalidQuery)
    }
    Ok({
      origin: projected_json_page_origin,
      raw: original,
      root,
      path,
      query,
      cursor_parameter,
      page_size,
      version_header,
      limits,
    })
  } catch {
    GetReadStop(issue) => Err(issue)
  }
}

///|
/// The legacy provider supplies its original row ceiling/profile hint; the
/// portable cursor caller obtains that same ceiling from its existing Owner.
/// This returns request DATA, never a read/claim/cleanup permission.
pub fn row_source_get_read_page(
  read : RowSourceGetRead,
  remaining_rows : Int,
  page_hint : Int,
  cursor : String?,
) -> Result[RowSourceGetPageRequest, RowSourceGetReadIssue] {
  if !physical_equal(read.origin, projected_json_page_origin) {
    return Err(ForeignRead)
  }
  if remaining_rows < 1 || page_hint < 1 {
    return Err(InvalidPageSize)
  }
  if cursor is Some(value) &&
    (
      read.cursor_parameter is None ||
      @scalar.unicode_scalar_count(value) is None
    ) {
    return Err(InvalidCursor)
  }
  let query = read.query.map(pair => [pair.0, pair.1])
  if read.page_size is Some((parameter, limit)) {
    query.push([
      parameter,
      Int::min(limit, Int::min(page_hint, remaining_rows)).to_string(),
    ])
  }
  if cursor is Some(value) {
    guard read.cursor_parameter is Some(parameter) &&
      @scalar.unicode_scalar_count(value) is Some(_) else {
      return Err(InvalidCursor)
    }
    query.push([parameter, value])
  }
  let headers = [["accept", "application/json"]]
  if read.version_header is Some((name, value)) {
    headers.push([name, value])
  }
  if query.length() > read.limits.max_query_pairs {
    return Err(InvalidQuery)
  }
  Ok({ origin: projected_json_page_origin, path: read.path, query, headers, })
}

///|
/// Original admitted public DATA for a data-only authoring tool. This is not
/// an executable request or a Source/Account receipt. Runtime paging retains
/// the opaque checked read and never reparses this wire per operation.
pub fn row_source_get_read_original_wire(
  read : RowSourceGetRead,
) -> Result[String, RowSourceGetReadIssue] {
  if !physical_equal(read.origin, projected_json_page_origin) ||
    read.raw.length() > read.limits.max_bytes ||
    @decode.object_length(read.root) is None {
    return Err(ForeignRead)
  }
  Ok(@utf8.decode(read.raw)) catch {
    _ => Err(InvalidRead)
  }
}

///|
/// Canonical public tuple of transport DATA. Query/header vectors are copied;
/// no mutable alias to the checked Source declaration escapes this accessor.
pub fn row_source_get_page_frame(
  page : RowSourceGetPageRequest,
) -> Result[
  (String, String, Array[Array[String]], Array[Array[String]]),
  RowSourceGetReadIssue,
] {
  if !physical_equal(page.origin, projected_json_page_origin) {
    return Err(ForeignRead)
  }
  Ok(
    (
      "GET",
      page.path,
      page.query.map(pair => pair.copy()),
      page.headers.map(pair => pair.copy()),
    ),
  )
}

///|
/// Original scalar declaration facts for target binding and the existing
/// implementation's page-hint eligibility. Presence is DATA, not permission.
/// The whole request remains opaque and bound to its original namespace.
pub fn row_source_get_read_metadata(
  read : RowSourceGetRead,
) -> Result[(String, Bool, Int, Int, Int), RowSourceGetReadIssue] {
  if !physical_equal(read.origin, projected_json_page_origin) {
    return Err(ForeignRead)
  }
  let has_size = read.page_size is Some(_)
  let size = match read.page_size {
    None => 0
    Some((_, value)) => value
  }
  Ok(
    (
      read.path,
      has_size,
      size,
      read.query.length() +
      (if has_size { 1 } else { 0 }) +
      (if read.cursor_parameter is Some(_) { 1 } else { 0 }),
      1 + (if read.version_header is Some(_) { 1 } else { 0 }),
    ),
  )
}
