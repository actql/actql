///|
pub(all) enum QueryReadIssue {
  InvalidLimits
  InvalidQuery
  AlreadyFinished
  Interrupted
  WrongRequest
  PageAwaitingConsumption
  WrongPage
  PageLimit
  RowLimit
  Page(QueryPageIssue)
} derive(Eq, Debug)

///|
/// One query and its locator chain. A new query is a new observation, even
/// when it uses the same projection after an interrupted read.
pub struct QueryRead {
  plan : ReadProjection
  api_version : String
  page_limits : QueryPageLimits
  max_pages : Int
  max_total_rows : Int64
  mut next_path : String?
  mut pending_page : QueryPage?
  mut pending_source : QueryResponseSource?
  mut page_count : Int
  mut row_count : Int64
  mut interrupted : Bool
}

///|
fn query_read_initial_path(
  plan : ReadProjection,
  api_version : String,
) -> Result[String, QueryReadIssue] {
  let out = StringBuilder()
  out.write_string("/services/data/")
  out.write_string(api_version)
  out.write_string("/query?q=")
  for character in plan.soql.iter() {
    if (character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      (character >= '0' && character <= '9') ||
      character == '_' {
      out.write_char(character)
    } else if character == ' ' {
      out.write_string("%20")
    } else if character == ',' {
      out.write_string("%2C")
    } else if character == '=' {
      out.write_string("%3D")
    } else if character == '<' {
      out.write_string("%3C")
    } else if character == '>' {
      out.write_string("%3E")
    } else if character == '-' {
      out.write_string("%2D")
    } else {
      return Err(InvalidQuery)
    }
  }
  Ok(out.to_string())
}

///|
pub fn begin_query_read(
  plan : ReadProjection,
  api_version : String,
  page_limits : QueryPageLimits,
  max_pages : Int,
  max_total_rows : Int64,
) -> Result[QueryRead, QueryReadIssue] {
  if !query_api_version_valid(api_version) ||
    page_limits.max_bytes <= 0 ||
    page_limits.max_nodes <= 0 ||
    page_limits.max_depth <= 0 ||
    page_limits.max_rows <= 0 ||
    page_limits.max_locator_units <= 0 ||
    max_pages <= 0 ||
    max_total_rows < 0L {
    return Err(InvalidLimits)
  }
  let initial = match query_read_initial_path(plan, api_version) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    plan,
    api_version,
    page_limits,
    max_pages,
    max_total_rows,
    next_path: Some(initial),
    pending_page: None,
    pending_source: None,
    page_count: 0,
    row_count: 0L,
    interrupted: false,
  })
}

///|
pub fn query_read_next_path(
  read : QueryRead,
) -> Result[String?, QueryReadIssue] {
  if read.interrupted {
    return Err(Interrupted)
  }
  if read.pending_page is Some(_) || read.pending_source is Some(_) {
    return Ok(None)
  }
  if read.next_path is Some(_) && read.page_count >= read.max_pages {
    read.interrupted = true
    read.next_path = None
    return Err(PageLimit)
  }
  Ok(read.next_path)
}

///|
/// The path must be the one previously issued by this state owner. A failed
/// physical request must interrupt the read, not restart its initial query.
pub fn query_read_accept_page(
  read : QueryRead,
  requested_path : String,
  bytes : Bytes,
) -> Result[QueryPage, QueryReadIssue] {
  if read.interrupted {
    return Err(Interrupted)
  }
  if read.pending_page is Some(_) {
    return Err(PageAwaitingConsumption)
  }
  let path = match read.next_path {
    Some(value) => value
    None => return Err(AlreadyFinished)
  }
  if requested_path != path {
    read.interrupted = true
    read.next_path = None
    return Err(WrongRequest)
  }
  if read.page_count >= read.max_pages {
    read.interrupted = true
    read.next_path = None
    return Err(PageLimit)
  }
  let parser = match read.pending_source {
    None => None
    Some(original) => {
      if !physical_equal(original.bytes, bytes) ||
        original.path != requested_path ||
        original.digest != @sha.hex(bytes) {
        ignore(interrupt_query_read(read))
        return Err(WrongPage)
      }
      let parser = match @source.take_json_source_parser(original.preflight) {
        Ok(parser) => parser
        Err(_) => {
          ignore(interrupt_query_read(read))
          return Err(WrongPage)
        }
      }
      read.pending_source = None
      Some(parser)
    }
  }
  let page = match
    project_query_page_with_original_parser(
      bytes,
      read.plan,
      read.api_version,
      read.page_limits,
      parser,
    ) {
    Ok(value) => value
    Err(issue) => {
      read.interrupted = true
      read.next_path = None
      return Err(Page(issue))
    }
  }
  let page_rows = page.rows.length().to_int64()
  if page_rows > read.max_total_rows - read.row_count {
    read.interrupted = true
    read.next_path = None
    return Err(RowLimit)
  }
  read.pending_page = Some(page)
  Ok(page)
}

