///|
pub(all) enum EffectSourceArtifactIssue {
  EffectSourceWrongContract
  EffectSourceInvalidBinding
  EffectSourceInvalidMeasurement
  EffectSourceEncoding
  EffectSourceContract(PublicationContractIssue)
} derive(Eq, Debug)

///|
/// Issue the private Artifact for a completed checked Stage Result export.
/// The Host bridge supplies its opaque export receipt's logical identity,
/// schema, and row count; this contract does not itself establish Store custody.
pub fn issue_effect_source_artifact(
  invocation : PublicationContract,
  retention : PublicationContract,
  source_result : String,
  source_binding_cid : String,
  store_authority_cid : String,
  logical_result_cid : String,
  result_schema_cid : String,
  row_count : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectSourceArtifactIssue] {
  if invocation.name != "run_invocation" ||
    retention.name != "result_retention_policy" {
    return Err(EffectSourceWrongContract)
  }
  guard contract_string(retention, "effective_data_policy_cid")
    is Some(data_policy_cid) else {
    return Err(EffectSourceWrongContract)
  }
  guard @canonical.normalize_nfc_lf(source_result) is Ok(normalized) else {
    return Err(EffectSourceInvalidBinding)
  }
  if source_result.is_empty() ||
    normalized != source_result ||
    !valid_contract_cid(source_binding_cid) ||
    !valid_contract_cid(store_authority_cid) ||
    !valid_contract_cid(logical_result_cid) ||
    !valid_contract_cid(result_schema_cid) {
    return Err(EffectSourceInvalidBinding)
  }
  if row_count < 0 {
    return Err(EffectSourceInvalidMeasurement)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(EffectSourceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "actual_completeness")
    @encode.string_value(writer, "complete")
    @encode.key(writer, "actual_row_count")
    @encode.number_value(writer, row_count.to_double())
    @encode.key(writer, "effective_data_policy_cid")
    @encode.string_value(writer, data_policy_cid)
    @encode.key(writer, "effective_retention_policy_cid")
    @encode.string_value(writer, retention.identity)
    @encode.key(writer, "invocation_cid")
    @encode.string_value(writer, invocation.identity)
    @encode.key(writer, "logical_result_cid")
    @encode.string_value(writer, logical_result_cid)
    @encode.key(writer, "provenance_evidence_cids")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.key(writer, "result_schema_cid")
    @encode.string_value(writer, result_schema_cid)
    @encode.key(writer, "source_binding_cid")
    @encode.string_value(writer, source_binding_cid)
    @encode.key(writer, "source_result")
    @encode.string_value(writer, source_result)
    @encode.key(writer, "store_authority_cid")
    @encode.string_value(writer, store_authority_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-effect-source-artifact/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(EffectSourceEncoding)
  }
  let body = @encode.finish(writer) catch {
    _ => return Err(EffectSourceEncoding)
  }
  match
    seal_publication_contract(
      "effect_source_artifact", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(artifact) => Ok(artifact)
    Err(issue) => Err(EffectSourceContract(issue))
  }
}

///|
/// Recover the Preview binding only from the issued source Artifact for the
/// exact Run Invocation and checked source Result. Store custody is a separate
/// obligation and is not established by this projection.
pub fn effect_source_artifact_preview_binding(
  artifact : PublicationContract,
  invocation_cid : String,
  source_result : String,
  store_authority_cid : String,
) -> Result[(String, String), EffectSourceArtifactIssue] {
  if artifact.name != "effect_source_artifact" ||
    !valid_contract_cid(invocation_cid) ||
    !valid_contract_cid(store_authority_cid) ||
    contract_string(artifact, "invocation_cid") != Some(invocation_cid) ||
    contract_string(artifact, "source_result") != Some(source_result) ||
    contract_string(artifact, "store_authority_cid") !=
    Some(store_authority_cid) {
    return Err(EffectSourceWrongContract)
  }
  guard contract_string(artifact, "source_binding_cid") is Some(binding) &&
    valid_contract_cid(binding) else {
    return Err(EffectSourceInvalidBinding)
  }
  Ok((artifact.identity, binding))
}
