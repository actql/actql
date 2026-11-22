///|
// Admit one bounded canonical request. DELETE uses the same five original
// identity/guard fields without an authored value. Callers fund construction.
fn native_mock_effect_file_request_wire(
  binding : String,
  mapping : String,
  target : Json,
  value : Json,
  before : Json,
  version : String,
  deleting? : Bool = false,
) -> Result[String, @row_host.RowHostIssue] {
  if deleting && !(value is Null) {
    return Err(@row_host.RowHostIssue::InvalidSpecification)
  }
  let request : Json = {
    "binding": Json::string(binding),
    "mapping": Json::string(mapping),
    "target": target,
    "value": value,
    "version": Json::string(version),
    "before": before,
  }
  if deleting && request is Object(fields) {
    ignore(fields.remove("value"))
  }
  // Preserve the combined admission limits and normalization.
  let root = @canonical.from_json(
    request,
    local_project_mock_relation_wire_nodes,
    local_project_mock_relation_wire_depth,
    local_project_mock_relation_wire_bytes,
    data_keys=true,
  ) catch {
    _ => return Err(@row_host.RowHostIssue::InvalidSpecification)
  }
  guard @canonical.object_field(root, "target") is Some(original_target) &&
    @canonical.object_field(root, "before") is Some(original_before) &&
    @canonical.object_field(root, "binding")
    is Some(@canonical.String(original_binding)) &&
    @canonical.object_field(root, "mapping")
    is Some(@canonical.String(original_mapping)) &&
    @canonical.object_field(root, "version")
    is Some(@canonical.String(original_version)) else {
    return Err(@row_host.RowHostIssue::InvalidSpecification)
  }
  let original_value = @canonical.object_field(root, "value")
  if deleting != (original_value is None) {
    return Err(@row_host.RowHostIssue::InvalidSpecification)
  }
  @local_host.native_local_effect_file_request_wire(
    original_binding, original_mapping, original_target, original_value, original_before,
    original_version, local_project_mock_relation_wire_bytes, local_project_mock_relation_wire_nodes,
    local_project_mock_relation_wire_depth,
  ).map_err(_ => @row_host.RowHostIssue::InvalidSpecification)
}

///|
// Same command-owned original request. The physical child/ACK is retained on
// the consuming operation separately; a request body alone permits no send.
priv struct LocalNativeSavedEffectFileRow {
  _retained_member_index : Int
  _retained_row_ordinal : Int
  _retained_installation : LocalProjectMockWriteInstallation
  _retained_row_binding : LocalProjectMockRowBinding
  request_wire : String
  request_cid : String
  target_cid : String
  outcome_template : String
  identity : String
  changes_wire : String
  version : String
}

///|
fn LocalNativeSavedEffectFileRow::deleting(self : Self) -> Bool {
  self._retained_installation.write.writable_fields.is_empty()
}

///|
fn LocalNativeSavedEffectFileRow::file_write_construction(
  self : Self,
  bytes : Int,
) -> (@execution.ExecutionCapacity, Int64)? {
  let provider = self._retained_row_binding.provider
  if self.deleting() {
    @row_file.native_relation_file_target_delete_construction(provider, bytes)
  } else {
    @row_file.native_relation_file_target_update_construction(
      provider,
      self._retained_installation.write.writable_fields.length(),
      bytes,
      self.changes_wire,
    )
  }
}
