///|
/// A bounded borrow of the original admitted listing. It retains no locator
/// map, copied rows, provider receipt or authority beyond that capture.
struct CapturedFileLocator {
  source : CapturedInputSource
  read : @execution.SuppliedRelationRead
  resource : @value.ReferenceValue
  version : String
  max_path_units : Int
  mut column : Int
  mut resource_column : Int?
  mut version_column : Int?
  mut path_column : Int?
  mut row : Int
  mut candidate_version : String?
  mut candidate_path : String?
  mut found : String?
  mut offset : Int
  mut closed : Bool
}

///|
pub enum CapturedFileLocatorPoll {
  CapturedFileLocatorContinue
  CapturedFileLocatorComplete(String)
  CapturedFileLocatorFailed
}

///|
pub fn start_captured_file_locator(
  source : CapturedInputSource,
  read : @execution.SuppliedRelationRead,
  resource : @value.ReferenceValue,
  version : String,
  max_path_units : Int,
) -> CapturedFileLocator? {
  if !captured_source_available(source) ||
    !@execution.supplied_relation_read_available(read) ||
    !(match source.owner {
      QueryCapture(query) =>
        @execution.supplied_relation_read_matches_input(
          read,
          query_sequence_owner(query),
          query_receipt_input_index(query),
        )
      InputCapture(input) =>
        @execution.supplied_relation_read_same_binding(read, input.read)
    }) ||
    !@value.reference_available(resource) ||
    version.is_empty() ||
    max_path_units < 1 {
    return None
  }
  Some({
    source,
    read,
    resource,
    version,
    max_path_units,
    column: 0,
    resource_column: None,
    version_column: None,
    path_column: None,
    row: 0,
    candidate_version: None,
    candidate_path: None,
    found: None,
    offset: 0,
    closed: false,
  })
}

///|
pub fn cancel_captured_file_locator(cursor : CapturedFileLocator) -> Unit {
  cursor.closed = true
  cursor.candidate_version = None
  cursor.candidate_path = None
  cursor.found = None
}

///|
fn captured_file_locator_fail(
  cursor : CapturedFileLocator,
) -> CapturedFileLocatorPoll {
  cancel_captured_file_locator(cursor)
  CapturedFileLocatorFailed
}

///|
fn captured_file_locator_text(
  read : @execution.SuppliedRelationRead,
  row : Int,
  column : Int,
) -> String? {
  match @execution.supplied_relation_read_cell(read, row, column) {
    Some(@value.Text(text)) => Some(text)
    _ => None
  }
}

///|
/// One metadata-column, row, or UTF-16 unit per advance. The Resource CID
/// comparison has the fixed admitted CID width, and file-kind names come from
/// the checked file profile. The original lookup
/// charges before each advance; text scans never become an unbounded equality
/// call. Scan the whole capture so contradictory matching locators cannot be
/// hidden by choosing the first row. Missing/NULL paths are not invented.
pub fn advance_captured_file_locator(
  cursor : CapturedFileLocator,
) -> CapturedFileLocatorPoll {
  if cursor.closed ||
    !captured_source_available(cursor.source) ||
    !@execution.supplied_relation_read_available(cursor.read) ||
    !@value.reference_available(cursor.resource) {
    return captured_file_locator_fail(cursor)
  }
  let schema = @execution.supplied_relation_read_schema(cursor.read)
  if cursor.column < @schema.field_count(schema) {
    match
      @schema.field_at(schema, cursor.column).map(@schema.field_reference_name) {
      Some("resource") => cursor.resource_column = Some(cursor.column)
      Some("version") => cursor.version_column = Some(cursor.column)
      Some("path") => cursor.path_column = Some(cursor.column)
      _ => ()
    }
    cursor.column += 1
    return CapturedFileLocatorContinue
  }
  guard cursor.resource_column is Some(resource_column) &&
    cursor.version_column is Some(version_column) &&
    cursor.path_column is Some(path_column) else {
    return captured_file_locator_fail(cursor)
  }
  if cursor.candidate_version is Some(version) {
    if cursor.offset < version.length() {
      if version[cursor.offset] != cursor.version[cursor.offset] {
        cursor.candidate_version = None
        cursor.offset = 0
        cursor.row += 1
      } else {
        cursor.offset += 1
      }
      return CapturedFileLocatorContinue
    }
    guard captured_file_locator_text(cursor.read, cursor.row, path_column)
      is Some(path) &&
      !path.is_empty() &&
      path.length() <= cursor.max_path_units else {
      return captured_file_locator_fail(cursor)
    }
    cursor.candidate_version = None
    cursor.candidate_path = Some(path)
    cursor.offset = 0
    return CapturedFileLocatorContinue
  }
  if cursor.candidate_path is Some(path) {
    if cursor.found is Some(found) {
      if found.length() != path.length() {
        return captured_file_locator_fail(cursor)
      }
      if cursor.offset < path.length() {
        if found[cursor.offset] != path[cursor.offset] {
          return captured_file_locator_fail(cursor)
        }
        cursor.offset += 1
        return CapturedFileLocatorContinue
      }
    }
    cursor.found = Some(path)
    cursor.candidate_path = None
    cursor.row += 1
    return CapturedFileLocatorContinue
  }
  if cursor.row == @execution.supplied_relation_read_row_count(cursor.read) {
    guard cursor.found is Some(path) else {
      return captured_file_locator_fail(cursor)
    }
    cursor.closed = true
    cursor.found = None
    return CapturedFileLocatorComplete(path)
  }
  match
    @execution.supplied_relation_read_cell(
      cursor.read,
      cursor.row,
      resource_column,
    ) {
    Some(@value.Reference(resource)) => {
      if !@value.reference_available(resource) {
        return captured_file_locator_fail(cursor)
      }
      if @value.reference_identity_cid(resource) ==
        @value.reference_identity_cid(cursor.resource) &&
        @value.reference_same_domain(resource, cursor.resource) {
        guard captured_file_locator_text(
            cursor.read,
            cursor.row,
            version_column,
          )
          is Some(version) else {
          return captured_file_locator_fail(cursor)
        }
        if version.length() == cursor.version.length() {
          cursor.candidate_version = Some(version)
          cursor.offset = 0
          return CapturedFileLocatorContinue
        }
      }
    }
    _ => return captured_file_locator_fail(cursor)
  }
  cursor.row += 1
  CapturedFileLocatorContinue
}
