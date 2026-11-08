///|
// Immutable physical roles for one existing declared file Source. This is
// neither a ResourceRef issuer nor Content custody. The same Native reader
// must consume this retained declaration, selection and limits after admission.
priv struct LocalProjectMockFileBinding {
  listing : @row_host.RowDeclaredView
  content : @row_host.RowDeclaredView
  _retained_physical : @row_host.RowDeclaration
  _retained_provider : @row_file.NativeRelationFilePreparedProvider
  _retained_read_profile : @row_file.NativeRelationFileKeyedReadProfile
  _retained_selection : @row_file.NativeRelationFileSelection
  _retained_limits : @row_file.NativeRelationFileLimits
  _retained_identity : String
  _retained_name : String
  _retained_version : String
  _retained_media_type : String
  _retained_content_utf8 : String
  _retained_path : String?
}

///|
fn local_project_mock_file_text(value : Json, name : String) -> String? {
  guard value is Object(fields) &&
    fields.get(name) is Some(String(text)) &&
    !text.is_empty() &&
    !text.contains("\u{0000}") else {
    return None
  }
  Some(text)
}

///|
fn local_project_mock_file_path(value : Json, name : String) -> Array[String]? {
  guard value is Object(fields) && fields.get(name) is Some(Array(path)) else {
    return None
  }
  let result = []
  for item in path {
    guard item is String(text) && !text.is_empty() && !text.contains("\u{0000}") else {
      return None
    }
    result.push(text)
  }
  Some(result)
}

///|
// Keep the existing declared Mock file profile. These are physical decoder
// ceilings, not the Project metadata Reader's 64 KiB limit or a Run grant.
// Both the file transport and response builder must enforce this SAME record.
fn local_project_mock_file_limits() -> @row_file.NativeRelationFileLimits {
  {
    page: { max_bytes: 1048576, max_nodes: 4096, max_depth: 32, max_rows: 100, },
    max_work: 16777216,
    chunk_bytes: 8192,
    diagnostic_ceiling: 4096,
  }
}

///|
// The public file contract selects exact non-null Text roles. Common still
// admits the complete original schema and owns all Value/row validation.
fn local_project_mock_file_text_field(schema : Json, name : String) -> Bool {
  schema is Object(fields) &&
  fields.get(name) is Some(Object(field)) &&
  field.get("type") == Some(Json::string("string")) &&
  field.get("nullable") == Some(Json::boolean(false))
}

