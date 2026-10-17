///|
/// Structural admission bounds, not a physical reservation or installation.
pub(all) struct NotionDatabaseLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_data_sources : Int
  max_properties : Int
  max_identity_bytes : Int
  max_name_bytes : Int
}

///|
pub(all) enum NotionDatabaseIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  InvalidIdentity
  DuplicateIdentity
  InvalidSelection
  ForeignDatabase
  InvalidProperty(String)
} derive(Eq, Debug)

///|
/// Original database discovery only. No implicit first-table selection, token,
/// permission, logical Contract or current installation is issued here.
pub struct NotionDatabaseCatalog {
  id : String
  response_sha256 : String
  priv original : @decode.Cursor
  priv sources : Array[(String, String)]
  priv raw : Bytes
}

///|
/// A property definition remains ordinary vendor DATA until its own typed
/// projection admits it. Its kind/name never supplies a Ref or write grant.
pub struct NotionPropertyMetadata {
  id : String
  name : String
  kind : String
  priv definition : @decode.Cursor
}

///|
/// Retains this exact database observation and selected occurrence, not merely
/// matching ids or response hashes. Physical issuer/current checks are separate.
pub struct NotionDataSourceCatalog {
  id : String
  response_sha256 : String
  priv database : NotionDatabaseCatalog
  priv source_index : Int
  priv original : @decode.Cursor
  priv properties : Array[NotionPropertyMetadata]
  priv raw : Bytes
}

///|
fn database_limits_valid(limits : NotionDatabaseLimits) -> Bool {
  limits.max_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_data_sources >= 0 &&
  limits.max_properties >= 0 &&
  limits.max_identity_bytes > 0 &&
  limits.max_name_bytes >= 0
}

///|
fn database_cursor(
  bytes : Bytes,
  limits : NotionDatabaseLimits,
) -> Result[@decode.Cursor, NotionDatabaseIssue] {
  if !database_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let source = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  match
    @decode.admit(source, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => Ok(value)
    Err(issue) =>
      Err(
        if issue.kind == @decode.BudgetExceeded {
          BudgetExceeded
        } else {
          InvalidResponse
        },
      )
  }
}

///|
fn metadata_text(
  cursor : @decode.Cursor,
  max_bytes : Int,
  nonempty : Bool,
) -> Result[String, NotionDatabaseIssue] {
  guard @decode.text(cursor) is Ok(text) else { return Err(InvalidResponse) }
  if nonempty && text.is_empty() {
    return Err(InvalidIdentity)
  }
  match
    @admitted.admit_usage(
      @contract.primitive(@contract.StringType, nullable=false),
      cursor,
      { max_nodes: 1, max_depth: 1, max_text_bytes: max_bytes, },
    ) {
    Ok(_) => Ok(text)
    Err(_) => Err(BudgetExceeded)
  }
}

