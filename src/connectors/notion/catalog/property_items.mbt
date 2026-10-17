///|
/// Bounded response/cursor history; not an installation, grant or reservation.
pub(all) struct NotionPropertyItemLimits {
  metadata : NotionDatabaseLimits
  max_pages : Int
  max_items : Int
  max_total_bytes : Int
  max_total_nodes : Int
  max_total_text_bytes : Int
  max_cursor_bytes : Int
  max_work : Int
}

///|
pub(all) enum NotionPropertyItemIssue {
  InvalidLimits
  BudgetExceeded
  InvalidSelection
  ForeignOriginal
  UnsupportedProperty(String)
  InvalidResponse
  InvalidItem
  InvalidCursor
  RepeatedCursor
  Incomplete
  Admission(@admitted.Issue)
} derive(Eq, Debug)

///|
/// Original row/property occurrence and prior response chain. This DATA request
/// does not authorize its HTTP path; the physical Site must bind its actual
/// operation/result to this same original and current acquisition.
pub struct NotionPropertyItemRequest {
  priv row : OriginalNotionQueryRow
  priv property : OriginalNotionProperty
  priv limits : NotionPropertyItemLimits
  priv cursor : String?
  priv previous : NotionPropertyItemPage?
}

///|
/// Immutable original response chain. Arrays and byte backing never escape.
/// Terminal protocol pagination is not current authority or physical retirement.
pub struct NotionPropertyItemPage {
  priv request : NotionPropertyItemRequest
  priv original : @decode.Cursor
  priv raw : Bytes
  priv items : Array[(@decode.Cursor, String, Int)]
  priv next_cursor : String?
  priv pages : Int
  priv total_items : Int
  priv total_bytes : Int
  priv total_nodes : Int
  priv total_text : Int
  priv value_text_bytes : Int
  priv remaining_work : Int
}

///|
fn property_item_limits_valid(limits : NotionPropertyItemLimits) -> Bool {
  database_limits_valid(limits.metadata) &&
  limits.max_pages > 0 &&
  limits.max_items >= 0 &&
  limits.max_total_bytes > 0 &&
  limits.max_total_nodes > 0 &&
  limits.max_total_text_bytes >= 0 &&
  limits.max_cursor_bytes > 0 &&
  limits.max_work > 0
}

///|
pub fn start_notion_property_item_request(
  row : OriginalNotionQueryRow,
  property_index : Int,
  limits : NotionPropertyItemLimits,
) -> Result[NotionPropertyItemRequest, NotionPropertyItemIssue] {
  if !property_item_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  guard notion_query_row_property_at(row, property_index) is Some(property) else {
    return Err(InvalidSelection)
  }
  if !["title", "rich_text", "people", "relation"].contains(
      property.metadata.kind,
    ) {
    return Err(UnsupportedProperty(property.metadata.kind))
  }
  Ok({ row, property, limits, cursor: None, previous: None, })
}

///|
pub fn notion_property_item_request_matches(
  request : NotionPropertyItemRequest,
  row : OriginalNotionQueryRow,
  property_index : Int,
) -> Bool {
  if !physical_equal(request.row, row) {
    return false
  }
  match notion_query_row_property_at(row, property_index) {
    Some(property) => physical_equal(request.property, property)
    None => false
  }
}