///|
fn local_project_mock_file_bindings(
  connection : String,
  entry : Json,
  declaration : @row_host.RowDeclaration,
  data_file : String,
) -> Result[Array[LocalProjectMockFileBinding], @row_host.RowHostIssue] {
  guard entry is Object(fields) else { return Err(InvalidSpecification) }
  let bindings = match fields.get("file_bindings") {
    None => return Ok([])
    Some(Array(values)) => values
    _ => return Err(InvalidSpecification)
  }
  guard fields.get("data") is Some(Array(data)) else {
    return Err(InvalidSpecification)
  }
  let result : Array[LocalProjectMockFileBinding] = []
  for binding in bindings {
    guard binding is Object(body) else { return Err(InvalidSpecification) }
    let required = [
      "listing_resource", "content_resource", "data_resource", "identity_field",
      "name_field", "version_field", "media_type_field", "content_utf8_field",
    ]
    if body.length() !=
      required.length() + (if body.contains("path_field") { 1 } else { 0 }) {
      return Err(InvalidSpecification)
    }
    let selected : Array[String] = []
    for name in required {
      guard local_project_mock_file_text(binding, name) is Some(value) else {
        return Err(InvalidSpecification)
      }
      selected.push(value)
    }
    let listing_resource = selected[0]
    let content_resource = selected[1]
    let data_resource = selected[2]
    let identity = selected[3]
    if listing_resource == content_resource ||
      result.any(previous => {
        previous.listing.resource == listing_resource ||
        previous.content.resource == listing_resource ||
        previous.listing.resource == content_resource ||
        previous.content.resource == content_resource
      }) {
      return Err(InvalidSpecification)
    }
    // Public roles name resources, not the full sourceRef accepted by the
    // generic sourceRef lookup. Keep the SAME original declared view objects.
    let mut listing = None
    let mut content = None
    for view in declaration.views {
      if view.resource == listing_resource {
        listing = Some(view)
      }
      if view.resource == content_resource {
        content = Some(view)
      }
    }
    guard listing is Some(listing) && content is Some(content) else {
      return Err(InvalidSpecification)
    }
    let mut physical_data = None
    for candidate in data {
      if local_project_mock_file_text(candidate, "resource") ==
        Some(data_resource) {
        if physical_data is Some(_) {
          return Err(InvalidSpecification)
        }
        physical_data = Some(candidate)
      }
    }
    guard physical_data is Some(Object(physical)) &&
      physical.get("schema") is Some(schema) &&
      local_project_mock_file_text(Json::object(physical), "primary_identity") ==
      Some(identity) &&
      local_project_mock_file_path(Json::object(physical), "items_path")
      is Some(items_path) &&
      local_project_mock_file_path(Json::object(physical), "key_path")
      is Some(key_path) else {
      return Err(InvalidSpecification)
    }
    for name in selected[3:] {
      if !local_project_mock_file_text_field(schema, name) {
        return Err(InvalidSpecification)
      }
    }
    let path = match body.get("path_field") {
      None => None
      Some(String(name)) => {
        if name.is_empty() ||
          !(schema is Object(fields) &&
          fields.get(name) is Some(Object(field)) &&
          field.get("type") == Some(Json::string("string"))) {
          return Err(InvalidSpecification)
        }
        Some(name)
      }
      _ => return Err(InvalidSpecification)
    }
    let physical_view : Json = {
      "views": [
        {
          "resource": data_resource,
          "resource_kind": "file",
          "schema": schema,
          "facts": { "relation_keys": { "candidate_keys": [[identity]] } },
        },
      ],
    }
    let input = match local_project_mock_relation_input(physical_view) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let physical = match
      @row_host.restore_relation_row_declaration(
        connection,
        "declared_file_data",
        "declared_file_data/0.1",
        input,
        None,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let selected_file = local_input_file_location("/", data_file) catch {
      _ => return Err(InvalidSpecification)
    }
    let selection : @row_file.NativeRelationFileSelection = {
      directory: selected_file.root,
      name: selected_file.name,
      resource: data_resource,
      items_path,
      key_path: Some(key_path),
      primary_identity: identity,
    }
    let limits = local_project_mock_file_limits()
    let provider = match
      @row_file.prepare_native_relation_file_provider(
        physical,
        selection,
        limits,
        response_measured=true,
      ) {
      Ok(value) => value
      Err(_) => return Err(InvalidSpecification)
    }
    let read_profile = match
      @row_file.prepare_native_relation_file_keyed_read_profile(
        declaration,
        content.source_ref,
        provider,
        {
          name: selected[4],
          version: selected[5],
          media_type: selected[6],
          path,
        },
        selected[7],
      ) {
      Ok(value) => value
      Err(_) => return Err(InvalidSpecification)
    }
    result.push({
      listing,
      content,
      _retained_physical: physical,
      _retained_provider: provider,
      _retained_read_profile: read_profile,
      _retained_selection: selection,
      _retained_limits: limits,
      _retained_identity: identity,
      _retained_name: selected[4],
      _retained_version: selected[5],
      _retained_media_type: selected[6],
      _retained_content_utf8: selected[7],
      _retained_path: path,
    })
  }
  Ok(result)
}

///|
// One selected declared-file protocol duration, shared by listing facts and
// the Host's keyed lookup policy. Actual admission/current/cleanup is separate.
fn local_project_mock_file_duration_ms() -> Int64 {
  30000L
}
