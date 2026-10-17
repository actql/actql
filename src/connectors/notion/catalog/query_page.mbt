///|
pub(all) struct NotionQueryLimits {
  metadata : NotionDatabaseLimits
  max_rows : Int
  max_cursor_bytes : Int
}

///|
pub(all) enum NotionQueryIssue {
  InvalidLimits
  BudgetExceeded
  Metadata(NotionDatabaseIssue)
  InvalidResponse
  InvalidCursor
  DuplicatePage(String)
  ForeignSource(String)
  SchemaChanged(String)
  InvalidProperty(String)
  UnsupportedEntry(String)
} derive(Eq, Debug)

///|
/// Vendor DATA under the original property, not an admitted logical cell,
/// Content/Resource reference, complete paginated value or write target.
pub struct OriginalNotionProperty {
  metadata : NotionPropertyMetadata
  priv original : @decode.Cursor
  priv value : @decode.Cursor
  priv raw : Bytes
}

///|
pub struct OriginalNotionQueryRow {
  id : String
  priv source : NotionDataSourceCatalog
  priv original : @decode.Cursor
  priv properties : Array[OriginalNotionProperty]
}

///|
/// One original response is not complete acquisition, typed rows or physical
/// retirement. The consuming same-site acquisition retains those obligations.
pub struct OriginalNotionQueryPage {
  response_sha256 : String
  next_cursor : String?
  priv source : NotionDataSourceCatalog
  priv original : @decode.Cursor
  priv rows : Array[OriginalNotionQueryRow]
  priv raw : Bytes
}

///|
fn query_metadata_text(
  cursor : @decode.Cursor,
  max_bytes : Int,
) -> Result[String, NotionQueryIssue] {
  match metadata_text(cursor, max_bytes, true) {
    Ok(value) => Ok(value)
    Err(BudgetExceeded) => Err(BudgetExceeded)
    Err(_) => Err(InvalidResponse)
  }
}

