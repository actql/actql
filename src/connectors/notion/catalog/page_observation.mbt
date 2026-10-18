///|
/// Admission bounds are not a Site reservation, page membership or permission.
pub(all) struct NotionPageLimits {
  metadata : NotionDatabaseLimits
  max_text_bytes : Int
}

///|
pub(all) enum NotionPageIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  ForeignPage
  InvalidParent
  InvalidField(String)
} derive(Eq, Debug)

///|
/// Preserve the vendor discriminant. A data-source id is never a database id,
/// and the workspace marker has no invented identifier.
pub(all) enum NotionPageParent {
  Workspace
  Page(String)
  Database(String)
  DataSource(String, String?)
  Block(String)
  Agent(String)
} derive(Eq, Debug)

///|
/// One exact GET response, not a complete pages collection, typed property
/// value, current-version guard, Reference or write authorization. Properties
/// remain original vendor DATA and may still need property-item pagination.
pub struct OriginalNotionPage {
  priv original_self : Ref[OriginalNotionPage?]
  id : String
  response_sha256 : String
  parent : NotionPageParent
  url : String
  created_by : String
  last_edited_by : String
  created_time : String
  last_edited_time : String
  version : String
  archived : Bool
  priv original : @decode.Cursor
  priv properties : @decode.Cursor
  priv raw : Bytes
}

///|
fn page_text(
  object : @decode.ObjectView,
  name : String,
  max_bytes : Int,
) -> Result[String, NotionPageIssue] {
  guard @decode.lookup(object, name) is Some(cursor) else {
    return Err(InvalidField(name))
  }
  match metadata_text(cursor, max_bytes, true) {
    Ok(value) => Ok(value)
    Err(BudgetExceeded) => Err(BudgetExceeded)
    Err(_) => Err(InvalidField(name))
  }
}

///|
fn page_parent(
  cursor : @decode.Cursor,
  max_bytes : Int,
) -> Result[NotionPageParent, NotionPageIssue] {
  guard @decode.open_object(cursor) is Ok(parent) &&
    @decode.lookup(parent, "type") is Some(kind) &&
    @decode.text(kind) is Ok(kind) else {
    return Err(InvalidParent)
  }
  if kind == "workspace" {
    guard @decode.closed_object(cursor, ["type", "workspace"]) is Ok(_) &&
      @decode.lookup(parent, "workspace") is Some(marker) &&
      @decode.boolean(marker) == Ok(true) else {
      return Err(InvalidParent)
    }
    return Ok(Workspace)
  }
  let allowed = if kind == "data_source_id" {
    ["type", "data_source_id", "database_id"]
  } else if ["page_id", "database_id", "block_id", "agent_id"].contains(kind) {
    ["type", kind]
  } else {
    return Err(InvalidParent)
  }
  guard @decode.closed_object(cursor, allowed) is Ok(_) else {
    return Err(InvalidParent)
  }
  let id = match page_text(parent, kind, max_bytes) {
    Ok(value) => value
    Err(BudgetExceeded) => return Err(BudgetExceeded)
    Err(_) => return Err(InvalidParent)
  }
  match kind {
    "page_id" => Ok(Page(id))
    "database_id" => Ok(Database(id))
    "block_id" => Ok(Block(id))
    "agent_id" => Ok(Agent(id))
    _ => {
      let database = match @decode.field(parent, "database_id") {
        Missing => None
        Present(_) =>
          match page_text(parent, "database_id", max_bytes) {
            Ok(value) => Some(value)
            Err(BudgetExceeded) => return Err(BudgetExceeded)
            Err(_) => return Err(InvalidParent)
          }
        _ => return Err(InvalidParent)
      }
      Ok(DataSource(id, database))
    }
  }
}

///|
fn page_user(
  root : @decode.ObjectView,
  name : String,
  max_bytes : Int,
) -> Result[String, NotionPageIssue] {
  guard @decode.lookup(root, name) is Some(cursor) &&
    @decode.open_object(cursor) is Ok(user) &&
    text_is(user, "object", "user") else {
    return Err(InvalidField(name))
  }
  match page_text(user, "id", max_bytes) {
    Ok(value) => Ok(value)
    Err(BudgetExceeded) => Err(BudgetExceeded)
    Err(_) => Err(InvalidField(name))
  }
}

///|
fn page_archived(root : @decode.ObjectView) -> Result[Bool, NotionPageIssue] {
  let current = match @decode.field(root, "in_trash") {
    Missing => None
    Present(value) =>
      match @decode.boolean(value) {
        Ok(value) => Some(value)
        Err(_) => return Err(InvalidField("in_trash"))
      }
    _ => return Err(InvalidField("in_trash"))
  }
  let legacy = match @decode.field(root, "archived") {
    Missing => None
    Present(value) =>
      match @decode.boolean(value) {
        Ok(value) => Some(value)
        Err(_) => return Err(InvalidField("archived"))
      }
    _ => return Err(InvalidField("archived"))
  }
  match (current, legacy) {
    (Some(value), Some(other)) if value == other => Ok(value)
    (Some(value), None) | (None, Some(value)) => Ok(value)
    _ => Err(InvalidField("in_trash"))
  }
}

