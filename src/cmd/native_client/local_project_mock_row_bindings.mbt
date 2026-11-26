///|
// Same immutable declaration/path/provider selected by the Project metadata
// Read. The actual managed Source still owns opening, current and retirement.
priv struct LocalProjectMockRowBinding {
  view : @row_host.RowDeclaredView
  _retained_selection : @row_file.NativeRelationFileSelection
  limits : @row_file.NativeRelationFileLimits
  provider : @row_file.NativeRelationFilePreparedProvider
}

///|
fn local_project_mock_row_bindings(
  entry : Json,
  declaration : @row_host.RowDeclaration,
  files : Array[LocalProjectMockFileBinding],
  data_file : String,
  fund_ordered? : ((@execution.ExecutionCapacity) -> Bool)? = None,
) -> Result[Array[LocalProjectMockRowBinding], @row_host.RowHostIssue] {
  guard entry is Object(body) else { return Err(InvalidSpecification) }
  let data = match body.get("data") {
    None => return Ok([])
    Some(Array(values)) => values
    _ => return Err(InvalidSpecification)
  }
  let selected_file = local_input_file_location("/", data_file) catch {
    _ => return Err(InvalidSpecification)
  }
  let result : Array[LocalProjectMockRowBinding] = []
  for value in data {
    guard local_project_mock_file_text(value, "resource") is Some(resource) else {
      return Err(InvalidSpecification)
    }
    // File carriers use their existing checked physical row declaration and
    // original ResourceRef issuer; they must never enter the raw row reader.
    if files.any(file => file._retained_selection.resource == resource) {
      continue
    }
    // The public Mock catalogue admits four fields here. A separate schema
    // is reserved for the already selected file-data branch above.
    guard value is Object(fields) &&
      fields.length() == 4 &&
      local_project_mock_file_path(value, "items_path") is Some(items_path) &&
      local_project_mock_file_path(value, "key_path") is Some(key_path) &&
      fields.get("primary_identity") is Some(original_key) &&
      declaration.views.iter().find_first(view => view.resource == resource)
      is Some(view) &&
      !result.any(prior => prior.view.resource == resource) else {
      return Err(InvalidSpecification)
    }
    // The same installed file profile supplies the ordinary read limits.
    let limits = local_project_mock_file_limits()
    let (identity, ordered_fields) = match original_key {
      String(_) => {
        guard local_project_mock_file_text(value, "primary_identity")
          is Some(identity) else {
          return Err(InvalidSpecification)
        }
        (identity, None)
      }
      Object(tuple) => {
        guard tuple.length() == 2 &&
          tuple.get("kind") == Some(Json::string("tuple")) &&
          tuple.get("fields") is Some(Array(names)) &&
          fund_ordered is Some(fund) &&
          @row_host.relation_document_key_metadata_capacity(
            declaration,
            resource,
            limits.page,
            names.length(),
          )
          is Some(quote) &&
          fund(quote) else {
          return Err(InvalidSpecification)
        }
        guard local_project_mock_write_names(tuple.get("fields"))
          is Some(fields) &&
          fields.get(0) is Some(identity) else {
          return Err(InvalidSpecification)
        }
        (identity, Some(fields))
      }
      _ => return Err(InvalidSpecification)
    }
    let selection : @row_file.NativeRelationFileSelection = {
      directory: selected_file.root,
      name: selected_file.name,
      resource,
      items_path,
      key_path: Some(key_path),
      primary_identity: identity,
    }
    let provider = match
      @row_file.prepare_native_relation_file_provider(
        declaration,
        selection,
        limits,
        response_measured=true,
        ordered_fields~,
      ) {
      Ok(value) => value
      Err(_) => return Err(InvalidSpecification)
    }
    result.push({ view, _retained_selection: selection, limits, provider, })
  }
  Ok(result)
}
