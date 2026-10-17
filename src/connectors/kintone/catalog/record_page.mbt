///|
/// Simultaneous original response/decode tree and selected observation bounds.
/// These do not reserve a RowRun, authorize I/O or adopt a numerical profile.
pub(all) struct RecordPageLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
  max_columns : Int
  max_cells : Int
  max_table_rows : Int
}

///|
pub(all) enum RecordPageIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  DuplicateSelection(String)
  FieldUnavailable(String)
  MissingField(String)
  InvalidField(String)
  DuplicateRecord(String)
  DuplicateTableRow(String)
} derive(Eq, Debug)

///|
/// Original native data, not a checked logical Value, writable target or grant.
/// The immutable decode cursor retains exact text and nulls without converting
/// Number, Time, revision or file size into another logical type.
pub struct OriginalRecordField {
  metadata : FormFieldMetadata
  priv value : @decode.Cursor
  priv table_rows : Array[OriginalTableRow]?
}

///|
pub struct OriginalTableRow {
  id : String
  priv fields : Array[OriginalRecordField]
}

///|
pub struct OriginalRecord {
  record_id : String
  revision : String
  priv fields : Array[OriginalRecordField]
}

///|
/// The original Form observation remains nominally associated with this page.
/// App identity and current authority must still be bound by the physical Site.
pub struct OriginalRecordPage {
  app_id : String
  form_revision : String
  response_sha256 : String
  total_count : String?
  priv catalog : FormFieldCatalog
  priv names : Array[String]
  priv records : Array[OriginalRecord]
}

///|
priv struct RecordProjectionBudget {
  mut cells : Int
  mut table_rows : Int
  depth : Int
}

///|
fn record_native_available(native_type : String) -> Bool {
  match native_type {
    "SINGLE_LINE_TEXT"
    | "MULTI_LINE_TEXT"
    | "RICH_TEXT"
    | "LINK"
    | "NUMBER"
    | "CALC"
    | "DATE"
    | "TIME"
    | "DATETIME"
    | "CREATED_TIME"
    | "UPDATED_TIME"
    | "CHECK_BOX"
    | "MULTI_SELECT"
    | "RADIO_BUTTON"
    | "DROP_DOWN"
    | "STATUS"
    | "CATEGORY"
    | "USER_SELECT"
    | "ORGANIZATION_SELECT"
    | "GROUP_SELECT"
    | "STATUS_ASSIGNEE"
    | "CREATOR"
    | "MODIFIER"
    | "RECORD_NUMBER"
    | "FILE"
    | "SUBTABLE" => true
    _ => false
  }
}

///|
fn record_wrapper(
  object : @decode.ObjectView,
  name : String,
  native_type : String,
) -> Result[@decode.Cursor, RecordPageIssue] {
  guard @decode.lookup(object, name) is Some(field) else {
    return Err(MissingField(name))
  }
  guard @decode.open_object(field) is Ok(wrapper) &&
    form_text(wrapper, "type") == Some(native_type) &&
    @decode.lookup(wrapper, "value") is Some(value) else {
    return Err(InvalidField(name))
  }
  Ok(value)
}

///|
fn record_identity(
  object : @decode.ObjectView,
  name : String,
  native_type : String,
) -> Result[String, RecordPageIssue] {
  let cursor = match record_wrapper(object, name, native_type) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.text(cursor) is Ok(value) && form_digits(value) else {
    return Err(InvalidField(name))
  }
  Ok(value)
}

///|
fn record_principal(cursor : @decode.Cursor) -> Bool {
  guard @decode.open_object(cursor) is Ok(object) &&
    form_text(object, "code") is Some(code) &&
    !code.is_empty() &&
    form_text(object, "name") is Some(_) else {
    return false
  }
  true
}

///|
fn record_array_valid(
  value : @decode.Cursor,
  check : (@decode.Cursor) -> Bool,
) -> Bool {
  guard @decode.array_length(value) is Some(count) else { return false }
  for index in 0..<count {
    if !check(@decode.element_at(value, index).unwrap()) {
      return false
    }
  }
  true
}

