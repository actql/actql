///|
// The exact completed Unit and supplied Source originals belong to the same
// physical Run as the Model Read scope. This remains a semantic issuer, not
// authority to dispatch or to publish a public Program Result.
struct ClientWholeLocalUnitOriginal {
  scope : ClientModelReadScope
  definition : @publication.PublicationContract
  run : @strategy.CapturedDAG
  unit : Int
  results : @strategy.CapturedCompletedUnitResults
  sources : ClientInferComposedSources
  request : ClientRequestIdentity
}

///|
pub type ClientWholeLocalUnitInvocation = ClientLocalUnitInvocation[
  ClientWholeLocalUnitOriginal,
]

///|
fn client_whole_local_unit_owners_match(
  scope : ClientModelReadScope,
  definition : @publication.PublicationContract,
  run : @strategy.CapturedDAG,
  unit : Int,
  results : @strategy.CapturedCompletedUnitResults,
  sources : ClientInferComposedSources,
) -> Bool {
  let compiled = scope.origin.compiled
  let plan = scope.origin.plan
  compiled.definition_binding is Some(facts) &&
  client_compiled_run_definition_facts_match(facts, compiled, definition) &&
  physical_equal(scope.ledger, @strategy.captured_dag_ledger(run)) &&
  client_model_read_scope_live(scope, compiled, definition, plan) &&
  @strategy.captured_completed_unit_results_match(results, run, unit) &&
  client_infer_composed_whole_sources_original(sources, plan.occurrence)
}

///|
fn client_whole_local_unit_original_live(
  original : ClientWholeLocalUnitOriginal,
) -> Bool {
  client_whole_local_unit_owners_match(
    original.scope,
    original.definition,
    original.run,
    original.unit,
    original.results,
    original.sources,
  )
}

///|
/// Take one complete producer Unit from its existing installed Run and funded
/// Model Read scope. The two funding callbacks precede the control inventory
/// and the actual semantic invocation wire respectively.
pub fn prepare_client_whole_local_unit_invocation(
  scope : ClientModelReadScope,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
  run : @strategy.CapturedDAG,
  results : @strategy.CapturedCompletedUnitResults,
  sources : ClientInferComposedSources,
  unit : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  fund_original : (Int) -> Bool,
  fund_body : (String, @encode.EncodingConstructionGeometry) -> Bool,
) -> Result[ClientWholeLocalUnitInvocation, ClientEffectLocalInvocationIssue] {
  let compiled = scope.origin.compiled
  let graph = compiled.owner.graph
  let program = @strategy.graph_program(graph)
  let count = sources.inputs.length()
  guard count > 0 &&
    count <= max_nodes &&
    unit < scope.origin.plan.occurrence.stage &&
    @checked.unit_definition_cid(program, unit) is Some(unit_definition) &&
    @checked.unit_used_values_cid(program, unit) is Some(used_values) &&
    @checked.unit_contracts_cid(program, unit) is Some(contracts) &&
    @checked.unit_pipeline(program, unit) is Some(pipeline) &&
    client_effect_source_unit_without_model(pipeline) &&
    @checked.unit_result_import_count(program, unit) == Some(0) &&
    @checked.unit_import_cid_count(program, unit) == Some(0) else {
    return Err(MissingUnit)
  }
  if !client_whole_local_unit_owners_match(
      scope, definition, run, unit, results, sources,
    ) {
    return Err(ForeignCapturedInput)
  }
  if !fund_original(count) {
    return Err(Encoding)
  }
  let original : ClientWholeLocalUnitOriginal = {
    scope,
    definition,
    run,
    unit,
    results,
    sources,
    request,
  }
  if !client_whole_local_unit_original_live(original) ||
    !client_infer_composed_whole_sources_match_run(
      sources,
      run,
      after_completion=true,
    ) {
    return Err(ForeignCapturedInput)
  }
  let observations : Array[String] = Array(capacity=count)
  for input in sources.inputs {
    guard input.original is Whole(acquisition) &&
      @acquisition.declaration(
        @acquisition.mode_input(
          @acquisition.source_acquisition_mode(acquisition),
        ),
      ).stage_index ==
      unit &&
      @publication.model_source_observation_matches_authority(
        input.observation,
        client_request_authority_scope_cid(request),
      ) else {
      return Err(ForeignSourceObservation)
    }
    observations.push(
      @publication.model_source_observation_fields(input.observation).0,
    )
  }
  // The wire funding callback may run Host code. Recheck both the exact
  // nominal owner and the physical reads before the writer takes the body.
  issue_client_local_unit_invocation(
    original,
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
      fund_body(name, geometry) &&
      client_whole_local_unit_original_live(original) &&
      client_infer_composed_whole_sources_match_run(
        sources,
        run,
        after_completion=true,
      )
    }),
  )
}

///|
/// Compare the exact local Invocation's owners without running a Source
/// callback. The caller retains its existing current-authority fence.
pub fn client_whole_local_unit_invocation_matches(
  value : ClientWholeLocalUnitInvocation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
  run : @strategy.CapturedDAG,
) -> Bool {
  let original = value.owner
  physical_equal(original.scope.origin.compiled, compiled) &&
  physical_equal(original.definition, definition) &&
  physical_equal(original.request, request) &&
  physical_equal(original.run, run) &&
  client_whole_local_unit_original_live(original)
}
