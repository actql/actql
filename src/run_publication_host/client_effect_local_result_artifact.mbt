///|
pub(all) enum ClientEffectLocalResultArtifactIssue {
  ForeignOwner
  MissingInput
  ForeignDefinition
  ForeignInvocation
  ForeignExport
  Evidence(@publication.ResultEvidenceIssuanceIssue)
  Artifact(@publication.ResultArtifactIssuanceIssue)
} derive(Eq, Debug)

///|
/// Local semantic Artifact and its exact witnesses. Store custody and the
/// current right to consume the captured Result remain separate obligations.
struct ClientEffectLocalResultArtifact {
  inputs : @strategy.CapturedEffectInputs
  member_index : Int
  definition : ClientEffectLocalResultDefinition
  invocation : ClientEffectLocalInvocation
  evidence : @publication.ResultOrderingEvidence
  artifact : @publication.PublicationContract
}

///|
/// Issue only from the checked source-free Unit and its live Effect input pin.
/// The physical adapter supplies admitted scope and retention contracts, as
/// on Run-bound publication; the surrounding chain must resolve those refs.
pub fn issue_source_free_client_effect_local_result_artifact(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  importing_input : @strategy.CapturedEffectInput,
  importing_output : @execution.ManagedCompletedOutput[Int],
  importing_bridge : @execution.ManagedPublicationBridge[Int],
  preparation : @execution.CompletedResultRelationExportPreparation,
  definition : ClientEffectLocalResultDefinition,
  invocation : ClientEffectLocalInvocation,
  receipt : @execution.CompletedRelationExportReceipt,
  retention : @publication.PublicationContract,
  scope_cid : String,
  effective_data_policy_cid : String,
  authority_scope_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientEffectLocalResultArtifact,
  ClientEffectLocalResultArtifactIssue,
] {
  if !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) {
    return Err(ForeignOwner)
  }
  guard @strategy.captured_effect_input_at(inputs, member_index) is Some(input) else {
    return Err(MissingInput)
  }
  let unit = @strategy.captured_effect_input_stage(input)
  let result_name = @execution.managed_result_occurrence_name(
    @strategy.captured_effect_input_occurrence(input),
  )
  if !client_effect_local_result_definition_matches(
      definition, owner, unit, result_name,
    ) {
    return Err(ForeignDefinition)
  }
  if !client_effect_local_invocation_matches(invocation, owner, unit) {
    return Err(ForeignInvocation)
  }
  if !physical_equal(importing_input, input) ||
    !@strategy.captured_effect_input_matches_managed(input, importing_output) ||
    !@execution.managed_publication_bridge_matches_result_export(
      importing_bridge,
      importing_output,
      preparation,
      @strategy.captured_effect_input_occurrence(input),
    ) ||
    !@execution.completed_result_export_preparation_matches_receipt(
      preparation, receipt,
    ) {
    return Err(ForeignExport)
  }
  let evidence = match
    @publication.issue_local_result_occurrence_evidence(
      definition.cid,
      @execution.logical_relation_cid(
        @execution.completed_relation_export_identity(receipt),
      ),
      @execution.relation_schema_cid(
        @execution.completed_relation_export_schema_identity(receipt),
      ),
      definition.unit_definition_cid,
      [],
      scope_cid,
      effective_data_policy_cid,
      "actql-common-host",
      authority_scope_cid,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let artifact = match
    @publication.issue_complete_local_result_artifact(
      definition.cid,
      invocation.cid,
      evidence,
      retention,
      @execution.completed_relation_export_measurement(receipt).row_count,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Artifact(issue))
  }
  Ok({ inputs, member_index, definition, invocation, evidence, artifact, })
}

///|
pub fn client_effect_local_result_artifact_cid(
  value : ClientEffectLocalResultArtifact,
) -> String {
  @publication.publication_contract_identity(value.artifact)
}

///|
pub fn client_effect_local_artifact_definition_cid(
  value : ClientEffectLocalResultArtifact,
) -> String {
  value.definition.cid
}

///|
pub fn client_effect_local_artifact_invocation_cid(
  value : ClientEffectLocalResultArtifact,
) -> String {
  value.invocation.cid
}

///|
pub fn client_effect_local_result_artifact_json(
  value : ClientEffectLocalResultArtifact,
) -> String {
  @publication.publication_contract_json(value.artifact)
}

///|
pub fn client_effect_local_result_derivation_json(
  value : ClientEffectLocalResultArtifact,
) -> String {
  @publication.publication_contract_json(
    @publication.result_ordering_derivation_contract(value.evidence),
  )
}

///|
pub fn client_effect_local_result_ordering_json(
  value : ClientEffectLocalResultArtifact,
) -> String {
  @publication.publication_contract_json(
    @publication.result_ordering_evidence_contract(value.evidence),
  )
}
