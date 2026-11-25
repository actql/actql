///|
// Original declared write DATA and Common's Mapping, not an installed grant.
// Observe and write permissions retain their separate authored meanings.
priv struct LocalProjectMockWriteDeclaration {
  mapping : @row_host.RowMapping
  operation : String
  writable_fields : Array[String]
  aliases : Array[String]
  _retained_observe_permission : String
}

///|
fn local_project_mock_write_names(value : Json?) -> Array[String]? {
  guard value is Some(Array(values)) else { return None }
  let names : Array[String] = []
  for value in values {
    guard value is String(name) &&
      !name.is_empty() &&
      !name.contains("\u{0000}") &&
      !names.contains(name) else {
      return None
    }
    names.push(name)
  }
  Some(names)
}

///|
fn local_project_mock_write_null_fields_valid(
  value : Json?,
  writable : Array[String],
) -> Bool {
  match value {
    None => true
    Some(Array(fields)) => {
      if fields.length() > writable.length() {
        return false
      }
      for index, field in fields {
        guard field is String(name) && writable.contains(name) else {
          return false
        }
        for previous in 0..<index {
          if fields[previous] == field {
            return false
          }
        }
      }
      true
    }
    _ => false
  }
}

///|
fn local_project_mock_write_null_selected(value : Json?, name : String) -> Bool {
  guard value is Some(Array(fields)) else { return false }
  for field in fields {
    if field is String(selected) && selected == name {
      return true
    }
  }
  false
}

