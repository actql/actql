///|
/// Content-level correspondence only; the Host issuer separately checks the
/// exact captured owners, approved target and current authority.
pub fn table_operation_matches_input(
  value : TableOperation,
  scope : @request_scope.LogicalRequestScope,
  effect_cid : String,
  artifact_cid : String,
  relation_cid : String,
  mapping : StorageMappingReference,
  data_policy_cid : String,
) -> Bool {
  mapping.kind == @carrier.RelationKind &&
  value.scope_cid == @request_scope.logical_request_scope_cid(scope) &&
  value.effect_cid == effect_cid &&
  value.input_artifact_cid == artifact_cid &&
  value.input_relation_cid == relation_cid &&
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