///|
pub fn project_notion_database(
  bytes : Bytes,
  limits : NotionDatabaseLimits,
) -> Result[NotionDatabaseCatalog, NotionDatabaseIssue] {
  if !database_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  // Retain the exact provider response independently of a mutable caller
  // Buffer. Decoded values/spans or an equal hash cannot recreate these bytes.
  let raw = Bytes::makei(bytes.length(), index => bytes[index])
  let original = match database_cursor(raw, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.open_object(original) is Ok(root) &&
    text_is(root, "object", "database") &&
    @decode.lookup(root, "id") is Some(id) &&
    @decode.lookup(root, "data_sources") is Some(sources) &&
    @decode.array_length(sources) is Some(count) else {
    return Err(InvalidResponse)
  }
  let id = match metadata_text(id, limits.max_identity_bytes, true) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if count > limits.max_data_sources {
    return Err(BudgetExceeded)
  }
  let selected = []
  let seen : Map[String, Bool] = Map([])
  for index in 0..<count {
    guard @decode.open_object(@decode.element_at(sources, index).unwrap())
      is Ok(entry) &&
      @decode.lookup(entry, "id") is Some(source_id) &&
      @decode.lookup(entry, "name") is Some(name) else {
      return Err(InvalidResponse)
    }
    let source_id = match
      metadata_text(source_id, limits.max_identity_bytes, true) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let name = match metadata_text(name, limits.max_name_bytes, false) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if seen.contains(source_id) {
      return Err(DuplicateIdentity)
    }
    seen[source_id] = true
    selected.push((source_id, name))
  }
  Ok({ id, response_sha256: @sha.hex(raw), original, sources: selected, raw, })
}

///|
pub fn notion_database_source_count(value : NotionDatabaseCatalog) -> Int {
  value.sources.length()
}

///|
pub fn notion_database_original(
  value : NotionDatabaseCatalog,
) -> @decode.Cursor {
  value.original
}

///|
/// Scalar pair copied out of the original inventory. Duplicate display names
/// are valid and are not selectors. No mutable backing array escapes.
pub fn notion_database_source_at(
  value : NotionDatabaseCatalog,
  index : Int,
) -> (String, String)? {
  if index < 0 || index >= value.sources.length() {
    None
  } else {
    Some(value.sources[index])
  }
}

///|
pub fn project_notion_data_source(
  database : NotionDatabaseCatalog,
  source_index : Int,
  bytes : Bytes,
  limits : NotionDatabaseLimits,
) -> Result[NotionDataSourceCatalog, NotionDatabaseIssue] {
  if !database_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  guard notion_database_source_at(database, source_index) is Some((selected, _)) else {
    return Err(InvalidSelection)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  // Retain the exact provider response independently of a mutable caller
  // Buffer. Decoded values/spans or an equal hash cannot recreate these bytes.
  let raw = Bytes::makei(bytes.length(), index => bytes[index])
  let original = match database_cursor(raw, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.open_object(original) is Ok(root) &&
    text_is(root, "object", "data_source") &&
    @decode.lookup(root, "id") is Some(id) &&
    @decode.lookup(root, "parent") is Some(parent) &&
    @decode.open_object(parent) is Ok(parent_view) &&
    @decode.lookup(parent_view, "database_id") is Some(database_id) &&
    @decode.lookup(root, "properties") is Some(properties) &&
    @decode.object_length(properties) is Some(count) else {
    return Err(InvalidResponse)
  }
  let id = match metadata_text(id, limits.max_identity_bytes, true) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let database_id = match
    metadata_text(database_id, limits.max_identity_bytes, true) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if id != selected || database_id != database.id {
    return Err(ForeignDatabase)
  }
  // Externally synced sources may have another data source as their direct
  // parent. Its containing database must still be the exact selected database.
  if !text_is(parent_view, "type", "database_id") {
    guard text_is(parent_view, "type", "data_source_id") &&
      @decode.lookup(parent_view, "data_source_id") is Some(parent_id) else {
      return Err(InvalidResponse)
    }
    match metadata_text(parent_id, limits.max_identity_bytes, true) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  if count > limits.max_properties {
    return Err(BudgetExceeded)
  }
  let fields = []
  let seen : Map[String, Bool] = Map([])
  for index in 0..<count {
    let (name, definition) = @decode.field_at(properties, index).unwrap()
    guard @decode.open_object(definition) is Ok(field) &&
      @decode.lookup(field, "name") is Some(declared_name) &&
      @decode.lookup(field, "id") is Some(property_id) &&
      @decode.lookup(field, "type") is Some(kind) else {
      return Err(InvalidProperty(name))
    }
    let declared_name = match
      metadata_text(declared_name, limits.max_name_bytes, false) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let property_id = match
      metadata_text(property_id, limits.max_identity_bytes, true) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let kind = match metadata_text(kind, limits.max_name_bytes, true) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard declared_name == name &&
      @decode.lookup(field, kind) is Some(body) &&
      @decode.open_object(body) is Ok(_) else {
      return Err(InvalidProperty(name))
    }
    if seen.contains(property_id) {
      return Err(DuplicateIdentity)
    }
    seen[property_id] = true
    fields.push({ id: property_id, name, kind, definition, })
  }
  Ok({
    id,
    response_sha256: @sha.hex(raw),
    database,
    source_index,
    original,
    properties: fields,
    raw,
  })
}

///|
pub fn notion_data_source_database(
  value : NotionDataSourceCatalog,
) -> NotionDatabaseCatalog {
  value.database
}

///|
pub fn notion_data_source_matches_database(
  value : NotionDataSourceCatalog,
  database : NotionDatabaseCatalog,
) -> Bool {
  physical_equal(value.database, database)
}

///|
pub fn notion_data_source_selected_index(
  value : NotionDataSourceCatalog,
) -> Int {
  value.source_index
}

///|
pub fn notion_data_source_original(
  value : NotionDataSourceCatalog,
) -> @decode.Cursor {
  value.original
}

///|
pub fn notion_data_source_property_count(
  value : NotionDataSourceCatalog,
) -> Int {
  value.properties.length()
}

///|
pub fn notion_data_source_property_at(
  value : NotionDataSourceCatalog,
  index : Int,
) -> NotionPropertyMetadata? {
  if index < 0 || index >= value.properties.length() {
    None
  } else {
    Some(value.properties[index])
  }
}

///|
/// Ordinary immutable vendor DATA; not an admitted ActQL ValueContract.
pub fn notion_property_definition(
  value : NotionPropertyMetadata,
) -> @decode.Cursor {
  value.definition
}

///|
/// Bounded ordinary metadata projection; not a logical schema or installation.
pub fn notion_database_metadata_wire(
  value : NotionDatabaseCatalog,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, NotionDatabaseIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "databaseId")
    @encode.string_value(writer, value.id)
    @encode.key(writer, "dataSources")
    @encode.begin_array(writer)
    for (id, name) in value.sources {
      @encode.begin_object(writer)
      @encode.key(writer, "id")
      @encode.string_value(writer, id)
      @encode.key(writer, "name")
      @encode.string_value(writer, name)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
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
pub fn notion_data_source_metadata_wire(
  value : NotionDataSourceCatalog,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, NotionDatabaseIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "databaseId")
    @encode.string_value(writer, value.database.id)
    @encode.key(writer, "dataSourceId")
    @encode.string_value(writer, value.id)
    @encode.key(writer, "properties")
    @encode.begin_array(writer)
    for field in value.properties {
      @encode.begin_object(writer)
      @encode.key(writer, "id")
      @encode.string_value(writer, field.id)
      @encode.key(writer, "name")
      @encode.string_value(writer, field.name)
      @encode.key(writer, "type")
      @encode.string_value(writer, field.kind)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}
