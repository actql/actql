///|
/// Project immutable Source facts only for its original Run-bound holding.
/// This is not Store availability, current authorization or execution proof.
pub fn captured_effect_source_payload_facts(
  source : CapturedEffectSourceArtifact,
  run_definition : PublicationContract,
) -> (String, String, Int64, String)? {
  if run_definition.name != "run_definition" ||
    effect_source_artifact_holding_cid(
      source.artifact,
      source.effect_id,
      run_definition.identity,
      captured_effect_source_store_authority_cid(source),
    ) !=
    Some(source.holding_cid) {
    return None
  }
  guard contract_string(source.artifact, "logical_result_cid") is Some(logical) &&
    contract_string(source.artifact, "result_schema_cid") is Some(schema) &&
    contract_count(source.artifact, "actual_row_count") is Some(rows) &&
    contract_string(source.artifact, "invocation_cid") is Some(invocation) else {
    return None
  }
  Some((logical, schema, rows, invocation))
}

///|
pub fn captured_effect_source_effect_id(
  source : CapturedEffectSourceArtifact,
) -> String {
  source.effect_id
}

///|
pub fn captured_effect_source_artifact_json(
  source : CapturedEffectSourceArtifact,
) -> String {
  publication_contract_json(source.artifact)
}