///|
fn record_file(cursor : @decode.Cursor) -> Bool {
  guard @decode.open_object(cursor) is Ok(object) &&
    form_text(object, "fileKey") is Some(key) &&
    !key.is_empty() &&
    form_text(object, "contentType") is Some(_) &&
    form_text(object, "name") is Some(_) &&
    form_text(object, "size") is Some(size) &&
    form_digits(size) else {
    return false
  }
  true
}

///|
fn record_scalar_shape_valid(
  value : @decode.Cursor,
  native_type : String,
) -> Bool {
  match native_type {
    "DATE" | "TIME" | "DROP_DOWN" | "RADIO_BUTTON" =>
      @decode.is_null(value) || @decode.text(value) is Ok(_)
    "CHECK_BOX" | "MULTI_SELECT" | "CATEGORY" =>
      record_array_valid(value, item => @decode.text(item) is Ok(_))
    "USER_SELECT"
    | "ORGANIZATION_SELECT"
    | "GROUP_SELECT"
    | "STATUS_ASSIGNEE" => record_array_valid(value, record_principal)
    "CREATOR" | "MODIFIER" => record_principal(value)
    "FILE" => record_array_valid(value, record_file)
    _ => @decode.text(value) is Ok(_)
  }
}

///|
fn record_table_children(
  catalog : FormFieldCatalog,
  parent : FormFieldMetadata,
) -> Array[FormFieldMetadata] {
  let children = []
  for field in catalog.fields {
    if field.path.length() == parent.path.length() + 1 {
      let mut same_parent = true
      for index in 0..<parent.path.length() {
        if field.path[index] != parent.path[index] {
          same_parent = false
          break
        }
      }
      if same_parent {
        children.push(field)
      }
    }
  }
  children
}

