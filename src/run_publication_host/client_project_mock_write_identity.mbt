///|
// The file declaration's canonical identity is static DATA. Keep the exact
// authored catalog wire and locator separate from the current Account scope.
pub fn client_project_mock_declared_file_scope(
  connection : String,
  provider : String,
  data_file : String,
  catalog_wire : String,
) -> Result[String, @row_host.RowHostIssue] {
  try {
    let writer = @encode.writer(4000000, 400000, 64)
    @encode.begin_object(writer)
    for
      (key, text) in [
        ("catalog", catalog_wire),
        ("connection", connection),
        ("connector", provider),
        ("dataPath", data_file),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, text)
    }
    @encode.end_object(writer)
    Ok("sha256:" + @sha.hex(@utf8.encode(@encode.finish(writer))))
  } catch {
    _ => Err(InvalidSpecification)
  }
}

///|
// Preserve the checked Mapping order of the original Project declaration.
// The Host obtains the authority scope from its own current installed Read.
pub fn client_project_mock_write_binding_cid(
  source_scope : String,
  authority_scope : String,
  writes : Array[@row_host.ProjectMockWriteDeclaration],
) -> Result[String, @row_host.RowHostIssue] {
  try {
    let writer = @encode.writer(4000000, 400000, 64)
    @encode.begin_object(writer)
    @encode.key(writer, "authority_scope_cid")
    @encode.string_value(writer, authority_scope)
    @encode.key(writer, "mapping_cids")
    @encode.begin_array(writer)
    for write in writes {
      @encode.string_value(writer, write.mapping.mapping_cid)
    }
    @encode.end_array(writer)
    @encode.key(writer, "source_scope_cid")
    @encode.string_value(writer, source_scope)
    @encode.end_object(writer)
    Ok("sha256:" + @sha.hex(@utf8.encode(@encode.finish(writer))))
  } catch {
    _ => Err(InvalidSpecification)
  }
}

///|
/// Admit the selected typed RowEffect facts in the existing installation
/// owner. This uses the same canonical wire as the untrusted wire entrance.
pub fn client_project_mock_write_installation(
  declaration : @row_host.RowDeclaration,
  connection : String,
  runtime_cid : String,
  binding : String,
) -> Result[(String, String), ClientEffectUpdateTargetIssue] {
  issue_client_effect_target_installation_data([
    binding,
    connection,
    declaration.connector_registration,
    declaration.connector_version,
    binding,
    "actql-installed-row-effect-continuation/0.1",
    "binding_cid",
    "actql-installed-row-effect-dispatch/0.1",
    "actql-installed-row-effect-recovery/0.1",
    "actql-installed-row-effect-source/0.1",
    "actql-installed-row-effect-check/0.1",
    "actql-installed-row-effect-unit/0.1",
    runtime_cid,
  ]).map(value => (value.0, value.1))
}

///|
/// The exact target of the admitted Mapping. Published alias spellings never
/// supply the connector target or alter the installation preimage.
pub fn client_project_mock_write_target(
  write : @row_host.ProjectMockWriteDeclaration,
) -> String? {
  let body = @json.parse(write.mapping.body) catch { _ => return None }
  guard body is Object(fields) &&
    fields.get("target_ref") is Some(String(target)) else {
    return None
  }
  Some(target)
}

///|
/// The same closed publication entry for the Native and Wasm Host adapters.
pub fn client_project_mock_write_alias(
  name : String,
  target : String,
  binding : String,
  owner : String,
) -> Json {
  {
    "name": Json::string(name),
    "targetRef": Json::string(target),
    "installationBindingCid": Json::string(binding),
    "installationOwnerCid": Json::string(owner),
  }
}
