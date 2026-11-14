///|
/// Fix physical Source custody to the exact checked member and completed
/// local export. Generic Store payload metadata alone cannot establish that
/// this Result belongs to the original Run or Effect occurrence.
pub fn client_effect_source_payload_binding(
  materials : ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  artifact : ClientEffectLocalResultArtifact,
  source : @publication.CapturedEffectSourceArtifact,
  request : @payload.PublicationPayloadRequest,
) -> Result[(String, Int), ClientEffectSourceArtifactIssue] {
  let owner = materials.prepared
  if !physical_equal(materials.compilation.owner, owner) ||
    !physical_equal(materials.compilation, materials.allowed.compilation) ||
    !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) ||
    !client_effect_local_artifact_matches_inputs(artifact, inputs) ||
    !client_effect_local_artifact_matches_member(artifact, inputs, member_index) {
    return Err(ForeignInput)
  }
  let run = @publication.publication_contract_identity(materials.run_definition)
  if @strategy.captured_effect_inputs_run_definition_cid(inputs) != Some(run) ||
    client_effect_local_artifact_run_definition_cid(artifact) != Some(run) {
    return Err(ForeignRun)
  }
  guard @publication.captured_effect_source_payload_facts(
      source,
      materials.run_definition,
    )
    is Some((logical, schema, rows, invocation)) else {
    return Err(ForeignRun)
  }
  if client_effect_local_artifact_run_invocation_cid(artifact) !=
    Some(invocation) {
    return Err(ForeignInvocation)
  }
  guard artifact.source is ResultSource(_, definition) &&
    @strategy.captured_effect_input_at(inputs, member_index) is Some(input) &&
    @syntax.effect_header_at(
      @checked.effect_program_static_headers(owner.candidate),
      member_index,
    )
    is Some(header) else {
    return Err(ForeignInput)
  }
  let name = @execution.managed_result_occurrence_name(
    @strategy.captured_effect_input_occurrence(input),
  )
  if @syntax.effect_header_id(header) !=
    @publication.captured_effect_source_effect_id(source) ||
    !@publication.captured_effect_source_matches_result_facts(
      source,
      artifact.artifact,
      name,
    ) ||
    !client_effect_local_result_definition_matches(
      definition,
      owner,
      @strategy.captured_effect_input_stage(input),
      name,
    ) ||
    @payload.publication_payload_request_store_authority(request) !=
    @publication.captured_effect_source_store_authority_cid(source) ||
    @payload.publication_payload_request_result_definition(request) !=
    definition.cid ||
    @payload.publication_payload_request_ordering_evidence(request) !=
    @publication.publication_contract_identity(
      @publication.result_ordering_evidence_contract(artifact.evidence),
    ) ||
    @payload.publication_payload_request_logical_relation(request) != logical ||
    @payload.publication_payload_request_schema(request) != schema ||
    @payload.publication_payload_request_row_count(request) != rows ||
    artifact.physical_bytes.to_int64() >
    @payload.publication_payload_request_max_bytes(request) {
    return Err(ForeignInput)
  }
  Ok((artifact.physical_cid, artifact.physical_bytes))
}
