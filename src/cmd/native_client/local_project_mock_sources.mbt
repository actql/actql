///|
// Original declaration DATA only. The actual Source owner must separately
// open the retained payload locator under its checked Request/current scope.
priv struct LocalProjectMockSourceDeclaration {
  _retained_provider_namespace : String
  _retained_connection : String
  _retained_entry : Json
  _retained_scope_cid : String
  _retained_declaration : @row_host.RowDeclaration
  _retained_files : Array[LocalProjectMockFileBinding]
  _retained_rows : Array[LocalProjectMockRowBinding]
  _retained_writes : Array[LocalProjectMockWriteDeclaration]
}

///|
// Mechanical adapter encoding under the existing Relation declaration bounds.
// Common remains the only schema/acquisition/correlation/contract checker.
fn local_project_mock_relation_wire(
  value : Json,
) -> Result[String, @row_host.RowHostIssue] {
  try {
    let canonical = @canonical.from_json(
      value,
      400000,
      64,
      4000000,
      data_keys=true,
    )
    Ok(@canonical.stringify_value(canonical, 4000000, 400000, 64))
  } catch {
    _ => Err(@row_host.RowHostIssue::InvalidSpecification)
  }
}

///|
// Preserve every original view field, translating only the public document
// form into the EXISTING Relation restore API. Unknown fields reach that
// same strict Common reader; the Host introduces no field/type allowlist.
fn local_project_mock_relation_input(
  entry : Json,
) -> Result[String, @row_host.RowHostIssue] {
  guard entry is Object(fields) && fields.get("views") is Some(Array(views)) else {
    return Err(@row_host.RowHostIssue::InvalidSpecification)
  }
  let saved = []
  for view in views {
    guard view is Object(fields) else {
      return Err(@row_host.RowHostIssue::InvalidSpecification)
    }
    let projected : Map[String, Json] = Map([])
    for key, value in fields {
      if key == "schema" {
        let wire = match local_project_mock_relation_wire(value) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        projected["schema_wire"] = Json::string(wire)
        projected["schema_cid"] = Json::string(
          "sha256:" + @sha.hex(@utf8.encode(wire)),
        )
      } else if ["request_schema", "facts", "acquisition", "resource_identity"].contains(
          key,
        ) {
        let wire = match local_project_mock_relation_wire(value) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        projected[key + "_wire"] = Json::string(wire)
      } else if key.has_suffix("_wire") || key == "schema_cid" {
        // A public field cannot inject one of the restore adapter's private
        // destination names. Preserve the unfamiliar field for strict refusal.
        projected["public_input_field:" + key] = value
      } else {
        // Forward instead of dropping unfamiliar fields. Restore decides.
        projected[key] = value
      }
    }
    saved.push(Json::object(projected))
  }
  local_project_mock_relation_wire(
    Json::object(Map([("views", Json::array(saved))])),
  )
}

///|
fn LocalProjectMockDeclarations::prepare_source_declarations(
  self : Self,
) -> Result[Unit, LocalProjectMockModelIssue] {
  if self.closing || self.retired {
    return Err(ForeignOriginal)
  }
  if self.model_failure is Some(issue) {
    return Err(issue)
  }
  if self.sources_started {
    return Err(AlreadyPreparing)
  }
  self.sources_started = true
  if self._retained_catalog.count() != self._retained_connections.count() {
    self.model_failure = Some(
      Source(@row_host.RowHostIssue::InvalidSpecification),
    )
    return Err(self.model_failure.unwrap())
  }
  for index in 0..<self._retained_catalog.count() {
    let (connection, wire) = self._retained_catalog.at(index).unwrap()
    let mut selected = None
    for connection_index in 0..<self._retained_connections.count() {
      if self._retained_connections.at(connection_index).unwrap().0 ==
        connection {
        selected = Some(
          self._retained_connections.at(connection_index).unwrap().1,
        )
      }
    }
    guard selected is Some(provider) else {
      self.model_failure = Some(ForeignOriginal)
      return Err(ForeignOriginal)
    }
    // ClientProjectCatalog already admitted duplicate keys/Unicode and retained
    // this exact entry. No file/payload re-read or provider callback occurs.
    let entry = @json.parse(wire) catch {
      _ => {
        self.model_failure = Some(
          Source(@row_host.RowHostIssue::InvalidSpecification),
        )
        return Err(self.model_failure.unwrap())
      }
    }
    let input = match local_project_mock_relation_input(entry) {
      Ok(value) => value
      Err(issue) => {
        self.model_failure = Some(Source(issue))
        return Err(Source(issue))
      }
    }
    let initial_declaration = match
      @row_host.restore_relation_row_declaration(
        connection,
        "declared_file",
        "declared_file/0.1",
        input,
        None,
      ) {
      Ok(value) => value
      Err(issue) => {
        self.model_failure = Some(Source(issue))
        return Err(Source(issue))
      }
    }
    let files = match
      local_project_mock_file_bindings(
        connection,
        entry,
        initial_declaration,
        self._retained_data_file,
      ) {
      Ok(value) => value
      Err(issue) => {
        self.model_failure = Some(Source(issue))
        return Err(Source(issue))
      }
    }
    let (declaration, files, scope) = match
      local_project_mock_file_declaration(
        connection,
        provider,
        self._retained_catalog.original_wire(),
        entry,
        self._retained_data_file,
        initial_declaration,
        files,
      ) {
      Ok(value) => value
      Err(issue) => {
        self.model_failure = Some(Source(issue))
        return Err(Source(issue))
      }
    }
    let writes = match
      local_project_mock_write_declarations(entry, declaration) {
      Ok(value) => value
      Err(issue) => {
        self.model_failure = Some(Mapping(issue))
        return Err(Mapping(issue))
      }
    }
    let rows = match
      local_project_mock_row_bindings(
        entry,
        declaration,
        files,
        self._retained_data_file,
      ) {
      Ok(value) => value
      Err(issue) => {
        self.model_failure = Some(Source(issue))
        return Err(Source(issue))
      }
    }
    // Keep the same declaration before constructing the next sibling. These
    // are contracts, not installation members, physical Sources or read grants.
    self.sources.push({
      _retained_provider_namespace: provider,
      _retained_connection: connection,
      _retained_entry: entry,
      _retained_scope_cid: scope,
      _retained_declaration: declaration,
      _retained_files: files,
      _retained_rows: rows,
      _retained_writes: writes,
    })
  }
  Ok(())
}
