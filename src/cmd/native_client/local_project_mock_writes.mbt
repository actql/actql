///|
// Original declared write DATA and Common's Mapping, not an installed grant.
// Observe and update permissions retain their separate authored meanings.
priv struct LocalProjectMockWriteDeclaration {
  mapping : @row_host.RowMapping
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
// Mechanical adaptation to the EXISTING closed UPDATE constructor. Common
// checks the complete original Relation and every sibling write specification.
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
  let originals : Array[(String, Array[String], Array[String], String)] = []
  for write in writes {
    guard write is Object(body) &&
      body.length() == 7 &&
      local_project_mock_file_text(write, "resource") is Some(resource) &&
      local_project_mock_file_text(write, "primary_identity") is Some(identity) &&
      local_project_mock_file_text(write, "permission") is Some(permission) &&
      local_project_mock_file_text(write, "observe_permission") is Some(observe) &&
      local_project_mock_file_text(write, "approval") == Some("required") &&
      local_project_mock_write_names(body.get("writable_fields")) is Some(names) &&
      !names.is_empty() &&
      local_project_mock_write_names(body.get("aliases")) is Some(aliases) &&
      !aliases.is_empty() &&
      !originals.any(original => original.0 == resource) else {
      return Err(InvalidSpecification)
    }
    guard data
      .iter()
      .find_first(candidate => {
        local_project_mock_file_text(candidate, "resource") == Some(resource)
      })
      is Some(physical) &&
      local_project_mock_file_text(physical, "primary_identity") ==
      Some(identity) else {
      return Err(InvalidSpecification)
    }
    adapted.push({
      "resource": Json::string(resource),
      "primary_identity": Json::string(identity),
      "update": {
        "fields": Json::array(names.map(Json::string)),
        "permission": Json::string(permission),
        "approval": "required",
      },
    })
    originals.push((resource, names, aliases, observe))
  }
  let wire = match
    local_project_mock_relation_wire({ "writes": Json::array(adapted) }) {
    Ok(value) => value
    Err(_) => return Err(InvalidSpecification)
  }
  let result : Array[LocalProjectMockWriteDeclaration] = []
  for (resource, names, aliases, observe) in originals {
    let mapping = match
      @row_host.prepare_row_update_mapping(
        declaration,
        wire,
        resource,
        names.map(name => {
          target: name,
          field: name,
          null_behavior: "reject",
        }),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    result.push({ mapping, aliases, _retained_observe_permission: observe, })
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
fn LocalProjectMockDeclarations::bind_runtime_writes(
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
  if !self.sources.any(source => !source._retained_writes.is_empty()) {
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
    if source._retained_writes.is_empty() {
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
fn LocalProjectMockDeclarations::update_aliases(self : Self) -> Array[Json] {
  let result : Array[Json] = []
  if self.closing || self.retired || self.model_failure is Some(_) {
    return result
  }
  if self.write_installations is Some(installations) {
    for installation in installations {
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
fn LocalCommandPreparationOriginal::bind_project_mock_writes(
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
    match mock.bind_runtime_writes(runtime, capture, principal) {
      Ok(_) => ()
      Err(issue) => {
        self.retain_primary(CommandProjectMock(issue))
        stop("InvalidProjectBindings")
      }
    }
  }
}
