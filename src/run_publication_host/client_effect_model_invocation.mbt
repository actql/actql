///|
/// Project one completed Model Unit's semantic identity. The retained compiler
/// and input Scope choose the Unit and its complete Source observation closure;
/// neither a Query requirement nor an input-free Unit is synthesized. The
/// admitted Model body is semantic DATA, not physical completion or permission.
/// The original Model owner supplies that body through its live output/issuer
/// wrapper. Result export, Store custody and Preview remain separate checks.
pub fn issue_single_model_client_effect_local_invocation(
  compiled : ClientCompiledRun,
  scope : ClientInferCallScope,
  model : @publication.CapturedEffectDependencyBody,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectLocalInvocation, ClientEffectLocalInvocationIssue] {
  issue_model_effect_local_invocation(
    compiled,
    scope,
    model,
    None,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn issue_model_effect_local_invocation(
  compiled : ClientCompiledRun,
  scope : ClientInferCallScope,
  model : @publication.CapturedEffectDependencyBody,
  lookup : ClientKeyedNativeCompletion?,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  imports? : (ClientEffectImportedEvidence, ClientInferComposedSources)? = None,
) -> Result[ClientEffectLocalInvocation, ClientEffectLocalInvocationIssue] {
  guard compiled.compilation is Effects(allowed) &&
    physical_equal(compiled.owner, scope.owner) &&
    physical_equal(scope.plan.owner, compiled.owner) &&
    allowed.compilation.compiled.infers.any(original => {
      physical_equal(original, scope.plan)
    }) &&
    client_infer_occurrence_matches_effect(
      scope.plan.occurrence,
      allowed.compilation.owner,
    ) &&
    client_infer_occurrence_matches_plan(scope.plan.occurrence, scope.plan) &&
    client_infer_call_scope_matches(scope, compiled.owner, scope.input) else {
    return Err(ForeignCapturedInput)
  }
  let occurrence = scope.plan.occurrence
  let owner = allowed.compilation.owner
  let unit = occurrence.stage
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  guard @checked.unit_definition_cid(program, unit) is Some(definition) &&
    @checked.unit_used_values_cid(program, unit) is Some(values) &&
    @checked.unit_contracts_cid(program, unit) is Some(contracts) else {
    return Err(MissingUnit)
  }
  if !model_effect_imports_match(owner, scope, occurrence, imports) {
    return Err(
      if imports is None {
        IncompleteResultImports
      } else {
        ForeignResultImport
      },
    )
  }
  if !@publication.local_model_observation_matches_input(
      model,
      definition,
      occurrence.step,
      scope.artifact,
    ) {
    return Err(ForeignSourceObservation)
  }
  let observations = [@publication.captured_effect_dependency_body_cid(model)]
  if imports is Some((original, _)) {
    for observed in original.observations {
      observations.push(observed.cid)
    }
  }
  for source in client_infer_call_scope_source_observations(scope) {
    if imports is Some((original, sources)) &&
      sources.inputs.any(input => {
        physical_equal(input.observation, source) &&
        model_effect_imported_source(original, input)
      }) {
      continue
    }
    if imports is Some((original, sources)) &&
      client_infer_occurrence_coordinates(sources.occurrence) !=
      client_infer_occurrence_coordinates(occurrence) &&
      sources.keyed.map(entry => physical_equal(entry.2, source)) == Some(true) &&
      model_effect_imported_keyed(original, sources) {
      continue
    }
    let (evidence, _, _, _) = @publication.model_source_observation_originals(
      source,
    )
    // The complete Lookup observation replaces its narrower Source-only root.
    // Its actual captured Source body remains a transitive provenance member.
    if lookup is Some(completed) && physical_equal(completed.source, evidence) {
      continue
    }
    let cid = @publication.run_evidence_value_identity(evidence)
    if !observations.contains(cid) {
      observations.push(cid)
    }
  }
  if lookup is Some(completed) {
    observations.push(
      @publication.publication_contract_identity(completed.evidence),
    )
  }
  observations.sort_by(@canonical_value.compare_utf16)
  issue_client_effect_local_invocation_body(
    owner,
    unit,
    definition,
    values,
    contracts,
    @checked.checked_local_policy_cid(program),
    observations,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
// A count never admits an import. Every original input is bound to the SAME
// captured Run and actual producer through its existing typed import proof.
fn model_effect_imports_match(
  owner : PreparedClientEffectComputation,
  scope : ClientInferCallScope,
  occurrence : ClientInferOccurrence,
  imports : (ClientEffectImportedEvidence, ClientInferComposedSources)?,
) -> Bool {
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  guard @checked.unit_result_import_count(program, occurrence.stage)
    is Some(count) &&
    @checked.unit_import_cid_count(program, occurrence.stage) == Some(count) else {
    return false
  }
  if count == 0 {
    return imports is None
  }
  guard imports is Some((original, sources)) &&
    physical_equal(original.owner, owner) &&
    original.invocation.unit == occurrence.stage &&
    original.observations.length() == count &&
    physical_equal(sources.occurrence.owner, scope.owner) &&
    client_infer_composed_source_origin_matches(sources.occurrence, occurrence) &&
    @strategy.captured_effect_inputs_match_computation(
      original.inputs,
      owner.graph,
    ) else {
    return false
  }
  for observed in original.observations {
    let producer = @strategy.captured_effect_result_import_producer(
      observed.captured,
    )
    guard @strategy.captured_effect_result_import_matches(
      observed.captured,
      original.inputs,
      occurrence.stage,
      producer,
    ) else {
      return false
    }
  }
  for input in sources.inputs {
    if !scope.named_sources.any(entry => {
        entry.0 == input.name && physical_equal(entry.1, input.observation)
      }) ||
      !(model_effect_imported_source(original, input) ||
      model_effect_inline_source(program, occurrence.stage, input.original)) {
      return false
    }
  }
  @strategy.captured_effect_inputs_match_computation(
    original.inputs,
    owner.graph,
  )
}
