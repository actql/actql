///|
/// Resolve public Result provenance from the exact retained import owner and
/// original admitted Run. These references grant neither publication nor a
/// current Effect mutation permission. Callers must also retain physical input
/// custody and recheck current Site authority around output traversal.
pub fn client_effect_imported_result_evidence_refs(
  materials : ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  imported : ClientEffectImportedEvidence,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  retention : @publication.PublicationContract,
) -> Result[
  (String, Array[String], String, String, String),
  ClientEffectLocalResultArtifactIssue,
] {
  let owner = materials.prepared
  if !physical_equal(imported.owner, owner) ||
    !physical_equal(imported.inputs, inputs) ||
    !physical_equal(materials.compilation, materials.allowed.compilation) ||
    !physical_equal(materials.compilation.owner, owner) ||
    !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) {
    return Err(ForeignOwner)
  }
  let graph = @strategy.checked_effect_computation_graph(owner.graph)
  guard @strategy.graph_result_count(graph) == 1 &&
    @strategy.graph_result_task(graph, 0) is Some(task) &&
    @strategy.graph_task_unit_index(graph, task) ==
    Some(imported.invocation.unit) else {
    return Err(ForeignDefinition)
  }
  let admission = materials.allowed.admission
  if @strategy.captured_effect_inputs_run_definition_cid(inputs) !=
    Some(@publication.publication_contract_identity(materials.run_definition)) ||
    @publication.check_run_publication_program_binding(
      admission,
      materials.run_definition,
      prepared_client_effect_computation_definition_cid(owner),
      prepared_client_effect_computation_semantics_cid(owner),
      prepared_client_effect_computation_environment_cid(owner),
    )
    is Err(_) {
    return Err(ForeignRun)
  }
  let (_, policy, authority) = match
    @publication.resolve_run_local_result_evidence_refs(
      admission,
      materials.run_definition,
      invocation,
      observation,
      retention,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Context(issue))
  }
  for observed in imported.observations {
    if !@strategy.captured_effect_result_import_matches(
        observed.captured,
        inputs,
        imported.invocation.unit,
        @strategy.captured_effect_result_import_producer(observed.captured),
      ) {
      return Err(ForeignOwner)
    }
    if client_effect_local_artifact_run_definition_cid(observed.artifact) !=
      Some(@publication.publication_contract_identity(materials.run_definition)) {
      return Err(ForeignRun)
    }
    // A valid Invocation of the same Template can still refresh the captured
    // observation. Public evidence must use the producer's original Invocation.
    if client_effect_local_artifact_run_invocation_cid(observed.artifact) !=
      Some(@publication.publication_contract_identity(invocation)) {
      return Err(ForeignInvocation)
    }
  }
  Ok(
    (
      @publication.publication_contract_identity(
        client_effect_compilation_compiled_plan(materials.compilation),
      ),
      imported.relations.map(@publication.publication_contract_identity),
      @publication.publication_contract_identity(imported.scope),
      policy,
      authority,
    ),
  )
}
