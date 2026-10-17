///|
/// One bounded original read-material representation. These are structural
/// codec limits, not a phase reservation or installation authority.
pub(all) struct NotionReadSnapshotLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum NotionReadSnapshotIssue {
  InvalidLimits
  BudgetExceeded
  InvalidSnapshot
  ForeignOriginal
  IdentityMismatch
  SchemaMismatch
  Metadata(NotionDatabaseIssue)
  Declaration(NotionReadContractIssue)
} derive(Eq, Debug)

///|
/// The same Catalog originals plus their exact bounded saved representation.
/// Reading this DATA cannot issue a trusted installation, current authority,
/// ResourceRef, Run custody, funding or physical retirement acknowledgement.
pub struct NotionDatabaseReadSnapshot {
  priv original_self : Ref[NotionDatabaseReadSnapshot?]
  priv selection : NotionReadSourceSelection
  priv source : NotionDataSourceCatalog
  priv read_contracts : NotionDataSourceReadContracts
  priv schema_wire : String
  priv schema_cid : String
  priv wire : String
  priv source_cid : String
}

///|
fn read_snapshot_limits_valid(limits : NotionReadSnapshotLimits) -> Bool {
  limits.max_bytes > 0 && limits.max_nodes > 0 && limits.max_depth > 0
}

///|
fn read_snapshot_is_original(snapshot : NotionDatabaseReadSnapshot) -> Bool {
  match snapshot.original_self.val {
    Some(original) => physical_equal(original, snapshot)
    None => false
  }
}

///|
pub fn capture_notion_database_read_snapshot(
  selection : NotionReadSourceSelection,
  source : NotionDataSourceCatalog,
  read_contracts : NotionDataSourceReadContracts,
  limits : NotionReadSnapshotLimits,
) -> Result[NotionDatabaseReadSnapshot, NotionReadSnapshotIssue] {
  if !read_snapshot_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if !physical_equal(selection.database, source.database) ||
    selection.index != source.source_index ||
    !notion_data_source_read_matches(
      read_contracts,
      selection.declaration,
      source,
    ) {
    return Err(ForeignOriginal)
  }
  // Only the existing property-only or full fixed-system binding is saved.
  // A caller Boolean never upgrades a property schema to a public Source.
  let system_columns = !read_contracts.system_columns.is_empty()
  if system_columns && read_contracts.system_columns.length() != 8 {
    return Err(ForeignOriginal)
  }
  let database_wire = match
    notion_database_original_json(selection.database, limits.max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Metadata(issue))
  }
  let declaration_wire = match
    notion_database_read_declaration_original_json(
      selection.declaration,
      limits.max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Declaration(issue))
  }
  let source_wire = match
    notion_data_source_original_json(source, limits.max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Metadata(issue))
  }
  let schema_wire = match
    notion_data_source_read_schema_wire(
      read_contracts,
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Declaration(issue))
  }
  let schema_cid = "sha256:" + @sha.hex(@utf8.encode(schema_wire))
  let writer = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  let wire = try {
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("database_response", database_wire),
        ("declaration_source", declaration_wire),
        ("schema_cid", schema_cid),
        ("schema_wire", schema_wire),
        ("selected_data_source_response", source_wire),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "system_columns")
    @encode.bool_value(writer, system_columns)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-notion-database-read-snapshot/0.1")
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return Err(BudgetExceeded)
    }
  }
  let snapshot : NotionDatabaseReadSnapshot = {
    original_self: Ref(None),
    selection,
    source,
    read_contracts,
    schema_wire,
    schema_cid,
    wire,
    source_cid: "sha256:" + @sha.hex(@utf8.encode(wire)),
  }
  snapshot.original_self.val = Some(snapshot)
  Ok(snapshot)
}

///|
fn read_snapshot_text(
  root : @decode.Cursor,
  key : String,
  max_bytes : Int,
) -> Result[String, NotionReadSnapshotIssue] {
  guard @decode.field(root, key) is Present(value) &&
    @decode.text(value) is Ok(text) else {
    return Err(InvalidSnapshot)
  }
  // Reject the UTF16 lower bound before allocating an encoded copy. The
  // existing admitted Text check separately bounds exact UTF8 and Unicode.
  if text.length() > max_bytes {
    return Err(BudgetExceeded)
  }
  match @admitted.text_value(text, max_bytes) {
    Some(_) => Ok(text)
    None => Err(BudgetExceeded)
  }
}