///|
fn original_query_row(
  source : NotionDataSourceCatalog,
  original : @decode.Cursor,
  raw : Bytes,
  limits : NotionQueryLimits,
) -> Result[OriginalNotionQueryRow, NotionQueryIssue] {
  guard @decode.open_object(original) is Ok(row) &&
    @decode.lookup(row, "object") is Some(kind) &&
    @decode.text(kind) is Ok(kind) else {
    return Err(InvalidResponse)
  }
  if kind != "page" {
    return Err(UnsupportedEntry(kind))
  }
  guard @decode.lookup(row, "id") is Some(id) else {
    return Err(InvalidResponse)
  }
  let id = match query_metadata_text(id, limits.metadata.max_identity_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.lookup(row, "parent") is Some(parent) &&
    @decode.open_object(parent) is Ok(parent) &&
    text_is(parent, "type", "data_source_id") &&
    @decode.lookup(parent, "data_source_id") is Some(source_id) &&
    @decode.text(source_id) == Ok(source.id) else {
    return Err(ForeignSource(id))
  }
  // Some response forms also identify the containing database. When supplied,
  // it must describe this same selected source's original database.
  match @decode.field(parent, "database_id") {
    Missing => ()
    Present(value) if @decode.text(value) == Ok(source.database.id) => ()
    _ => return Err(ForeignSource(id))
  }
  guard @decode.lookup(row, "properties") is Some(properties) &&
    @decode.open_object(properties) is Ok(property_object) &&
    @decode.object_length(properties) == Some(source.properties.length()) else {
    return Err(SchemaChanged(id))
  }
  if source.properties.length() > limits.metadata.max_properties {
    return Err(BudgetExceeded)
  }
  let selected = []
  for metadata in source.properties {
    guard @decode.lookup(property_object, metadata.name) is Some(original) &&
      @decode.open_object(original) is Ok(property) &&
      @decode.lookup(property, "id") is Some(property_id) &&
      @decode.text(property_id) == Ok(metadata.id) &&
      text_is(property, "type", metadata.kind) &&
      @decode.lookup(property, metadata.kind) is Some(value) else {
      return Err(InvalidProperty(metadata.name))
    }
    // Preserve present null, full native discriminants, and truncation flags.
    // They still require the original logical contract and property-item
    // completion before any value is admitted/captured as a Source row.
    selected.push({ metadata, original, value, raw, })
  }
  Ok({ id, source, original, properties: selected, })
}

///|
pub fn project_notion_query_page(
  source : NotionDataSourceCatalog,
  bytes : Bytes,
  limits : NotionQueryLimits,
) -> Result[OriginalNotionQueryPage, NotionQueryIssue] {
  if !database_limits_valid(limits.metadata) ||
    limits.max_rows < 0 ||
    limits.max_cursor_bytes <= 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.metadata.max_bytes {
    return Err(BudgetExceeded)
  }
  // One bounded independent snapshot: later Decimal admission uses its exact
  // token, never a rounded Double or reconstructed numeric spelling.
  let raw = Bytes::makei(bytes.length(), index => bytes[index])
  let original = match database_cursor(raw, limits.metadata) {
    Ok(value) => value
    Err(BudgetExceeded) => return Err(BudgetExceeded)
    Err(issue) => return Err(Metadata(issue))
  }
  guard @decode.open_object(original) is Ok(root) &&
    text_is(root, "object", "list") &&
    text_is(root, "type", "page_or_data_source") &&
    @decode.lookup(root, "page_or_data_source") is Some(details) &&
    @decode.open_object(details) is Ok(_) &&
    @decode.lookup(root, "results") is Some(results) &&
    @decode.array_length(results) is Some(count) &&
    @decode.lookup(root, "has_more") is Some(has_more) &&
    @decode.boolean(has_more) is Ok(has_more) else {
    return Err(InvalidResponse)
  }
  if count > 100 {
    return Err(InvalidResponse)
  }
  if count > limits.max_rows {
    return Err(BudgetExceeded)
  }
  let next_cursor = match @decode.field(root, "next_cursor") {
    ExplicitNull if !has_more => None
    Present(value) if has_more =>
      match query_metadata_text(value, limits.max_cursor_bytes) {
        Ok(cursor) => Some(cursor)
        Err(BudgetExceeded) => return Err(BudgetExceeded)
        Err(_) => return Err(InvalidCursor)
      }
    _ => return Err(InvalidCursor)
  }
  let rows = []
  let seen : Map[String, Bool] = Map([])
  for index in 0..<count {
    let row = match
      original_query_row(
        source,
        @decode.element_at(results, index).unwrap(),
        raw,
        limits,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if seen.contains(row.id) {
      return Err(DuplicatePage(row.id))
    }
    seen[row.id] = true
    rows.push(row)
  }
  Ok({
    source,
    original,
    rows,
    next_cursor,
    response_sha256: @sha.hex(raw),
    raw,
  })
}

///|
pub fn notion_query_page_matches_source(
  page : OriginalNotionQueryPage,
  source : NotionDataSourceCatalog,
) -> Bool {
  physical_equal(page.source, source)
}

///|
pub fn notion_query_page_source(
  page : OriginalNotionQueryPage,
) -> NotionDataSourceCatalog {
  page.source
}

///|
pub fn notion_query_page_original(
  page : OriginalNotionQueryPage,
) -> @decode.Cursor {
  page.original
}

///|
pub fn notion_query_page_row_count(page : OriginalNotionQueryPage) -> Int {
  page.rows.length()
}

///|
pub fn notion_query_page_row_at(
  page : OriginalNotionQueryPage,
  index : Int,
) -> OriginalNotionQueryRow? {
  if index < 0 || index >= page.rows.length() {
    None
  } else {
    Some(page.rows[index])
  }
}

///|
pub fn notion_query_row_matches_source(
  row : OriginalNotionQueryRow,
  source : NotionDataSourceCatalog,
) -> Bool {
  physical_equal(row.source, source)
}

///|
pub fn notion_query_row_original(
  row : OriginalNotionQueryRow,
) -> @decode.Cursor {
  row.original
}

///|
pub fn notion_query_row_property_count(row : OriginalNotionQueryRow) -> Int {
  row.properties.length()
}

///|
pub fn notion_query_row_property_at(
  row : OriginalNotionQueryRow,
  index : Int,
) -> OriginalNotionProperty? {
  if index < 0 || index >= row.properties.length() {
    None
  } else {
    Some(row.properties[index])
  }
}

///|
pub fn notion_query_property_original(
  value : OriginalNotionProperty,
) -> @decode.Cursor {
  value.original
}

///|
pub fn notion_query_property_value(
  value : OriginalNotionProperty,
) -> @decode.Cursor {
  value.value
}

///|
pub fn notion_query_page_metadata_wire(
  page : OriginalNotionQueryPage,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, NotionQueryIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "ids")
    @encode.begin_array(writer)
    for row in page.rows {
      @encode.string_value(writer, row.id)
    }
    @encode.end_array(writer)
    @encode.key(writer, "nextCursor")
    match page.next_cursor {
      Some(cursor) => @encode.string_value(writer, cursor)
      None => @encode.null_value(writer)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}

///|
/// Exact ordinary JSON token, including original number digits/exponent. This
/// String is data, not a logical Value or physical response retirement receipt.
pub fn notion_query_property_value_json(
  value : OriginalNotionProperty,
  max_bytes : Int,
) -> Result[String, NotionQueryIssue] {
  if max_bytes <= 0 {
    return Err(InvalidLimits)
  }
  let span = @decode.cursor_span(value.value)
  if span.start_byte < 0 ||
    span.end_byte < span.start_byte ||
    span.end_byte > value.raw.length() {
    return Err(InvalidResponse)
  }
  if span.end_byte - span.start_byte > max_bytes {
    return Err(BudgetExceeded)
  }
  Ok(@utf8.decode(value.raw[span.start_byte:span.end_byte])) catch {
    _ => Err(InvalidResponse)
  }
}

///|
pub fn notion_query_page_original_json(
  page : OriginalNotionQueryPage,
  max_bytes : Int,
) -> Result[String, NotionQueryIssue] {
  if max_bytes <= 0 {
    return Err(InvalidLimits)
  }
  if page.raw.length() > max_bytes {
    return Err(BudgetExceeded)
  }
  Ok(@utf8.decode(page.raw)) catch {
    _ => Err(InvalidResponse)
  }
}