///|
/// The next cursor is opaque. Never follow a vendor-supplied next_url as a new
/// origin, resource scope or grant. The actual caller builds its declared path
/// from this original row/property and sends only the returned cursor value.
pub fn notion_property_item_request_wire(
  request : NotionPropertyItemRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, NotionPropertyItemIssue] {
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "pageId")
    @encode.string_value(writer, request.row.id)
    @encode.key(writer, "propertyId")
    @encode.string_value(writer, request.property.metadata.id)
    @encode.key(writer, "cursor")
    match request.cursor {
      None => @encode.null_value(writer)
      Some(cursor) => @encode.string_value(writer, cursor)
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
fn property_item_value(
  cursor : @decode.Cursor,
  kind : String,
  max_bytes : Int,
) -> Result[(@decode.Cursor, String, Int), NotionPropertyItemIssue] {
  guard @decode.open_object(cursor) is Ok(value) else {
    return Err(InvalidItem)
  }
  let selected = match kind {
    "title" | "rich_text" => {
      guard @decode.lookup(value, "type") is Some(native_kind) &&
        @decode.text(native_kind) is Ok(native_kind) &&
        ["text", "mention", "equation"].contains(native_kind) &&
        @decode.lookup(value, native_kind) is Some(body) &&
        @decode.open_object(body) is Ok(_) &&
        @decode.lookup(value, "plain_text") is Some(text) else {
        return Err(InvalidItem)
      }
      text
    }
    "people" => {
      guard text_is(value, "object", "user") &&
        @decode.lookup(value, "id") is Some(id) else {
        return Err(InvalidItem)
      }
      id
    }
    "relation" => {
      guard @decode.lookup(value, "id") is Some(id) else {
        return Err(InvalidItem)
      }
      id
    }
    _ => return Err(UnsupportedProperty(kind))
  }
  guard @decode.text(selected) is Ok(text) else { return Err(InvalidItem) }
  if (kind == "people" || kind == "relation") && text.is_empty() {
    return Err(InvalidItem)
  }
  match
    @admitted.admit_usage(
      @contract.primitive(@contract.StringType, nullable=false),
      selected,
      { max_nodes: 1, max_depth: 1, max_text_bytes: max_bytes, },
    ) {
    Ok((_, _, text_bytes)) => Ok((selected, text, text_bytes))
    Err(_) => Err(BudgetExceeded)
  }
}

///|
pub fn project_notion_property_item_page(
  request : NotionPropertyItemRequest,
  bytes : Bytes,
) -> Result[NotionPropertyItemPage, NotionPropertyItemIssue] {
  let limits = request.limits
  let (pages, total_items, total_bytes, total_nodes, total_text, work) = match
    request.previous {
    None => (0, 0, 0, 0, 0, limits.max_work)
    Some(previous) =>
      (
        previous.pages,
        previous.total_items,
        previous.total_bytes,
        previous.total_nodes,
        previous.total_text,
        previous.remaining_work,
      )
  }
  if pages >= limits.max_pages ||
    bytes.length() > limits.metadata.max_bytes ||
    bytes.length() > limits.max_total_bytes - total_bytes ||
    bytes.length() > work {
    return Err(BudgetExceeded)
  }
  let mut work = work - bytes.length()
  // An external Buffer mutation cannot change the retained original response.
  let raw = Bytes::makei(bytes.length(), index => bytes[index])
  let original = match database_cursor(raw, limits.metadata) {
    Ok(value) => value
    Err(BudgetExceeded) => return Err(BudgetExceeded)
    Err(_) => return Err(InvalidResponse)
  }
  let usage = @decode.admission_usage(original)
  if usage.nodes > limits.max_total_nodes - total_nodes ||
    usage.total_string_bytes > limits.max_total_text_bytes - total_text ||
    usage.nodes > work {
    return Err(BudgetExceeded)
  }
  work -= usage.nodes
  if usage.total_string_bytes > work {
    return Err(BudgetExceeded)
  }
  work -= usage.total_string_bytes
  guard @decode.open_object(original) is Ok(root) &&
    text_is(root, "object", "list") &&
    text_is(root, "type", "property_item") &&
    @decode.lookup(root, "property_item") is Some(metadata) &&
    @decode.open_object(metadata) is Ok(metadata) &&
    text_is(metadata, "id", request.property.metadata.id) &&
    text_is(metadata, "type", request.property.metadata.kind) &&
    @decode.lookup(metadata, request.property.metadata.kind) is Some(definition) &&
    @decode.open_object(definition) is Ok(_) &&
    @decode.object_length(definition) == Some(0) &&
    @decode.lookup(root, "has_more") is Some(more) &&
    @decode.boolean(more) is Ok(more) &&
    @decode.lookup(root, "results") is Some(results) &&
    @decode.array_length(results) is Some(count) else {
    return Err(InvalidResponse)
  }
  if count > 100 {
    return Err(InvalidResponse)
  }
  if count > limits.max_items - total_items {
    return Err(BudgetExceeded)
  }
  let next_cursor = match @decode.field(root, "next_cursor") {
    ExplicitNull if !more => None
    Present(cursor) if more =>
      match metadata_text(cursor, limits.max_cursor_bytes, true) {
        Ok(text) => Some(text)
        Err(BudgetExceeded) => return Err(BudgetExceeded)
        Err(_) => return Err(InvalidCursor)
      }
    _ => return Err(InvalidCursor)
  }
  match @decode.field(metadata, "next_url") {
    ExplicitNull if !more => ()
    Present(url) if more =>
      match metadata_text(url, limits.metadata.max_bytes, true) {
        Ok(_) => ()
        Err(BudgetExceeded) => return Err(BudgetExceeded)
        Err(_) => return Err(InvalidCursor)
      }
    _ => return Err(InvalidCursor)
  }
  if next_cursor is Some(next) {
    let mut ancestor = request.previous
    while ancestor is Some(previous) {
      let prior = previous.next_cursor
      if prior is Some(cursor) {
        if cursor.length() > work {
          return Err(BudgetExceeded)
        }
        work -= cursor.length()
        if cursor == next {
          return Err(RepeatedCursor)
        }
      }
      if work == 0 {
        return Err(BudgetExceeded)
      }
      work -= 1
      ancestor = previous.request.previous
    }
  }
  let items = []
  let mut value_text_bytes = match request.previous {
    None => 0
    Some(page) => page.value_text_bytes
  }
  for index in 0..<count {
    if work == 0 {
      return Err(BudgetExceeded)
    }
    work -= 1
    let item = @decode.element_at(results, index).unwrap()
    guard @decode.open_object(item) is Ok(item) &&
      text_is(item, "object", "property_item") &&
      text_is(item, "id", request.property.metadata.id) &&
      text_is(item, "type", request.property.metadata.kind) &&
      @decode.lookup(item, request.property.metadata.kind) is Some(value) else {
      return Err(InvalidItem)
    }
    let projected = match
      property_item_value(
        value,
        request.property.metadata.kind,
        limits.metadata.max_bytes,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if projected.1.length() > work {
      return Err(BudgetExceeded)
    }
    work -= projected.1.length()
    // Each item's id is the shared property id, not a unique per-item key.
    // Preserve actual value order and repetitions; do not invent key evidence.
    if projected.2 > limits.max_total_text_bytes - value_text_bytes {
      return Err(BudgetExceeded)
    }
    value_text_bytes += projected.2
    items.push(projected)
  }
  Ok({
    request,
    original,
    raw,
    items,
    next_cursor,
    pages: pages + 1,
    total_items: total_items + count,
    total_bytes: total_bytes + bytes.length(),
    total_nodes: total_nodes + usage.nodes,
    total_text: total_text + usage.total_string_bytes,
    remaining_work: work,
    value_text_bytes,
  })
}

///|
pub fn next_notion_property_item_request(
  page : NotionPropertyItemPage,
) -> NotionPropertyItemRequest? {
  match page.next_cursor {
    None => None
    Some(cursor) =>
      Some({
        row: page.request.row,
        property: page.request.property,
        limits: page.request.limits,
        cursor: Some(cursor),
        previous: Some(page),
      })
  }
}

///|
/// Complete only this original row/property response chain under the same
/// checked Contract. Completion is protocol evidence, never authority or ACK.
pub fn admit_notion_completed_property(
  binding : NotionDataSourceReadContracts,
  terminal : NotionPropertyItemPage,
  column_index : Int,
  limits : @admitted.Limits,
) -> Result[(@admitted.CheckedValue, Int, Int), NotionPropertyItemIssue] {
  if terminal.next_cursor is Some(_) {
    return Err(Incomplete)
  }
  guard notion_data_source_read_column_at(binding, column_index) is Some(column) else {
    return Err(InvalidSelection)
  }
  let request = terminal.request
  if !physical_equal(binding.source, request.row.source) ||
    !physical_equal(column.property, request.property.metadata) ||
    column.projection != Value {
    return Err(ForeignOriginal)
  }
  if limits.max_nodes <= 0 || limits.max_depth <= 0 || limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  if terminal.value_text_bytes > limits.max_text_bytes {
    return Err(BudgetExceeded)
  }
  let kind = request.property.metadata.kind
  if (kind == "title" || kind == "rich_text") && limits.max_nodes < 1 {
    return Err(BudgetExceeded)
  }
  if (kind == "people" || kind == "relation") &&
    terminal.total_items > limits.max_nodes - 1 {
    return Err(BudgetExceeded)
  }
  let mut work = terminal.remaining_work
  let pages = []
  let mut current = Some(terminal)
  while current is Some(page) {
    if pages.length() >= request.limits.max_pages {
      return Err(BudgetExceeded)
    }
    if work == 0 {
      return Err(BudgetExceeded)
    }
    work -= 1
    pages.push(page)
    current = page.request.previous
  }
  let span = @decode.cursor_span(request.property.value)
  let value = if kind == "title" || kind == "rich_text" {
    let output = StringBuilder()
    for index = pages.length() - 1; index >= 0; index = index - 1 {
      for (_, text, _) in pages[index].items {
        if work == 0 {
          return Err(BudgetExceeded)
        }
        work -= 1
        if text.length() > work {
          return Err(BudgetExceeded)
        }
        work -= text.length()
        output.write_string(text)
      }
    }
    @source.String(output.to_string())
  } else {
    let output : Array[@source.Node] = []
    for index = pages.length() - 1; index >= 0; index = index - 1 {
      for (original, text, _) in pages[index].items {
        if work == 0 {
          return Err(BudgetExceeded)
        }
        work -= 1
        if text.length() > work {
          return Err(BudgetExceeded)
        }
        work -= text.length()
        output.push({
          value: @source.String(text),
          span: @decode.cursor_span(original),
        })
      }
    }
    @source.Array(output)
  }
  let cursor = match
    @decode.admit({ value, span, }, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_text_bytes,
      max_total_string_bytes: limits.max_text_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  match @admitted.admit_usage(column.contract, cursor, limits) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Admission(issue))
  }
}

///|
pub fn notion_completed_property_wire(
  binding : NotionDataSourceReadContracts,
  terminal : NotionPropertyItemPage,
  column_index : Int,
  limits : @admitted.Limits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, NotionPropertyItemIssue] {
  let (value, _, _) = match
    admit_notion_completed_property(binding, terminal, column_index, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @admitted.emit_checked_wire_value(value, writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}

///|
pub fn notion_property_item_page_original(
  page : NotionPropertyItemPage,
) -> @decode.Cursor {
  page.original
}

///|
pub fn notion_property_item_page_original_wire(
  page : NotionPropertyItemPage,
  max_bytes : Int,
) -> Result[String, NotionPropertyItemIssue] {
  if max_bytes < page.raw.length() {
    return Err(BudgetExceeded)
  }
  Ok(@utf8.decode(page.raw[:])) catch {
    _ => Err(InvalidResponse)
  }
}

///|
/// Select the exact property occurrence of an original checked column before
/// any physical request. The bounded scan is charged to this same chain.
pub fn start_notion_column_property_item_request(
  binding : NotionDataSourceReadContracts,
  row : OriginalNotionQueryRow,
  column_index : Int,
  limits : NotionPropertyItemLimits,
) -> Result[NotionPropertyItemRequest, NotionPropertyItemIssue] {
  if !property_item_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  guard notion_data_source_read_column_at(binding, column_index) is Some(column) else {
    return Err(InvalidSelection)
  }
  if !physical_equal(row.source, binding.source) || column.projection != Value {
    return Err(ForeignOriginal)
  }
  let mut remaining = limits.max_work
  for index in 0..<row.properties.length() {
    if remaining == 0 {
      return Err(BudgetExceeded)
    }
    remaining -= 1
    if physical_equal(row.properties[index].metadata, column.property) {
      if remaining == 0 {
        return Err(BudgetExceeded)
      }
      return start_notion_property_item_request(row, index, {
        ..limits,
        max_work: remaining,
      })
    }
  }
  Err(ForeignOriginal)
}

///|
pub fn notion_property_item_request_matches_binding(
  request : NotionPropertyItemRequest,
  binding : NotionDataSourceReadContracts,
  column_index : Int,
) -> Bool {
  guard notion_data_source_read_column_at(binding, column_index) is Some(column) else {
    return false
  }
  physical_equal(request.row.source, binding.source) &&
  physical_equal(request.property.metadata, column.property) &&
  column.projection == Value
}

///|
pub fn notion_property_item_page_complete(
  page : NotionPropertyItemPage,
) -> Bool {
  page.next_cursor is None
}