///|
pub fn project_notion_page(
  bytes : Bytes,
  expected_page_id : String,
  limits : NotionPageLimits,
) -> Result[OriginalNotionPage, NotionPageIssue] {
  if !database_limits_valid(limits.metadata) || limits.max_text_bytes <= 0 {
    return Err(InvalidLimits)
  }
  // Lower bounds reject before snapshot allocation or decoding. The returned
  // id is independently admitted under its actual UTF8 identity bound below.
  if bytes.length() > limits.metadata.max_bytes ||
    expected_page_id.length() > limits.metadata.max_identity_bytes {
    return Err(BudgetExceeded)
  }
  if expected_page_id.is_empty() {
    return Err(ForeignPage)
  }
  let raw = Bytes::makei(bytes.length(), index => bytes[index])
  let original = match database_cursor(raw, limits.metadata) {
    Ok(value) => value
    Err(BudgetExceeded) => return Err(BudgetExceeded)
    Err(_) => return Err(InvalidResponse)
  }
  guard @decode.open_object(original) is Ok(root) &&
    text_is(root, "object", "page") else {
    return Err(InvalidResponse)
  }
  let id = match page_text(root, "id", limits.metadata.max_identity_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if id != expected_page_id {
    return Err(ForeignPage)
  }
  guard @decode.lookup(root, "parent") is Some(parent) else {
    return Err(InvalidParent)
  }
  let parent = match page_parent(parent, limits.metadata.max_identity_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let url = match page_text(root, "url", limits.max_text_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let created_by = match
    page_user(root, "created_by", limits.metadata.max_identity_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let last_edited_by = match
    page_user(root, "last_edited_by", limits.metadata.max_identity_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let created = match page_text(root, "created_time", limits.max_text_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let version = match
    page_text(root, "last_edited_time", limits.max_text_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @admitted.normalize_timestamp_text(created, limits.max_text_bytes)
    is Some(created_time) else {
    return Err(InvalidField("created_time"))
  }
  guard @admitted.normalize_timestamp_text(version, limits.max_text_bytes)
    is Some(last_edited_time) else {
    return Err(InvalidField("last_edited_time"))
  }
  let archived = match page_archived(root) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.lookup(root, "properties") is Some(properties) &&
    @decode.object_length(properties) is Some(count) else {
    return Err(InvalidField("properties"))
  }
  if count > limits.metadata.max_properties {
    return Err(BudgetExceeded)
  }
  // Normalized time is retained alongside the exact original spelling.
  if created_time.length() > limits.max_text_bytes ||
    last_edited_time.length() > limits.max_text_bytes {
    return Err(BudgetExceeded)
  }
  for index in 0..<count {
    let (name, _) = @decode.field_at(properties, index).unwrap()
    if name.length() > limits.metadata.max_name_bytes ||
      @utf8.encode(name).length() > limits.metadata.max_name_bytes {
      return Err(BudgetExceeded)
    }
  }
  let original_self : Ref[OriginalNotionPage?] = Ref(None)
  let page = {
    original_self,
    id,
    response_sha256: @sha.hex(raw),
    parent,
    url,
    created_by,
    last_edited_by,
    created_time,
    last_edited_time,
    version,
    archived,
    original,
    properties,
    raw,
  }
  original_self.val = Some(page)
  Ok(page)
}

///|
fn notion_page_is_original(page : OriginalNotionPage) -> Bool {
  match page.original_self.val {
    Some(original) => physical_equal(original, page)
    None => false
  }
}

///|
pub fn notion_page_original(page : OriginalNotionPage) -> @decode.Cursor {
  page.original
}

///|
/// An original property container is not a logical cell or complete title.
pub fn notion_page_properties_original(
  page : OriginalNotionPage,
) -> @decode.Cursor {
  page.properties
}

///|
pub fn notion_page_original_json(
  page : OriginalNotionPage,
  max_bytes : Int,
) -> Result[String, NotionPageIssue] {
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

///|
/// Bounded private DATA projection, not the public pages schema or target Ref.
pub fn notion_page_metadata_wire(
  page : OriginalNotionPage,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, NotionPageIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("id", page.id),
        ("resource", page.id),
        ("version", page.version),
        ("url", page.url),
        ("created_by", page.created_by),
        ("last_edited_by", page.last_edited_by),
        ("created_time", page.created_time),
        ("last_edited_time", page.last_edited_time),
        ("responseSha256", page.response_sha256),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "archived")
    @encode.bool_value(writer, page.archived)
    @encode.key(writer, "parent")
    @encode.begin_object(writer)
    @encode.key(writer, "type")
    match page.parent {
      Workspace => {
        @encode.string_value(writer, "workspace")
        @encode.key(writer, "workspace")
        @encode.bool_value(writer, true)
      }
      Page(id) | Database(id) | Block(id) | Agent(id) => {
        let name = match page.parent {
          Page(_) => "page_id"
          Database(_) => "database_id"
          Block(_) => "block_id"
          _ => "agent_id"
        }
        @encode.string_value(writer, name)
        @encode.key(writer, name)
        @encode.string_value(writer, id)
      }
      DataSource(id, database) => {
        @encode.string_value(writer, "data_source_id")
        @encode.key(writer, "data_source_id")
        @encode.string_value(writer, id)
        match database {
          None => ()
          Some(id) => {
            @encode.key(writer, "database_id")
            @encode.string_value(writer, id)
          }
        }
      }
    }
    @encode.end_object(writer)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}
