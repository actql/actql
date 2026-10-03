///|
pub(all) enum ClientEffectImportedEvidenceIssue {
  Invocation(ClientEffectLocalInvocationIssue)
  MissingScope
  IncompatibleScope
  Relation(@publication.AcquisitionRelationIssue)
} derive(Eq, Debug)

///|
/// Dependency edges originate in actual retained import observations. This
/// owner carries their bodies until Store custody is established.
struct ClientEffectImportedEvidence {
  owner : PreparedClientEffectComputation
  inputs : @strategy.CapturedEffectInputs
  invocation : ClientEffectLocalInvocation
  observations : Array[ClientEffectResultImportObservation]
  relations : Array[@publication.PublicationContract]
  scope : @publication.PublicationContract
}

///|
pub fn issue_client_effect_imported_evidence(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  unit : Int,
  observations : Array[ClientEffectResultImportObservation],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectImportedEvidence, ClientEffectImportedEvidenceIssue] {
  let invocation = match
    issue_imported_client_effect_local_invocation(
      owner, inputs, unit, observations, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  // Retain each producer's exact scope on its Relation. The downstream
  // scope is the canonical request inventory of those captured imports,
  // not a union of access permissions or a caller-supplied source list.
  let scopes : Array[@publication.PublicationContract] = []
  let relations : Array[@publication.PublicationContract] = []
  for observation in observations {
    let artifact = observation.artifact
    guard artifact.scope is Some(input_scope) else { return Err(MissingScope) }
    scopes.push(input_scope)
    let relation = match
      @publication.issue_derived_input_relation(
        artifact.artifact,
        artifact.evidence,
        input_scope,
        artifact.retention,
        max_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Relation(issue))
    }
    // Repeated imports retain their separate observation positions. The
    // Derivation's Relation dependency set itself has no duplicate CIDs.
    if !relations.any(value => {
        @publication.publication_contract_identity(value) ==
        @publication.publication_contract_identity(relation)
      }) {
      relations.push(relation)
    }
  }
  let scope = match
    @publication.issue_combined_acquisition_scope(
      scopes, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Relation(issue))
  }
  relations.sort_by(fn(a, b) {
    @canonical_value.compare_utf16(
      @publication.publication_contract_identity(a),
      @publication.publication_contract_identity(b),
    )
  })
  Ok({
    owner,
    inputs,
    invocation,
    observations: observations.copy(),
    relations,
    scope,
  })
}

///|
pub fn client_effect_imported_invocation(
  value : ClientEffectImportedEvidence,
) -> ClientEffectLocalInvocation {
  value.invocation
}

///|
/// The derived Result references this exact combined scope. Retain its body
/// alongside the input Relations so recovery can close the evidence graph.
pub fn client_effect_imported_scope_json(
  value : ClientEffectImportedEvidence,
) -> String {
  @publication.publication_contract_json(value.scope)
}

///|
pub fn client_effect_imported_relation_bodies(
  value : ClientEffectImportedEvidence,
) -> Array[String] {
  value.relations.map(@publication.publication_contract_json)
}

///|
pub fn issue_imported_client_effect_local_result_artifact(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  imported : ClientEffectImportedEvidence,
  definition : ClientEffectLocalResultDefinition,
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
  if !physical_equal(imported.owner, owner) ||
    !physical_equal(imported.inputs, inputs) ||
    !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) {
    return Err(ForeignOwner)
  }
  // Recheck custody, without reissuing or hashing the Invocation.
  for observed in imported.observations {
    if !@strategy.captured_effect_result_import_matches(
        observed.captured,
        inputs,
        imported.invocation.unit,
        @strategy.captured_effect_result_import_producer(observed.captured),
      ) {
      return Err(ForeignOwner)
    }
  }
  if !@strategy.captured_effect_local_result_export_matches_receipt(
      inputs, exported, receipt,
    ) {
    return Err(ForeignExport)
  }
  let result = @strategy.captured_effect_local_result_export_result(exported)
  let borrow = @strategy.captured_effect_local_result_borrow(result)
  if @strategy.captured_effect_local_result_stage(result) !=
    imported.invocation.unit ||
    !client_effect_local_result_definition_matches(
      definition,
      owner,
      imported.invocation.unit,
      @execution.managed_result_occurrence_name(
        @strategy.captured_any_result_borrow_occurrence(borrow),
      ),
    ) {
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
  let (_, policy, authority) = match
    @publication.resolve_run_local_result_evidence_refs(
      admission, run_definition, run_invocation, observation, retention,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Context(issue))
  }
  build_client_effect_local_result_artifact(
    inputs,
    borrow,
    definition,
    imported.invocation,
    receipt,
    retention,
    @publication.publication_contract_identity(imported.scope),
    policy,
    authority,
    imported.relations.map(@publication.publication_contract_identity),
    max_bytes,
    max_nodes,
    max_depth,
    scope=Some(imported.scope),
  )
}