///|
/// A page becomes part of this observation only after its consumer has
/// accepted the typed values. The pending page blocks further physical I/O.
pub fn acknowledge_query_page(
  read : QueryRead,
  page : QueryPage,
) -> Result[Unit, QueryReadIssue] {
  if read.interrupted {
    return Err(Interrupted)
  }
  guard read.pending_page is Some(pending) else { return Err(AlreadyFinished) }
  if !physical_equal(pending, page) {
    return Err(WrongPage)
  }
  read.page_count += 1
  read.row_count += page.rows.length().to_int64()
  read.next_path = page.next_url
  read.pending_page = None
  Ok(())
}

///|
pub fn interrupt_query_read(read : QueryRead) -> Bool {
  if read.interrupted || (read.next_path is None && read.pending_page is None) {
    return false
  }
  read.interrupted = true
  read.next_path = None
  read.pending_page = None
  if read.pending_source is Some(original) {
    @source.cancel_json_source_preflight(original.preflight)
    read.pending_source = None
  }
  true
}

///|
pub fn query_read_complete(read : QueryRead) -> Bool {
  !read.interrupted &&
  read.page_count > 0 &&
  read.next_path is None &&
  read.pending_page is None
}

///|
pub fn query_read_page_count(read : QueryRead) -> Int {
  read.page_count
}

///|
pub fn query_read_row_count(read : QueryRead) -> Int64 {
  read.row_count
}

///|
// Staging custody belongs to the existing QueryRead. No page or successful
// parse exists until its original reservation grows and the same cursor runs.
struct QueryResponseSource {
  bytes : Bytes
  path : String
  digest : String
  preflight : @source.JsonSourcePreflight
  mut geometry : @source.JsonSourceGeometry?
}

///|
/// Observe original wire geometry before grammar construction. Original parser
/// rejection limits remain unchanged; a copied body cannot consume the cursor.
pub fn prepare_query_read_response(
  read : QueryRead,
  path : String,
  bytes : Bytes,
) -> Result[@source.JsonSourceGeometry, QueryReadIssue] {
  if read.interrupted {
    return Err(Interrupted)
  }
  if read.pending_page is Some(_) {
    return Err(PageAwaitingConsumption)
  }
  if read.next_path != Some(path) {
    return Err(WrongRequest)
  }
  if read.page_count >= read.max_pages {
    return Err(PageLimit)
  }
  let original = match read.pending_source {
    Some(original) => {
      if !physical_equal(original.bytes, bytes) ||
        original.path != path ||
        original.digest != @sha.hex(bytes) {
        return Err(WrongPage)
      }
      original
    }
    None => {
      if bytes.length() > read.page_limits.max_bytes {
        return Err(Page(BudgetExceeded))
      }
      let text = @utf8.decode(bytes[:], ignore_bom=false) catch {
        _ => return Err(Page(InvalidResponse))
      }
      let preflight = match
        @source.start_json_source_preflight(
          text,
          {
            max_input_bytes: read.page_limits.max_bytes,
            max_nodes: read.page_limits.max_nodes,
            max_depth: read.page_limits.max_depth,
          },
          data_keys=true,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Page(query_source_issue(issue)))
      }
      let original : QueryResponseSource = {
        bytes,
        path,
        digest: @sha.hex(bytes),
        preflight,
        geometry: None,
      }
      // Retain before the fallible scan. Interruption always retires this same
      // preflight; it never rebuilds a handle or acknowledges a physical body.
      read.pending_source = Some(original)
      original
    }
  }
  if original.geometry is Some(geometry) {
    return Ok(geometry)
  }
  for tick = 0 {
    match @source.advance_json_source_preflight(original.preflight, 4096) {
      Ok(JsonSourceContinue(..)) => continue tick + 1
      Ok(JsonSourceReady(geometry, ..)) => {
        original.geometry = Some(geometry)
        break Ok(geometry)
      }
      Ok(JsonSourceFailed(issue, ..)) => {
        ignore(interrupt_query_read(read))
        return Err(Page(query_source_issue(issue)))
      }
      Err(_) => {
        ignore(interrupt_query_read(read))
        return Err(WrongPage)
      }
    }
  }
}

///|
/// Pure constructor DATA from this original checked projection. Multipicklist
/// decoding may create one Value per separator, including rejected prefixes;
/// ordinary scalar/compound fields do not turn string length into node count.
pub fn query_read_response_value_node_bound(
  read : QueryRead,
  geometry : @source.JsonSourceGeometry,
) -> Int {
  let extra = if read.plan.fields.any(field => {
      field.native_type == "multipicklist"
    }) {
    geometry.quoted_raw_utf16_units.to_int64()
  } else {
    0L
  }
  let (components, _) = address_component_role_bounds()
  // A malformed/missing nullable field can construct a Null not present in
  // the wire. Bound all such fields and compound roles for every observed
  // Object, without claiming that any Object is a valid query record.
  let missing = geometry.objects.to_int64() *
    read.plan.fields.length().to_int64() *
    (components.to_int64() + 1L)
  Int64::min(
    read.page_limits.max_nodes.to_int64(),
    geometry.node_upper.to_int64() + missing + extra,
  ).to_int()
}

///|
pub fn query_read_response_columns(read : QueryRead) -> Int {
  read.plan.fields.length()
}
