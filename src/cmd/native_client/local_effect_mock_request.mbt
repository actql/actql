///|
// The SAME six-field original Mock UPDATE request for warm construction and
// saved application. This mechanical projection grants neither target access
// nor dispatch. Callers fund its existing JSON construction before entry.
fn native_mock_effect_update_request_wire(
  binding : String,
  mapping : String,
  target : Json,
  value : Json,
  before : Json,
  version : String,
) -> Result[String, @row_host.RowHostIssue] {
  // Preserve the old combined admission limits and normalization. Splitting
  // this into three separately admitted subtrees would widen that contract.
  let root = @canonical.from_json(
    {
      "binding": Json::string(binding),
      "mapping": Json::string(mapping),
      "target": target,
      "value": value,
      "version": Json::string(version),
      "before": before,
    },
    local_project_mock_relation_wire_nodes,
    local_project_mock_relation_wire_depth,
    local_project_mock_relation_wire_bytes,
    data_keys=true,
  ) catch {
    _ => return Err(@row_host.RowHostIssue::InvalidSpecification)
  }
  guard @canonical.object_field(root, "target") is Some(original_target) &&
    @canonical.object_field(root, "value") is Some(original_value) &&
    @canonical.object_field(root, "before") is Some(original_before) &&
    @canonical.object_field(root, "binding")
    is Some(@canonical.String(original_binding)) &&
    @canonical.object_field(root, "mapping")
    is Some(@canonical.String(original_mapping)) &&
    @canonical.object_field(root, "version")
    is Some(@canonical.String(original_version)) else {
    return Err(@row_host.RowHostIssue::InvalidSpecification)
  }
  @local_host.native_local_effect_update_request_wire(
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
