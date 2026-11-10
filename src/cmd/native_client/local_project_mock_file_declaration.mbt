///|
// This is the declared-file implementation's static identity, not the adopted
// Account authority scope. Keep the exact original catalogue wire and locator
// in the same preimage used by the existing declared Project implementation.
fn local_project_mock_file_cid(
  value : Json,
) -> Result[String, @row_host.RowHostIssue] {
  local_project_mock_relation_wire(value).map(wire => {
    "sha256:" + @sha.hex(@utf8.encode(wire))
  })
}

///|
// Bind the existing File protocol facts to the SAME admitted schema and real
// physical reader limits. This constructs no reader, reference or permission.
// Common alone checks the completed facts and correlation declarations.
fn local_project_mock_file_declaration(
  connection : String,
  provider : String,
  original_wire : String,
  entry : Json,
  data_file : String,
  initial : @row_host.RowDeclaration,
  files : Array[LocalProjectMockFileBinding],
) -> Result[
  (@row_host.RowDeclaration, Array[LocalProjectMockFileBinding], String),
  @row_host.RowHostIssue,
] {
  guard entry is Object(body) else { return Err(InvalidSpecification) }
  let scope = match
    local_project_mock_file_cid({
      "connection": Json::string(connection),
      "connector": Json::string(provider),
      "dataPath": Json::string(data_file),
      "catalog": Json::string(original_wire),
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if files.is_empty() {
    return Ok((initial, files, scope))
  }
  guard body.get("views") is Some(Array(views)) &&
    body.get("data") is Some(Array(data)) else {
    return Err(InvalidSpecification)
  }
  let selected = views.map(view => {
    match view {
      Object(fields) => Json::object(Map(fields.to_array()))
      _ => view
    }
  })
  for file in files {
    guard data
      .iter()
      .find_first(candidate => {
        local_project_mock_file_text(candidate, "resource") ==
        Some(file._retained_selection.resource)
      })
      is Some(physical) else {
      return Err(InvalidSpecification)
    }
    let version = match
      local_project_mock_file_cid({
        "scope": Json::string(scope),
        "physical": physical,
        "version_field": Json::string(file._retained_version),
        "representation": Json::string("exact_stored_bytes"),
      }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let limits = file._retained_limits
    let version_capability : Json = {
      "contract_cid": Json::string(version),
      "required_nonnull": true,
    }
    for view in selected {
      guard view is Object(fields) &&
        fields.get("resource") is Some(String(resource)) else {
        return Err(InvalidSpecification)
      }
      if resource == file.listing.resource {
        fields["facts"] = {
          "file_listing": {
            "version": "actql-file-list/0.1",
            "kind": "file_listing",
            "selectable": [],
            "allow_unfiltered_listing": true,
            "admitted_scope_contract_cid": Json::string(scope),
            "listing_schema_contract_cid": Json::string(
              file.listing.carrier_schema_cid,
            ),
            "version_capability": version_capability,
            "max_listing_items": Json::number(limits.page.max_rows.to_double()),
            "max_examined_items": Json::number(limits.page.max_rows.to_double()),
            "max_listing_pages": 1,
            "max_request_attempts": 1,
            "max_listing_bytes": Json::number(limits.page.max_bytes.to_double()),
            "max_listing_duration_ms": Json::number(
              local_project_mock_file_duration_ms().to_double(),
            ),
            "maximum_path_length": 4096,
          },
        }
      } else if resource == file.content.resource {
        fields["facts"] = {
          "file_content": {
            "version": "actql-file-content/0.1",
            "kind": "file_content",
            "admitted_scope_contract_cid": Json::string(scope),
            "content_schema_contract_cid": Json::string(
              file.content.carrier_schema_cid,
            ),
            "version_capability": version_capability,
            "representation": "exact_stored_bytes",
          },
          "lookup_capacity": {
            "version": "actql-lookup-capacity/0.1",
            "completeness": "complete_per_requested_key",
            "max_rows_per_key": 1,
            "max_pages_per_request": 1,
            "max_response_bytes_per_page": Json::number(
              limits.page.max_bytes.to_double(),
            ),
          },
        }
      }
    }
  }
  let input = match
    local_project_mock_relation_input({ "views": Json::array(selected) }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let declaration = match
    @row_host.restore_relation_row_declaration(
      connection,
      "declared_file",
      "declared_file/0.1",
      input,
      None,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let rebound : Array[LocalProjectMockFileBinding] = []
  for file in files {
    guard declaration.views
      .iter()
      .find_first(view => view.resource == file.listing.resource)
      is Some(listing) &&
      declaration.views
      .iter()
      .find_first(view => view.resource == file.content.resource)
      is Some(content) else {
      return Err(InvalidSpecification)
    }
    // The facts above change the SourceView identity. Bind the implementation
    // descriptor to that final admitted declaration as well; retaining the
    // initial descriptor would name a different view in the first Model Plan.
    // The physical provider/selection/limits are the SAME retained originals.
    let read_profile = match
      @row_file.prepare_native_relation_file_keyed_read_profile(
        declaration,
        content.source_ref,
        file._retained_provider,
        {
          name: file._retained_name,
          version: file._retained_version,
          media_type: file._retained_media_type,
          path: file._retained_path,
        },
        file._retained_content_utf8,
      ) {
      Ok(value) => value
      Err(_) => return Err(InvalidSpecification)
    }
    rebound.push({
      ..file,
      listing,
      content,
      _retained_read_profile: read_profile,
    })
  }
  Ok((declaration, rebound, scope))
}
