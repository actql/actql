///|
/// Provider-neutral envelope DATA. The original RowRun separately admits the
/// complete row objects under its declared schema and owns physical charges.
struct RowSourceJsonPage {
  rows_wire : String
  original : RowSourceProjectedJsonPage
}

///|
/// The same parsed external rows, before schema admission. No mutable source
/// tree or response bytes escape this opaque page. Its RowRun still validates
/// the whole selected array under the original input schema and page limits.
struct RowSourceProjectedJsonPage {
  origin : Ref[Unit]
  rows : @source.Node
  rows_bytes : Int
  row_count : Int
  next_cursor : String?
}

///|
/// Namespace identity is DATA provenance, not an admission or Resource owner.
let projected_json_page_origin : Ref[Unit] = Ref(())

///|
pub(all) enum RowSourceJsonPageIssue {
  InvalidLimits
  InvalidPage
  InvalidItems
  InvalidCursor
  NoNextCursor
} derive(Eq, Debug)

///|
fn json_page_path(
  root : @source.Node,
  path : Array[String],
) -> Result[@source.Node?, RowSourceJsonPageIssue] {
  let mut current = root
  for name in path {
    match current.value {
      @source.Null => return Ok(None)
      @source.Object(fields) => {
        let mut found = None
        for field in fields {
          if field.key == name {
            found = Some(field.value)
            break
          }
        }
        match found {
          Some(value) => current = value
          None => return Ok(None)
        }
      }
      _ => return Err(InvalidPage)
    }
  }
  Ok(Some(current))
}

///|
/// Validate the whole original document before selecting any output. Its
/// array span preserves numeric tokens, whitespace, keys and literal values;
/// no parser Double is converted back to a number or a row value here.
pub fn project_row_source_json_page(
  bytes : Bytes,
  items_path : Array[String],
  cursor_present : Bool,
  cursor_path : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_cursor_bytes : Int,
) -> Result[RowSourceJsonPage, RowSourceJsonPageIssue] {
  let original = match
    project_row_source_typed_json_page(
      bytes, items_path, cursor_present, cursor_path, max_bytes, max_nodes, max_depth,
      max_rows, max_cursor_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let span = original.rows.span
  let rows_wire = @utf8.decode(bytes[span.start_byte:span.end_byte]) catch {
    _ => return Err(InvalidPage)
  }
  Ok({ rows_wire, original, })
}

///|
/// Parse once without encoding the selected array. The provider envelope and
/// cursor use the same parser and bounds as the wire projection above.
pub fn project_row_source_typed_json_page(
  bytes : Bytes,
  items_path : Array[String],
  cursor_present : Bool,
  cursor_path : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_cursor_bytes : Int,
) -> Result[RowSourceProjectedJsonPage, RowSourceJsonPageIssue] {
  if max_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    max_rows < 0 ||
    max_cursor_bytes < 0 ||
    items_path.length() > max_depth ||
    cursor_path.length() > max_depth ||
    (!cursor_present && !cursor_path.is_empty()) {
    return Err(InvalidLimits)
  }
  for path in [items_path, cursor_path] {
    for name in path {
      if @scalar.admit_utf8_length(name, max_bytes) is Err(_) {
        return Err(InvalidLimits)
      }
    }
  }
  let root = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    }) {
    Err(_) => return Err(InvalidPage)
    Ok(value) => value
  }
  guard json_page_path(root, items_path) is Ok(Some(selected)) &&
    selected.value is @source.Array(rows) &&
    rows.length() <= max_rows else {
    return Err(InvalidItems)
  }
  for row in rows {
    if !(row.value is @source.Object(_)) {
      return Err(InvalidItems)
    }
  }
  let cursor = if cursor_present {
    match json_page_path(root, cursor_path) {
      Ok(None) => None
      Ok(Some({ value: @source.Null, .. })) => None
      Ok(Some({ value: @source.String(text), .. })) => {
        if @scalar.admit_utf8_length(text, max_cursor_bytes) is Err(_) {
          return Err(InvalidCursor)
        }
        Some(text)
      }
      _ => return Err(InvalidCursor)
    }
  } else {
    None
  }
  let span = selected.span
  if span.start_byte < 0 ||
    span.end_byte <= span.start_byte ||
    span.end_byte > bytes.length() {
    return Err(InvalidPage)
  }
  Ok({
    origin: projected_json_page_origin,
    rows: selected,
    rows_bytes: span.end_byte - span.start_byte,
    row_count: rows.length(),
    next_cursor: cursor,
  })
}

