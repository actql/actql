///|
/// Content-level correspondence only; the Host issuer separately checks the
/// exact captured owners, approved target and current authority.
pub fn table_operation_matches_input(
  value : TableOperation,
  scope : @request_scope.LogicalRequestScope,
  effect_cid : String,
  artifact_cid : String,
  kind : @carrier.Kind,
  carrier_cid : String,
  mapping : StorageMappingReference,
  data_policy_cid : String,
) -> Bool {
  value.input_kind == kind &&
  mapping.kind == kind &&
  value.scope_cid == @request_scope.logical_request_scope_cid(scope) &&
  value.effect_cid == effect_cid &&
  value.input_artifact_cid == artifact_cid &&
  value.input_carrier_cid == carrier_cid &&
  value.schema_cid == mapping.schema_cid &&
  value.mapping_cid == mapping.cid &&
  value.data_policy_cid == data_policy_cid
}

///|
pub fn table_operation_cid(value : TableOperation) -> String {
  value.cid
}

///|
pub fn table_operation_json(value : TableOperation) -> String {
  value.wire
}
