///|
// Authentication of the receiving Saved scope, not a new Source admission.
// The restored call scope must retain the SAME admitted artifact, effective
// inputs and named observations, in addition to its compiled Run and Plan.
fn saved_model_imported_scope_matches(
  compiled : ClientCompiledRun,
  scope : ClientInferCallScope,
  saved : ClientInferSavedCallScope,
) -> Bool {
  if !physical_equal(scope.owner, compiled.owner) ||
    !physical_equal(scope.plan, saved.plan) ||
    !physical_equal(scope.artifact, saved.artifact) ||
    !physical_equal(scope.effective, saved.effective) ||
    scope.named_sources.length() != saved.named_sources.length() {
    return false
  }
  for index in 0..<scope.named_sources.length() {
    let original = saved.named_sources[index]
    let retained = scope.named_sources[index]
    if retained.0 != original.0 || !physical_equal(retained.1, original.1) {
      return false
    }
  }
  client_infer_call_scope_matches(scope, compiled.owner, scope.input) &&
  client_infer_saved_call_scope_matches_originals(
    saved, compiled, saved.definition, scope.plan.occurrence, scope.plan,
  )
}

///|
/// A restored Model Unit whose external inputs are actual retained Results.
/// The imported owner supplies every checked producer, artifact and Scope;
/// historical Source observations alone cannot manufacture direct evidence.
/// This does not mix live Source admission into the restored input scheduler.
pub fn issue_restored_model_client_effect_imported_evidence(
  compiled : ClientCompiledRun,
  scope : ClientInferCallScope,
  saved : ClientInferSavedCallScope,
  model : @publication.CapturedEffectDependencyBody,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  imports : ClientEffectImportedEvidence,
) -> Result[ClientEffectModelAcquiredEvidence, ClientEffectAcquiredEvidenceIssue] {
  guard compiled.compilation is Effects(allowed) &&
    physical_equal(scope.plan.owner, compiled.owner) &&
    allowed.compilation.compiled.infers.any(original => {
      physical_equal(original, scope.plan)
    }) &&
    client_infer_occurrence_matches_effect(
      scope.plan.occurrence, allowed.compilation.owner,
    ) &&
    scope.plan.keyed is None &&
    saved_model_imported_scope_matches(compiled, scope, saved) else {
    return Err(Invocation(ForeignCapturedInput))
  }
  let owner = allowed.compilation.owner
  let occurrence = scope.plan.occurrence
  let unit = occurrence.stage
  let program = @checked.effect_program_static_checked_computation(owner.candidate)
  guard @checked.unit_definition_cid(program, unit) is Some(definition) &&
    @checked.unit_used_values_cid(program, unit) is Some(values) &&
    @checked.unit_contracts_cid(program, unit) is Some(contracts) &&
    @checked.unit_result_import_count(program, unit) is Some(count) &&
    count > 0 &&
    @checked.unit_import_cid_count(program, unit) == Some(count) &&
    physical_equal(imports.owner, owner) &&
    client_effect_local_invocation_matches(imports.invocation, owner, unit) &&
    imports.observations.length() == count &&
    scope.named_sources.length() == count &&
    @strategy.captured_effect_inputs_match_computation(imports.inputs, owner.graph) &&
    @strategy.captured_effect_inputs_run_definition_cid(imports.inputs) ==
    Some(@publication.publication_contract_identity(saved.definition)) &&
    @publication.local_model_observation_matches_input(
      model, definition, occurrence.step, scope.artifact,
    ) else {
    return Err(Invocation(ForeignCapturedInput))
  }
  let seen : Map[String, Bool] = Map([])
  let observations = [@publication.captured_effect_dependency_body_cid(model)]
  for observed in imports.observations {
    let producer = @strategy.captured_effect_result_import_producer(observed.captured)
    let interface = @strategy.captured_effect_result_import_interface(observed.captured)
    guard observed.artifact.source is ResultSource(borrow, result_definition) &&
      physical_equal(observed.owner, owner) &&
      physical_equal(observed.inputs, imports.inputs) &&
      client_effect_local_artifact_matches_inputs(observed.artifact, imports.inputs) &&
      @strategy.captured_effect_result_import_matches(
        observed.captured, imports.inputs, unit, producer,
      ) &&
      @strategy.captured_any_result_borrows_share_view(
        borrow, @strategy.captured_effect_local_result_borrow(producer),
      ) &&
      client_effect_local_result_definition_matches(
        result_definition,
        owner,
        @strategy.captured_effect_local_result_stage(producer),
        interface.result_name,
      ) &&
      client_effect_local_manifest_matches(
        observed.manifest, owner, observed.artifact.invocation,
        observed.manifest.artifacts,
      ) &&
      !seen.contains(interface.input_name) &&
      scope.named_sources.any(original => original.0 == interface.input_name) else {
      return Err(Invocation(ForeignResultImport))
    }
    // The actual captured producer/interface/borrow determines this position.
    // A name, count, equal logical row set or CID never substitutes for it.
    seen[interface.input_name] = true
    observations.push(observed.cid)
  }
  observations.sort_by(@canonical_value.compare_utf16)
  let invocation = match
    issue_client_effect_local_invocation_body(
      owner, unit, definition, values, contracts,
      @checked.checked_local_policy_cid(program), observations,
      max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  let combined = match
    @publication.issue_combined_acquisition_scope(
      [imports.scope], max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Relation(issue))
  }
  if !saved_model_imported_scope_matches(compiled, scope, saved) ||
    !@strategy.captured_effect_inputs_match_computation(imports.inputs, owner.graph) {
    return Err(Invocation(ForeignCapturedInput))
  }
  Ok({
    compiled,
    call_scope: scope,
    model,
    invocation,
    direct: [],
    keyed: None,
    scope: combined,
    retention,
    imports: Some(imports),
  })
}
