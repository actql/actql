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
  issue_effect_relation_source_artifact(
    invocation,
    retention,
    Result(source_result),
    source_binding_cid,
    store_authority_cid,
    logical_result_cid,
    result_schema_cid,
    row_count,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Issue a physical source for a checked private Table input. The separate
/// source namespace preserves Conditional presence without publishing a Result.
/// Export facts do not establish live Store custody or permission to commit.
pub fn issue_effect_table_input_artifact(
  invocation : PublicationContract,
  retention : PublicationContract,
  table_input : String,
  source_binding_cid : String,
  store_authority_cid : String,
  logical_result_cid : String,
  result_schema_cid : String,
  row_count : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, EffectSourceArtifactIssue] {
  issue_effect_relation_source_artifact(
    invocation,
    retention,
    TableInput(table_input),
    source_binding_cid,
    store_authority_cid,
    logical_result_cid,
    result_schema_cid,
    row_count,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn issue_effect_relation_source_artifact(
  invocation : PublicationContract,
  retention : PublicationContract,
  source : EffectPreviewRelationSource,
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
  let (source_field, source_name) = match source {
    Result(name) => ("source_result", name)
    TableInput(name) => ("source_table_input", name)
  }
  guard @canonical.normalize_nfc_lf(source_name) is Ok(normalized) else {
    return Err(EffectSourceInvalidBinding)
  }
  if source_name.is_empty() ||
    normalized != source_name ||
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
    @encode.key(writer, source_field)
    @encode.string_value(writer, source_name)
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
  effect_relation_source_artifact_preview_binding(
    artifact,
    invocation_cid,
    Result(source_result),
    store_authority_cid,
  )
}

///|
pub fn effect_table_input_artifact_preview_binding(
  artifact : PublicationContract,
  invocation_cid : String,
  table_input : String,
  store_authority_cid : String,
) -> Result[(String, String), EffectSourceArtifactIssue] {
  effect_relation_source_artifact_preview_binding(
    artifact,
    invocation_cid,
    TableInput(table_input),
    store_authority_cid,
  )
}

///|
fn effect_source_artifact_relation_source(
  artifact : PublicationContract,
) -> EffectPreviewRelationSource? {
  if artifact.name != "effect_source_artifact" {
    return None
  }
  match
    (
      contract_string(artifact, "source_result"),
      contract_string(artifact, "source_table_input"),
    ) {
    (Some(name), None) => Some(Result(name))
    (None, Some(name)) => Some(TableInput(name))
    _ => None
  }
}

///|
fn effect_relation_source_artifact_preview_binding(
  artifact : PublicationContract,
  invocation_cid : String,
  source : EffectPreviewRelationSource,
  store_authority_cid : String,
) -> Result[(String, String), EffectSourceArtifactIssue] {
  if artifact.name != "effect_source_artifact" ||
    !valid_contract_cid(invocation_cid) ||
    !valid_contract_cid(store_authority_cid) ||
    contract_string(artifact, "invocation_cid") != Some(invocation_cid) ||
    effect_source_artifact_relation_source(artifact) != Some(source) ||
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

///|
/// Read the original captured physical source's selected retention identity.
/// Full computation-chain admission remains with its original caller. This
/// borrowed DATA is neither a new retention contract nor a Store holding.
pub fn captured_run_effect_source_retention_cid(
  captured : PublicationContract,
  effect_id : String,
) -> String? {
  guard captured.name == "captured_run" &&
    @json.object_field(captured.value, "effect_context") is Some(context) &&
    @json.object_field(context, "effect_source_artifacts") is Some(sources) &&
    @json.object_field(sources, effect_id) is Some(source) else {
    return None
  }
  optional_string(@json.object_field(source, "effective_retention_policy_cid"))
}