///|
/// Re-admit only the saved exact metadata/declaration. No current profile,
/// provider request, default resolution or installation adoption occurs here.
pub fn read_notion_database_read_snapshot(
  bytes : Bytes,
  expected_source_cid : String,
  read_limits : NotionReadContractLimits,
  limits : NotionReadSnapshotLimits,
) -> Result[NotionDatabaseReadSnapshot, NotionReadSnapshotIssue] {
  if !read_snapshot_limits_valid(limits) ||
    !read_contract_limits_valid(read_limits) {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let raw = Bytes::makei(bytes.length(), index => bytes[index])
  if expected_source_cid.length() != 71 ||
    expected_source_cid != "sha256:" + @sha.hex(raw) {
    return Err(IdentityMismatch)
  }
  let cursor = match
    database_cursor(raw, {
      ..read_limits.metadata,
      max_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) => return Err(Metadata(issue))
  }
  guard @decode.closed_object(cursor, [
      "database_response", "declaration_source", "schema_cid", "schema_wire", "selected_data_source_response",
      "system_columns", "version",
    ])
    is Ok(_) &&
    @decode.field(cursor, "system_columns") is Present(system) &&
    @decode.boolean(system) is Ok(system_columns) else {
    return Err(InvalidSnapshot)
  }
  let version = match read_snapshot_text(cursor, "version", 64) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if version != "actql-notion-database-read-snapshot/0.1" {
    return Err(InvalidSnapshot)
  }
  let database_wire = match
    read_snapshot_text(
      cursor,
      "database_response",
      read_limits.metadata.max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let declaration_wire = match
    read_snapshot_text(
      cursor,
      "declaration_source",
      read_limits.metadata.max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let source_wire = match
    read_snapshot_text(
      cursor,
      "selected_data_source_response",
      read_limits.metadata.max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let schema_wire = match
    read_snapshot_text(cursor, "schema_wire", limits.max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let schema_cid = match read_snapshot_text(cursor, "schema_cid", 71) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let declaration = match
    read_notion_database_read_declaration(
      @utf8.encode(declaration_wire),
      read_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Declaration(issue))
  }
  let database = match
    project_notion_database(@utf8.encode(database_wire), read_limits.metadata) {
    Ok(value) => value
    Err(issue) => return Err(Metadata(issue))
  }
  let selection = match
    select_notion_read_source(declaration, database, read_limits.max_work) {
    Ok(value) => value
    Err(issue) => return Err(Declaration(issue))
  }
  let source = match
    project_notion_selected_read_source(
      selection,
      @utf8.encode(source_wire),
      read_limits.metadata,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Declaration(issue))
  }
  let properties = match
    bind_notion_selected_read_contracts(selection, source, read_limits) {
    Ok(value) => value
    Err(issue) => return Err(Declaration(issue))
  }
  let read_contracts = if system_columns {
    match with_notion_source_system_contracts(properties, read_limits) {
      Ok(value) => value
      Err(issue) => return Err(Declaration(issue))
    }
  } else {
    properties
  }
  let result = match
    capture_notion_database_read_snapshot(
      selection, source, read_contracts, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if schema_wire != result.schema_wire || schema_cid != result.schema_cid {
    return Err(SchemaMismatch)
  }
  // The complete checked canonical body is the saved preimage. Alternate
  // field order/escaping, missing fields or an equal typed schema are not it.
  if @utf8.encode(result.wire) != raw {
    return Err(InvalidSnapshot)
  }
  Ok(result)
}

///|
pub fn notion_database_read_snapshot_matches(
  snapshot : NotionDatabaseReadSnapshot,
  selection : NotionReadSourceSelection,
  source : NotionDataSourceCatalog,
  read_contracts : NotionDataSourceReadContracts,
) -> Bool {
  read_snapshot_is_original(snapshot) &&
  physical_equal(snapshot.selection, selection) &&
  physical_equal(snapshot.source, source) &&
  physical_equal(snapshot.read_contracts, read_contracts)
}

///|
pub fn notion_database_read_snapshot_wire(
  snapshot : NotionDatabaseReadSnapshot,
) -> Result[String, NotionReadSnapshotIssue] {
  if read_snapshot_is_original(snapshot) {
    Ok(snapshot.wire)
  } else {
    Err(ForeignOriginal)
  }
}

///|
pub fn notion_database_read_snapshot_source_cid(
  snapshot : NotionDatabaseReadSnapshot,
) -> Result[String, NotionReadSnapshotIssue] {
  if read_snapshot_is_original(snapshot) {
    Ok(snapshot.source_cid)
  } else {
    Err(ForeignOriginal)
  }
}

///|
pub fn notion_database_read_snapshot_declaration(
  snapshot : NotionDatabaseReadSnapshot,
) -> Result[NotionDatabaseReadDeclaration, NotionReadSnapshotIssue] {
  if read_snapshot_is_original(snapshot) {
    Ok(snapshot.selection.declaration)
  } else {
    Err(ForeignOriginal)
  }
}

///|
pub fn notion_database_read_snapshot_source(
  snapshot : NotionDatabaseReadSnapshot,
) -> Result[NotionDataSourceCatalog, NotionReadSnapshotIssue] {
  if read_snapshot_is_original(snapshot) {
    Ok(snapshot.source)
  } else {
    Err(ForeignOriginal)
  }
}

///|
pub fn notion_database_read_snapshot_contracts(
  snapshot : NotionDatabaseReadSnapshot,
) -> Result[NotionDataSourceReadContracts, NotionReadSnapshotIssue] {
  if read_snapshot_is_original(snapshot) {
    Ok(snapshot.read_contracts)
  } else {
    Err(ForeignOriginal)
  }
}