///|
// Adapt the closed Catalog file-write forms. Common checks the
// complete original Relation and every sibling write specification.
fn local_project_mock_write_declarations(
  entry : Json,
  declaration : @row_host.RowDeclaration,
) -> Result[Array[LocalProjectMockWriteDeclaration], @row_host.RowMappingIssue] {
  guard entry is Object(fields) else { return Err(InvalidSpecification) }
  let writes = match fields.get("writes") {
    None => return Ok([])
    Some(Array(values)) => values
    _ => return Err(InvalidSpecification)
  }
  if writes.is_empty() {
    return Ok([])
  }
  guard fields.get("data") is Some(Array(data)) else {
    return Err(InvalidSpecification)
  }
  let adapted : Array[Json] = []
  let originals : Array[
    (String, String, Array[String], Array[String], Array[String], String),
  ] = []
  for write in writes {
    guard write is Object(body) else { return Err(InvalidSpecification) }
    let operation = match body.get("operation") {
      None | Some(String("update")) => "update"
      Some(String("delete")) => "delete"
      Some(String("create")) => "create"
      Some(String("upsert")) => "upsert"
      _ => return Err(InvalidSpecification)
    }
    guard local_project_mock_file_text(write, "resource") is Some(resource) &&
      body.get("primary_identity") is Some(identity) &&
      (
        identity is Object(_) ||
        local_project_mock_file_text(write, "primary_identity") is Some(_)
      ) &&
      local_project_mock_file_text(write, "permission") is Some(permission) &&
      local_project_mock_file_text(write, "observe_permission") is Some(observe) &&
      local_project_mock_file_text(write, "approval") == Some("required") &&
      local_project_mock_write_names(body.get("aliases")) is Some(aliases) &&
      !aliases.is_empty() else {
      return Err(InvalidSpecification)
    }
    let (names, selected) = if operation == "delete" {
      // The six common properties and operation exhaust the DELETE object.
      guard body.length() == 7 else { return Err(InvalidSpecification) }
      let fields : Array[String] = []
      (fields, fields)
    } else {
      let optional_count = (if body.get("write_null_fields") is Some(_) {
          1
        } else {
          0
        }) +
        (if body.get("update_fields") is Some(_) { 1 } else { 0 }) +
        (if body.get("operation") is Some(_) { 1 } else { 0 })
      guard body.length() == 7 + optional_count &&
        local_project_mock_write_names(body.get("writable_fields"))
        is Some(names) &&
        !names.is_empty() &&
        local_project_mock_write_null_fields_valid(
          body.get("write_null_fields"),
          names,
        ) else {
        return Err(InvalidSpecification)
      }
      let selected = match body.get("update_fields") {
        None => names
        Some(value) => {
          guard operation == "update" &&
            local_project_mock_write_names(Some(value)) is Some(fields) &&
            !fields.is_empty() &&
            fields.all(name => names.contains(name)) else {
            return Err(InvalidSpecification)
          }
          fields
        }
      }
      (names, selected)
    }
    guard data
      .iter()
      .find_first(candidate => {
        local_project_mock_file_text(candidate, "resource") == Some(resource)
      })
      is Some(Object(physical)) &&
      physical.get("primary_identity") == Some(identity) else {
      return Err(InvalidSpecification)
    }
    let specification : Json = if operation == "delete" {
      { "permission": Json::string(permission), "approval": "required" }
    } else {
      {
        "fields": Json::array(names.map(Json::string)),
        "permission": Json::string(permission),
        "approval": "required",
      }
    }
    let facts : Json = match
      adapted
      .iter()
      .find_first(candidate => {
        local_project_mock_file_text(candidate, "resource") == Some(resource)
      }) {
      Some(value) => value
      None => {
        let value : Json = {
          "resource": Json::string(resource),
          "primary_identity": identity,
        }
        adapted.push(value)
        value
      }
    }
    guard facts is Object(fields) && fields.get(operation) is None else {
      return Err(InvalidSpecification)
    }
    fields[operation] = specification
    originals.push((resource, operation, names, selected, aliases, observe))
  }
  let wire = match
    local_project_mock_relation_wire({ "writes": Json::array(adapted) }) {
    Ok(value) => value
    Err(_) => return Err(InvalidSpecification)
  }
  let result : Array[LocalProjectMockWriteDeclaration] = []
  for
    index, (resource, operation, names, selected, aliases, observe) in originals {
    let null_fields = match writes[index] {
      Object(body) => body.get("write_null_fields")
      _ => None
    }
    let admitted = if operation == "delete" {
      @row_host.prepare_row_delete_mapping_from_writes(
        declaration, wire, resource,
      )
    } else {
      let sources : Array[@row_host.RowMappingSource] = selected.map(name => {
        target: name,
        field: name,
        null_behavior: if local_project_mock_write_null_selected(
            null_fields, name,
          ) {
          "write_null"
        } else {
          "reject"
        },
      })
      match operation {
        "create" =>
          @row_host.prepare_row_file_create_mapping(
            declaration, wire, resource, sources,
          )
        "update" =>
          @row_host.prepare_row_update_mapping(
            declaration, wire, resource, sources,
          )
        "upsert" =>
          @row_host.prepare_row_file_upsert_mapping(
            declaration, wire, resource, sources,
          )
        _ => Err(InvalidSpecification)
      }
    }
    let mapping = match admitted {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let writable_fields = if selected.length() == names.length() {
      mapping.write_fields
    } else {
      names
    }
    result.push({
      mapping,
      operation,
      writable_fields,
      aliases,
      _retained_observe_permission: observe,
    })
  }
  Ok(result)
}

///|
// Same selected implementation originals, retained by the command's Project.
// Common's owner wire is identity DATA; Account/claim/current stay independent.
priv struct LocalProjectMockWriteInstallation {
  _retained_source : LocalProjectMockSourceDeclaration
  write : LocalProjectMockWriteDeclaration
  binding : String
  owner : (String, String)
  target : String
}

///|
fn LocalProjectMockWriteInstallation::matches_file_operation(
  self : Self,
  operation : String,
) -> Bool {
  match operation {
    "create" | "update" | "delete" | "upsert" =>
      self.write.operation == operation
    _ => false
  }
}

///|
fn LocalProjectMockWriteInstallation::file_target_read_capacity(
  self : Self,
  provider : @row_file.NativeRelationFilePreparedProvider,
  response_bytes? : Int? = None,
  ordered_wire_utf16? : Int? = None,
) -> @execution.ExecutionCapacity? {
  if self.write.writable_fields.is_empty() {
    @row_file.native_relation_file_delete_target_read_io_capacity(
      provider,
      response_bytes~,
      ordered_wire_utf16~,
    )
  } else {
    @row_file.native_relation_file_target_read_io_capacity(
      provider,
      self.write.writable_fields.length(),
      response_bytes~,
      ordered_wire_utf16~,
    )
  }
}

///|
// Pure metadata projection of the selected implementation. These inputs issue
// no Runtime, Read, Account or grant. The actual caller obtains them only from
// its SAME runtime manifest and adopted Read before using this projection.
fn local_project_mock_write_installations(
  source : LocalProjectMockSourceDeclaration,
  runtime_cid : String,
  scope : String,
) -> Result[
  Array[LocalProjectMockWriteInstallation],
  LocalProjectMockModelIssue,
] {
  let result : Array[LocalProjectMockWriteInstallation] = []
  let binding = match
    local_project_mock_file_cid({
      "source_scope_cid": Json::string(source._retained_scope_cid),
      "authority_scope_cid": Json::string(scope),
      "mapping_cids": Json::array(
        source._retained_writes.map(write => {
          Json::string(write.mapping.mapping_cid)
        }),
      ),
    }) {
    Ok(value) => value
    Err(issue) => return Err(Source(issue))
  }
  let facts : Json = {
    "connector_registration": Json::string(
      source._retained_declaration.connector_registration,
    ),
    "connector_revision": Json::string(
      source._retained_declaration.connector_version,
    ),
    "runtime_bundle_cid": Json::string(runtime_cid),
    "binding_cid": Json::string(binding),
    "connection": Json::string(source._retained_connection),
    "continuation_binding": Json::string(binding),
    "profile": {
      "continuation": "actql-installed-row-effect-continuation/0.1",
      "continuationBinding": "binding_cid",
      "dispatch": "actql-installed-row-effect-dispatch/0.1",
      "recovery": "actql-installed-row-effect-recovery/0.1",
      "source": "actql-installed-row-effect-source/0.1",
      "targetCheck": "actql-installed-row-effect-check/0.1",
      "unit": "actql-installed-row-effect-unit/0.1",
    },
  }
  let wire = match local_project_mock_relation_wire(facts) {
    Ok(value) => value
    Err(issue) => return Err(Source(issue))
  }
  let owner = match @run_host.issue_client_effect_target_installation(wire) {
    Ok(value) => value
    Err(issue) => return Err(WriteInstallation(issue))
  }
  for write in source._retained_writes {
    // Target identity comes from Common's SAME full Mapping, never its alias.
    let body = @json.parse(write.mapping.body) catch { _ => Json::null() }
    let target = match body {
      Object(fields) => fields.get("target_ref")
      _ => None
    }
    guard target is Some(String(target)) else { return Err(ForeignOriginal) }
    result.push({ _retained_source: source, write, binding, owner, target, })
  }
  Ok(result)
}

///|
fn LocalProjectMockDeclarations::bind_runtime(
  self : Self,
  runtime : @local_host.NativeLocalPackagedRuntime,
  capture : @local_host.NativeLocalJournalCapture,
  principal : String,
) -> Result[Unit, LocalProjectMockModelIssue] {
  if self.closing || self.retired || !self.sources_started {
    return Err(ForeignOriginal)
  }
  if self.model_failure is Some(issue) {
    return Err(issue)
  }
  if self.writes_started {
    return if self.write_runtime is Some(original_runtime) &&
      self.write_capture is Some(original_capture) &&
      physical_equal(original_runtime, runtime) &&
      physical_equal(original_capture, capture) &&
      self.write_principal == Some(principal) {
      Ok(())
    } else {
      Err(ForeignOriginal)
    }
  }
  if !self.sources.any(source => {
      !source._retained_writes.is_empty() || !source._retained_files.is_empty()
    }) {
    return Ok(())
  }
  if self.source_environment is Some(_) ||
    self.model_environment is Some(_) ||
    self.publication is Some(_) {
    return Err(ForeignOriginal)
  }
  // Retain the SAME attempted selection before any original Read operation.
  self.writes_started = true
  self.write_runtime = Some(runtime)
  self.write_capture = Some(capture)
  self.write_principal = Some(principal)
  self.write_installations = Some([])
  self.file_sources = Some([])
  let refuse = issue => {
    self.model_failure = Some(issue)
    Err(issue)
  }
  // The normal installed Runtime already owns this exact manifest. A full
  // product/upgrade observation is separate, not another Run prerequisite.
  let manifest = match runtime.manifest() {
    Ok(value) => value
    Err(issue) => return refuse(Runtime(issue))
  }
  self._retained_write_manifest = Some(manifest)
  let runtime_cid = "sha256:" +
    @sha.hex(
      @utf8.encode(@run_host.client_native_local_runtime_original(manifest)),
    )
  for source in self.sources {
    // A cold approved write has no Model/Source execution originals. Do not
    // issue new ResourceRef identities or rebuild unused file listing hooks.
    let source_files = self._retained_registry is Some(_) &&
      !source._retained_files.is_empty()
    if source._retained_writes.is_empty() && !source_files {
      continue
    }
    let scope = match
      capture.authority_scope_cid_in_original_read(
        principal,
        source._retained_connection,
      ) {
      Ok(value) => value
      Err(issue) => return refuse(WriteHost(issue))
    }
    // The original Host operation may observe retirement. Do not attach new
    // Source or write holders after that boundary; no second I/O check is needed.
    if self.closing || self.retired || self.file_sources is None {
      return refuse(ForeignOriginal)
    }
    if source_files {
      let files = match local_project_mock_file_source(source, scope) {
        Ok(value) => value
        Err(issue) => return refuse(Source(issue))
      }
      self.file_sources.unwrap().push(files)
    }
    let installations = match
      local_project_mock_write_installations(source, runtime_cid, scope) {
      Ok(value) => value
      Err(issue) => return refuse(issue)
    }
    for installation in installations {
      self.write_installations.unwrap().push(installation)
    }
  }
  Ok(())
}

///|
fn LocalProjectMockDeclarations::update_aliases(
  self : Self,
  visible? : ((LocalProjectMockSourceDeclaration, String) -> Bool)? = None,
) -> Array[Json] {
  let result : Array[Json] = []
  if self.closing || self.retired || self.model_failure is Some(_) {
    return result
  }
  if self.write_installations is Some(installations) {
    for installation in installations {
      if visible is Some(disclose) &&
        !disclose(
          installation._retained_source,
          installation.write.mapping.resource,
        ) {
        continue
      }
      for name in installation.write.aliases {
        result.push({
          "name": Json::string(name),
          "targetRef": Json::string(installation.target),
          "installationBindingCid": Json::string(installation.binding),
          "installationOwnerCid": Json::string(installation.owner.0),
        })
      }
    }
  }
  result
}

///|
fn LocalCommandPreparationOriginal::bind_project_mock_runtime(
  self : Self,
  runtime : @local_host.NativeLocalPackagedRuntime,
  capture : @local_host.NativeLocalJournalCapture,
  principal : String,
) -> Unit raise ClientStop {
  if self.project is Some(project) && project.mock_declarations is Some(mock) {
    guard self.runtime is Some(original_runtime) &&
      physical_equal(original_runtime, runtime) &&
      self.journal is Some(original_capture) &&
      physical_equal(original_capture, capture) &&
      self.journal_read_open &&
      !self.closing &&
      !self.closed else {
      stop("LocalBusinessOriginalUnavailable")
    }
    match mock.bind_runtime(runtime, capture, principal) {
      Ok(_) => ()
      Err(issue) => {
        self.retain_primary(CommandProjectMock(issue))
        stop("InvalidProjectBindings")
      }
    }
  }
}
