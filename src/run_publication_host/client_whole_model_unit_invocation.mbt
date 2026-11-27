///|
/// A completed Model Unit contributes its own semantic observation and the
/// imports read at that Unit. Its original Model and Result remain borrowed.
priv struct ClientWholeModelUnitOriginal {
  call : ClientInferCallScope
  model : @publication.CapturedEffectDependencyBody
  imports : Array[ClientScopeResultImportObservation]
  current : () -> Bool
}

///|
fn client_whole_model_unit_sources_match(
  original : ClientWholeLocalUnitOriginal,
  call : ClientInferCallScope,
) -> Bool {
  let inputs = original.sources.inputs
  if call.sources.length() != inputs.length() ||
    call.named_sources.length() != inputs.length() {
    return false
  }
  for index, input in inputs {
    if !physical_equal(call.sources[index], input.observation) ||
      call.named_sources[index].0 != input.name ||
      !physical_equal(call.named_sources[index].1, input.observation) ||
      !@publication.model_source_observation_matches_authority(
        input.observation,
        client_request_authority_scope_cid(original.request),
      ) {
      return false
    }
  }
  true
}

///|
/// The completed Model owner supplies the checked A Scope and its observed
/// outcomes. The same Run lends the completed Unit and original Whole
/// captures. Both owners are fenced after each writer funding callback.
pub fn issue_client_whole_model_unit_invocation(
  scope : ClientModelReadScope,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
  run : @strategy.CapturedDAG,
  results : @strategy.CapturedCompletedUnitResults,
  sources : ClientInferComposedSources,
  call : ClientInferCallScope,
  model : @publication.CapturedEffectDependencyBody,
  outcome : @execution.CompletedRelationExportReceipt,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  original_current : () -> Bool,
  fund_controls : (Int) -> Bool,
  fund_body : (String, @encode.EncodingConstructionGeometry) -> Bool,
) -> Result[ClientWholeLocalUnitInvocation, ClientEffectLocalInvocationIssue] {
  let compiled = scope.origin.compiled
  let plan = scope.origin.plan
  let unit = plan.occurrence.stage
  let program = @strategy.graph_program(compiled.owner.graph)
  let identity = prepared_client_identity(compiled.owner)
  guard compiled.compilation is Tasks(_) &&
    physical_equal(call.owner, compiled.owner) &&
    physical_equal(call.plan, plan) &&
    physical_equal(sources.occurrence, plan.occurrence) &&
    identity.program_definition_cid == request.program_definition_cid &&
    identity.parameter_values_cid == request.parameter_values_cid &&
    @checked.unit_definition_cid(program, unit) is Some(unit_definition) &&
    @checked.unit_used_values_cid(program, unit) is Some(used_values) &&
    @checked.unit_contracts_cid(program, unit) is Some(contracts) &&
    @checked.unit_result_import_count(program, unit) is Some(import_count) else {
    return Err(ForeignCapturedInput)
  }
  let count = 1L + sources.inputs.length().to_int64() + import_count.to_int64()
  guard count <= max_nodes.to_int64() &&
    call.unit_definition_cid == unit_definition &&
    call.source_ordinal == plan.occurrence.step &&
    client_whole_model_observation_matches(call, model, outcome) else {
    return Err(ForeignSourceObservation)
  }
  let whole : ClientWholeLocalUnitOriginal = {
    scope,
    definition,
    run,
    unit,
    results,
    sources,
    request,
    model: None,
  }
  let current = () => {
    client_whole_local_unit_original_live(whole) &&
    client_whole_model_unit_sources_match(whole, call) &&
    client_infer_call_scope_matches(call, compiled.owner, call.input) &&
    client_infer_composed_whole_sources_match_run(
      sources,
      run,
      after_completion=true,
    ) &&
    original_current() &&
    client_whole_model_outcome_matches(call, outcome) &&
    call.whole_terminal is Recorded(_) &&
    client_whole_local_unit_original_live(whole) &&
    client_infer_result_input_inventory_current(call) &&
    client_whole_model_unit_sources_match(whole, call)
  }
  if !current() {
    return Err(ForeignCapturedInput)
  }
  if !fund_controls(count.to_int()) || !current() {
    return Err(Encoding)
  }
  let backed = (name, geometry) => fund_body(name, geometry) && current()
  let imports = match
    issue_original_scope_result_import_observations(
      program,
      call,
      WholeScope(run, request, definition),
      max_bytes,
      max_nodes,
      max_depth,
      before_body=Some(backed),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let original : ClientWholeModelUnitOriginal = {
    call,
    model,
    imports,
    current,
  }
  let observations = [
    @publication.captured_effect_dependency_body_cid(original.model),
  ]
  for imported in original.imports {
    observations.push(imported.cid)
  }
  for input in sources.inputs {
    guard input.original is Whole(acquisition) else {
      return Err(ForeignSourceObservation)
    }
    let declaration = @acquisition.declaration(
      @acquisition.mode_input(@acquisition.source_acquisition_mode(acquisition)),
    )
    // An earlier Unit's File provenance is carried by the exact imported
    // Result. Only this Unit's declared Source is an immediate observation.
    if declaration.stage_index == original.call.plan.occurrence.stage {
      observations.push(
        @publication.model_source_observation_fields(input.observation).0,
      )
    }
  }
  observations.sort_by(@canonical_value.compare_utf16)
  issue_client_local_unit_invocation(
    { ..whole, model: Some(original), },
    unit,
    unit_definition,
    used_values,
    contracts,
    @checked.checked_local_policy_cid(program),
    observations,
    max_bytes,
    max_nodes,
    max_depth,
    before_body=Some((name, geometry) => {
      fund_body(name, geometry) && (original.current)()
    }),
  )
}