///|
fn record_project_fields(
  object : @decode.ObjectView,
  definitions : Array[FormFieldMetadata],
  catalog : FormFieldCatalog,
  budget : RecordProjectionBudget,
  depth : Int,
) -> Result[Array[OriginalRecordField], RecordPageIssue] {
  if depth > budget.depth || definitions.length() > budget.cells {
    return Err(BudgetExceeded)
  }
  let fields = []
  for metadata in definitions {
    if !record_native_available(metadata.native_type) {
      return Err(FieldUnavailable(metadata.code))
    }
    if budget.cells <= 0 {
      return Err(BudgetExceeded)
    }
    budget.cells -= 1
    let value = match
      record_wrapper(object, metadata.code, metadata.native_type) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let table_rows = if metadata.native_type == "SUBTABLE" {
      guard @decode.array_length(value) is Some(count) else {
        return Err(InvalidField(metadata.code))
      }
      if count > budget.table_rows {
        return Err(BudgetExceeded)
      }
      budget.table_rows -= count
      let definitions = record_table_children(catalog, metadata)
      for child in definitions {
        if !record_native_available(child.native_type) {
          return Err(FieldUnavailable(child.code))
        }
      }
      let rows = []
      let ids : Map[String, Bool] = Map([])
      for index in 0..<count {
        guard @decode.open_object(@decode.element_at(value, index).unwrap())
          is Ok(row) &&
          form_text(row, "id") is Some(id) &&
          form_digits(id) &&
          @decode.lookup(row, "value") is Some(values) &&
          @decode.open_object(values) is Ok(values_object) &&
          @decode.object_length(values) == Some(definitions.length()) else {
          return Err(InvalidField(metadata.code))
        }
        if ids.contains(id) {
          return Err(DuplicateTableRow(id))
        }
        ids[id] = true
        let fields = match
          record_project_fields(
            values_object,
            definitions,
            catalog,
            budget,
            depth + 1,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        rows.push({ id, fields, })
      }
      Some(rows)
    } else {
      if !record_scalar_shape_valid(value, metadata.native_type) {
        return Err(InvalidField(metadata.code))
      }
      None
    }
    fields.push({ metadata, value, table_rows, })
  }
  Ok(fields)
}

///|
/// Validate one complete Get Records response against the original selected
/// Form metadata. The physical caller requests $id and $revision as well as
/// these complete top-level fields (a subtable is not a child-field request).
/// A missing field never becomes null. Original native text/arrays are not
/// normalized, rounded, classified or admitted as logical Values here.
pub fn project_record_page(
  bytes : Bytes,
  catalog : FormFieldCatalog,
  names : Array[String],
  limits : RecordPageLimits,
) -> Result[OriginalRecordPage, RecordPageIssue] {
  if limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_rows <= 0 ||
    limits.max_columns <= 0 ||
    limits.max_cells <= 0 ||
    limits.max_table_rows <= 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes || names.length() > limits.max_columns {
    return Err(BudgetExceeded)
  }
  let selected = []
  let seen : Map[String, Bool] = Map([])
  for name in names {
    if seen.contains(name) {
      return Err(DuplicateSelection(name))
    }
    guard form_field_named(catalog, [name]) is Some(field) &&
      record_native_available(field.native_type) else {
      return Err(FieldUnavailable(name))
    }
    selected.push(field)
    seen[name] = true
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(error) =>
      return Err(
        match error.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(error) =>
      return Err(
        match error.kind {
          BudgetExceeded => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  guard @decode.open_object(root) is Ok(object) &&
    @decode.lookup(object, "records") is Some(list) &&
    @decode.array_length(list) is Some(count) else {
    return Err(InvalidResponse)
  }
  if count > limits.max_rows {
    return Err(BudgetExceeded)
  }
  let total_count = match @decode.field(object, "totalCount") {
    ExplicitNull => None
    Present(value) => {
      guard @decode.text(value) is Ok(text) && form_digits(text) else {
        return Err(InvalidResponse)
      }
      Some(text)
    }
    Missing => return Err(InvalidResponse)
  }
  let budget : RecordProjectionBudget = {
    cells: limits.max_cells,
    table_rows: limits.max_table_rows,
    depth: limits.max_depth,
  }
  let records = []
  let ids : Map[String, Bool] = Map([])
  for index in 0..<count {
    guard @decode.open_object(@decode.element_at(list, index).unwrap())
      is Ok(row) else {
      return Err(InvalidResponse)
    }
    let record_id = match record_identity(row, "$id", "__ID__") {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let revision = match record_identity(row, "$revision", "__REVISION__") {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if ids.contains(record_id) {
      return Err(DuplicateRecord(record_id))
    }
    ids[record_id] = true
    let fields = match
      record_project_fields(row, selected, catalog, budget, 1) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    records.push({ record_id, revision, fields, })
  }
  Ok({
    app_id: catalog.app_id,
    form_revision: catalog.revision,
    response_sha256: @sha.hex(bytes),
    total_count,
    catalog,
    names: names.copy(),
    records,
  })
}

///|
pub fn record_page_uses_catalog(
  page : OriginalRecordPage,
  catalog : FormFieldCatalog,
) -> Bool {
  physical_equal(page.catalog, catalog)
}

///|
pub fn record_page_records(page : OriginalRecordPage) -> Array[OriginalRecord] {
  page.records.copy()
}

///|
pub fn record_page_columns(page : OriginalRecordPage) -> Array[String] {
  page.names.copy()
}

///|
pub fn original_record_fields(
  record : OriginalRecord,
) -> Array[OriginalRecordField] {
  record.fields.copy()
}

///|
pub fn original_table_fields(
  row : OriginalTableRow,
) -> Array[OriginalRecordField] {
  row.fields.copy()
}

///|
pub fn original_record_value(field : OriginalRecordField) -> @decode.Cursor {
  field.value
}

///|
pub fn original_record_table_rows(
  field : OriginalRecordField,
) -> Array[OriginalTableRow]? {
  field.table_rows.map(rows => rows.copy())
}
