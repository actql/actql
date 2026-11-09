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
) -> Result[ClientEffectLocalInvocation, ClientEffectLocalInvocationIssue] {
  guard compiled.compilation is Effects(allowed) &&
    physical_equal(compiled.owner, scope.owner) &&
    allowed.compilation.compiled.infers.length() <= 1 &&
    client_effect_compilation_infer_original(allowed.compilation)
    is Some((plan, occurrence)) &&
    physical_equal(scope.plan, plan) &&
    client_infer_call_scope_matches(scope, compiled.owner, scope.input) else {
    return Err(ForeignCapturedInput)
  }
  let owner = allowed.compilation.owner
  let unit = occurrence.stage
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  guard @checked.unit_definition_cid(program, unit) is Some(definition) &&
    @checked.unit_used_values_cid(program, unit) is Some(values) &&
    @checked.unit_contracts_cid(program, unit) is Some(contracts) &&
    @checked.unit_result_import_count(program, unit) == Some(0) &&
    @checked.unit_import_cid_count(program, unit) == Some(0) &&
    @publication.local_model_observation_matches_input(
      model,
      definition,
      occurrence.step,
      scope.artifact,
    ) else {
    return Err(ForeignSourceObservation)
  }
  let observations = [@publication.captured_effect_dependency_body_cid(model)]
  for source in client_infer_call_scope_source_observations(scope) {
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
