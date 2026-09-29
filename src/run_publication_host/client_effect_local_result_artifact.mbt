///|
pub(all) enum ClientEffectLocalResultArtifactIssue {
  ForeignOwner
  MissingInput
  ForeignDefinition
  ForeignInvocation
  ForeignExport
  ForeignRun
  Context(@publication.RunLocalResultEvidenceIssue)
  Evidence(@publication.ResultEvidenceIssuanceIssue)
  Artifact(@publication.ResultArtifactIssuanceIssue)
} derive(Eq, Debug)

///|
/// Local semantic Artifact and its exact witnesses. Store custody and the
/// current right to consume the captured Result remain separate obligations.
struct ClientEffectLocalResultArtifact {
  inputs : @strategy.CapturedEffectInputs
  borrow : @strategy.CapturedAnyResultBorrow
  definition : ClientEffectLocalResultDefinition
  invocation : ClientEffectLocalInvocation
  evidence : @publication.ResultOrderingEvidence
  artifact : @publication.PublicationContract
  retention : @publication.PublicationContract
  scope : @publication.PublicationContract?
  physical_cid : String
  physical_bytes : Int
}

///|
/// Issue only from the checked source-free Unit and its live Effect input pin.
/// Scope, policy, and capture authority come from the exact admitted Run,
/// not from caller-authored CID strings. Current mutation authority remains
/// a separate apply-time obligation.
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
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  run_invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
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
  // Matching an Invocation owner alone is not proof of an input-free Unit.
  // Acquired/imported Units must include their actual Relation provenance.
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  guard @checked.unit_pipeline(program, unit) is Some(pipeline) else {
    return Err(ForeignInvocation)
  }
  if unit != 0 ||
    !@pipeline.starts_with_values(pipeline) ||
    @pipeline.input_count(pipeline) != 0 ||
    @checked.unit_result_import_count(program, unit) != Some(0) ||
    @checked.unit_import_cid_count(program, unit) != Some(0) {
    return Err(ForeignInvocation)
  }
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
  if @strategy.captured_effect_inputs_run_definition_cid(inputs) !=
    Some(@publication.publication_contract_identity(run_definition)) ||
    @publication.check_run_publication_program_binding(
      admission,
      run_definition,
      prepared_client_effect_computation_definition_cid(owner),
      prepared_client_effect_computation_semantics_cid(owner),
      prepared_client_effect_computation_environment_cid(owner),
    )
    is Err(_) {
    return Err(ForeignRun)
  }
  let (scope_cid, effective_data_policy_cid, authority_scope_cid) = match
    @publication.resolve_run_local_result_evidence_refs(
      admission, run_definition, run_invocation, observation, retention,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Context(issue))
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
  build_client_effect_local_result_artifact(
    inputs,
    @strategy.captured_effect_input_borrow(input),
    definition,
    invocation,
    receipt,
    retention,
    scope_cid,
    effective_data_policy_cid,
    authority_scope_cid,
    [],
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn build_client_effect_local_result_artifact(
  inputs : @strategy.CapturedEffectInputs,
  borrow : @strategy.CapturedAnyResultBorrow,
  definition : ClientEffectLocalResultDefinition,
  invocation : ClientEffectLocalInvocation,
  receipt : @execution.CompletedRelationExportReceipt,
  retention : @publication.PublicationContract,
  scope_cid : String,
  effective_data_policy_cid : String,
  authority_scope_cid : String,
  input_relations : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  scope? : @publication.PublicationContract? = None,
) -> Result[
  ClientEffectLocalResultArtifact,
  ClientEffectLocalResultArtifactIssue,
] {
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
      input_relations,
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
  let (physical_cid, physical_bytes, _, _) = @execution.output_stream_identity(
    @execution.completed_relation_export_content(receipt),
  )
  Ok({
    inputs,
    borrow,
    definition,
    invocation,
    evidence,
    artifact,
    retention,
    scope,
    physical_cid,
    physical_bytes,
  })
}

///|
/// Physical custody facts from the exact export receipt admitted by issuance.
/// They are not added to the semantic Artifact preimage. No rehash/reexport
/// occurs, and a foreign Run cannot adopt the facts as its dependency payload.
pub fn client_effect_local_result_payload_binding(
  value : ClientEffectLocalResultArtifact,
  run_definition : @publication.PublicationContract,
) -> Result[(String, Int), ClientEffectLocalResultArtifactIssue] {
  if @publication.publication_contract_name(run_definition) != "run_definition" ||
    @strategy.captured_effect_inputs_run_definition_cid(value.inputs) !=
    Some(@publication.publication_contract_identity(run_definition)) {
    return Err(ForeignRun)
  }
  Ok((value.physical_cid, value.physical_bytes))
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

///|
/// Match the checked local Artifact inventory to one retained Run-bound
/// source before Store custody is acquired. Separate Effect members may use
/// the same physical view, but equal Result values alone do not share owner.
pub fn client_effect_local_source_matches(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  manifest : ClientEffectLocalManifest,
  invocation : ClientEffectLocalInvocation,
  artifact : ClientEffectLocalResultArtifact,
  source : @publication.CapturedEffectSourceArtifact,
) -> Bool {
  let mut owns_artifact = false
  for candidate in manifest.artifacts {
    if physical_equal(candidate, artifact) {
      owns_artifact = true
    }
  }
  if !physical_equal(artifact.inputs, inputs) ||
    !owns_artifact ||
    !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) ||
    !client_effect_local_artifact_matches_member(artifact, inputs, member_index) ||
    !client_effect_local_manifest_matches(
      manifest,
      owner,
      invocation,
      manifest.artifacts,
    ) {
    return false
  }
  guard @strategy.captured_effect_input_at(inputs, member_index) is Some(input) else {
    return false
  }
  let unit = @strategy.captured_effect_input_stage(input)
  let name = @execution.managed_result_occurrence_name(
    @strategy.captured_effect_input_occurrence(input),
  )
  client_effect_local_result_definition_matches(
    artifact.definition,
    owner,
    unit,
    name,
  ) &&
  client_effect_local_invocation_matches(invocation, owner, unit) &&
  @publication.captured_effect_source_matches_result_facts(
    source,
    artifact.artifact,
    name,
  )
}

///|
fn client_effect_local_artifact_matches_member(
  artifact : ClientEffectLocalResultArtifact,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
) -> Bool {
  guard physical_equal(artifact.inputs, inputs) &&
    @strategy.captured_effect_input_at(inputs, member_index) is Some(input) else {
    return false
  }
  @strategy.captured_any_result_borrows_share_view(
    artifact.borrow,
    @strategy.captured_effect_input_borrow(input),
  )
}

///|
/// Seal local semantic evidence only through the checked source owner. The
/// physical holding and current authority remain independent obligations.
pub fn admit_client_effect_local_source_evidence(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  manifest : ClientEffectLocalManifest,
  invocation : ClientEffectLocalInvocation,
  artifact : ClientEffectLocalResultArtifact,
  source : @publication.CapturedEffectSourceArtifact,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.CapturedLocalEffectSourceEvidence,
  @publication.CapturedLocalEffectSourceIssue,
] {
  if !client_effect_local_source_matches(
      owner, inputs, member_index, manifest, invocation, artifact, source,
    ) {
    return Err(@publication.InvalidLocalReference("owner"))
  }
  @publication.admit_captured_local_effect_source(
    source,
    artifact.definition.wire,
    invocation.wire,
    manifest.wire,
    artifact.artifact,
    @publication.result_ordering_derivation_contract(artifact.evidence),
    @publication.result_ordering_evidence_contract(artifact.evidence),
    artifact.retention,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}
