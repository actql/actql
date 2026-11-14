///|
/// Issue a private Table projection through the same Relation Artifact owner.
/// Its Definition and Manifest entry have a private namespace; neither can
/// satisfy an ordinary Result source. Wire recovery admission remains separate.
/// This issuer establishes content binding, never approval or write authority.
pub fn issue_source_free_client_effect_local_table_artifact(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  importing_input : @strategy.CapturedEffectTableInput,
  importing_output : @execution.ManagedCompletedOutput[Int],
  importing_bridge : @execution.ManagedPublicationBridge[Int],
  preparation : @execution.CompletedTableInputRelationExportPreparation,
  definition : ClientEffectLocalTableDefinition,
  invocation : ClientEffectLocalInvocation,
  receipt : @execution.CompletedRelationExportReceipt,
  retention : @publication.PublicationContract,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  run_invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientEffectLocalResultArtifact,
  ClientEffectLocalResultArtifactIssue,
] {
  if !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) {
    return Err(ForeignOwner)
  }
  guard @strategy.captured_effect_table_input_at(inputs, member_index)
    is Some(input) else {
    return Err(MissingInput)
  }
  let unit = @strategy.captured_effect_table_input_stage(input)
  // The existing source-free Invocation issuer proves zero imports and no
  // external Source. Acquired Units must use their actual capture provenance.
  if issue_source_free_client_effect_local_invocation(
      owner, unit, max_bytes, max_nodes, max_depth,
    )
    is Err(_) ||
    !client_effect_local_invocation_matches(invocation, owner, unit) {
    return Err(ForeignInvocation)
  }
  issue_client_effect_local_table_artifact(
    owner,
    inputs,
    member_index,
    importing_input,
    importing_output,
    importing_bridge,
    preparation,
    definition,
    invocation,
    receipt,
    retention,
    admission,
    run_definition,
    run_invocation,
    observation,
    [],
    None,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// A private Table export uses its own occurrence and retained export proof;
/// an equal public Result cannot replace it. Import provenance comes from the
/// existing checked imported Invocation, not a caller-authored dependency list.
pub fn issue_imported_client_effect_local_table_artifact(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  importing_input : @strategy.CapturedEffectTableInput,
  importing_output : @execution.ManagedCompletedOutput[Int],
  importing_bridge : @execution.ManagedPublicationBridge[Int],
  preparation : @execution.CompletedTableInputRelationExportPreparation,
  definition : ClientEffectLocalTableDefinition,
  imported : ClientEffectImportedEvidence,
  receipt : @execution.CompletedRelationExportReceipt,
  retention : @publication.PublicationContract,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  run_invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientEffectLocalResultArtifact,
  ClientEffectLocalResultArtifactIssue,
] {
  if !client_effect_imported_evidence_matches_owner(imported, owner, inputs) {
    return Err(ForeignOwner)
  }
  issue_client_effect_local_table_artifact(
    owner,
    inputs,
    member_index,
    importing_input,
    importing_output,
    importing_bridge,
    preparation,
    definition,
    imported.invocation,
    receipt,
    retention,
    admission,
    run_definition,
    run_invocation,
    observation,
    imported.relations.map(@publication.publication_contract_identity),
    Some(imported.scope),
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn issue_client_effect_local_table_artifact(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  importing_input : @strategy.CapturedEffectTableInput,
  importing_output : @execution.ManagedCompletedOutput[Int],
  importing_bridge : @execution.ManagedPublicationBridge[Int],
  preparation : @execution.CompletedTableInputRelationExportPreparation,
  definition : ClientEffectLocalTableDefinition,
  invocation : ClientEffectLocalInvocation,
  receipt : @execution.CompletedRelationExportReceipt,
  retention : @publication.PublicationContract,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  run_invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  input_relations : Array[String],
  imported_scope : @publication.PublicationContract?,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientEffectLocalResultArtifact,
  ClientEffectLocalResultArtifactIssue,
] {
  if !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) {
    return Err(ForeignOwner)
  }
  guard @strategy.captured_effect_table_input_at(inputs, member_index)
    is Some(input) else {
    return Err(MissingInput)
  }
  let unit = @strategy.captured_effect_table_input_stage(input)
  if !client_effect_local_invocation_matches(invocation, owner, unit) {
    return Err(ForeignInvocation)
  }
  if !client_effect_local_table_definition_matches(definition, owner, input) {
    return Err(ForeignDefinition)
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
  let (scope, policy, authority) = match
    @publication.resolve_run_local_result_evidence_refs(
      admission, run_definition, run_invocation, observation, retention,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Context(issue))
  }
  if !physical_equal(importing_input, input) ||
    !@strategy.captured_table_input_borrow_matches_managed(
      @strategy.captured_effect_table_input_borrow(input),
      importing_output,
    ) ||
    !@execution.managed_publication_bridge_matches_table_input_export(
      importing_bridge,
      importing_output,
      preparation,
      @strategy.captured_effect_table_input_occurrence(input),
    ) ||
    !@execution.completed_table_input_export_preparation_matches_receipt(
      preparation, receipt,
    ) {
    return Err(ForeignExport)
  }
  build_client_effect_local_result_artifact(
    EffectInputs(inputs),
    TableSource(@strategy.captured_effect_table_input_borrow(input), definition),
    invocation,
    receipt,
    Some(run_invocation),
    retention,
    imported_scope
    .map(@publication.publication_contract_identity)
    .unwrap_or(scope),
    policy,
    authority,
    input_relations,
    max_bytes,
    max_nodes,
    max_depth,
    scope=imported_scope,
  )
}

///|
/// Classify an issued artifact by its original occurrence namespace. Equal
/// Relation content never changes a private Table root into a public Result.
pub fn client_effect_local_artifact_dependency_root(
  artifact : ClientEffectLocalResultArtifact,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  @publication.CapturedEffectDependencyIssue,
] {
  let kind = match artifact.source {
    ResultSource(_, _) => "result_artifact"
    TableSource(_, _) => "table_input_artifact"
  }
  @publication.admit_publication_effect_dependency_body(
    kind,
    client_effect_local_result_artifact_json(artifact),
    max_bytes,
    max_nodes,
    max_depth,
  )
}