///|
pub fn row_source_json_page_rows_wire(value : RowSourceJsonPage) -> String {
  value.rows_wire
}

///|
pub fn row_source_json_page_row_count(value : RowSourceJsonPage) -> Int {
  value.original.row_count
}

///|
pub fn row_source_json_page_has_next_cursor(value : RowSourceJsonPage) -> Bool {
  value.original.next_cursor is Some(_)
}

///|
pub fn row_source_json_page_next_cursor(
  value : RowSourceJsonPage,
) -> Result[String, RowSourceJsonPageIssue] {
  match value.original.next_cursor {
    Some(text) => Ok(text)
    None => Err(NoNextCursor)
  }
}

///|
pub fn row_source_json_page_original(
  value : RowSourceJsonPage,
) -> RowSourceProjectedJsonPage {
  value.original
}

///|
pub fn row_source_typed_json_page_row_count(
  value : RowSourceProjectedJsonPage,
) -> Int {
  value.row_count
}

///|
pub fn row_source_typed_json_page_has_next_cursor(
  value : RowSourceProjectedJsonPage,
) -> Bool {
  value.next_cursor is Some(_)
}

///|
pub fn row_source_typed_json_page_next_cursor(
  value : RowSourceProjectedJsonPage,
) -> Result[String, RowSourceJsonPageIssue] {
  match value.next_cursor {
    Some(text) => Ok(text)
    None => Err(NoNextCursor)
  }
}

///|
/// This is still full row/schema admission. Only the already completed byte
/// parse is reused; no row, field, value, count or retention check is skipped.
fn accept_row_source_projected_page(
  read : RowSourceRead,
  page : RowSourceProjectedJsonPage,
) -> Result[Int, RowSourceIssue] {
  if !read.open {
    return Err(Closed)
  }
  if !physical_equal(page.origin, projected_json_page_origin) {
    return fail_read(read, InvalidPage)
  }
  if read.listing is Some(_) {
    return fail_read(read, ListingProtocol)
  }
  if read.keyed is Some(_) {
    return fail_read(read, KeyedIncomplete)
  }
  let limits = read.page_limits
  guard page.rows_bytes <= limits.max_bytes &&
    @decode.admit(page.rows, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    })
    is Ok(root) &&
    @decode.elements(root) is Ok(items) else {
    return fail_read(read, InvalidPage)
  }
  accept_row_source_items(read, items)
}

///|
/// Reuse the exact parsed page with this attempt's existing response charge.
/// The opaque page supplies DATA only; it cannot issue another charge, permit
/// a foreign ticket or acknowledge physical cleanup.
pub fn accept_charged_row_run_projected_page(
  run : RowRun,
  charge : RowPageCharge,
  page : RowSourceProjectedJsonPage,
) -> Result[Int, RowHostIssue] {
  guard !run.closed && run.attempt.state is Reading(read) else {
    return Err(InvalidState)
  }
  match consume_row_page_charge(run, charge) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if run.configuration is InputConfiguration(_) &&
    run.physical is Some(_) &&
    physical_equal(page.origin, projected_json_page_origin) &&
    page.rows_bytes <= read.page_limits.max_bytes {
    // The original provider still owns the immutable parsed tree. An actual
    // UTF8 JSON span bounds node/field occurrences without parsing it again.
    let nodes = Int::min(page.rows_bytes, read.page_limits.max_nodes)
    match
      fund_row_input_page(
        run,
        read,
        nodes.to_int64(),
        page.rows_bytes.to_int64(),
        page.row_count.to_int64(),
        page.rows_bytes,
        None,
      ) {
      Ok(_) => ()
      Err(issue) => {
        abort_row_run(run)
        return Err(issue)
      }
    }
  }
  match accept_row_source_projected_page(read, page) {
    Ok(count) => Ok(count)
    Err(issue) => {
      abort_row_run(run)
      Err(Source(issue))
    }
  }
}
