///|
// Before the initial Direct read of a checked keyed pipeline, lend the original
// Ledger only to its existing Core Local accounted Row receiver. This checks
// Source inventory, not successful keyed acquisition, authority or Model send.
pub fn borrow_client_original_keyed_direct_ledger(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  prepared : PreparedClientProgram,
  keyed : ClientKeyedAcquisition,
  requirement : @planning.QueryRequirement,
) -> Result[@resources.Ledger, ClientModelReadPreparationIssue] {
  if !client_model_origin_matches(scope.origin, compiled, definition, plan) ||
    !client_compiled_run_matches(compiled, prepared) ||
    !physical_equal(plan.owner, prepared) ||
    check_client_compiled_run_definition(compiled, definition) is Err(_) {
    return Err(ForeignRun)
  }
  guard client_compiled_run_serialization(compiled) is Some(component) &&
    plan.serialization is Some(selected) &&
    physical_equal(component, selected) &&
    physical_equal(component.owner, prepared) &&
    client_keyed_acquisition_matches_program(keyed, prepared) &&
    select_client_single_keyed_acquisition(prepared) is Ok(Some(original)) &&
    physical_equal(keyed.check, original.check) &&
    client_keyed_acquisition_coordinates(keyed) is Some((_, task, join)) &&
    task == component.task && join < component.step &&
    client_serialization_single_capture_shape(prepared, component.task) &&
    client_keyed_observation_covers_sources(prepared, keyed, requirement) &&
    client_keyed_direct_acquisition_coordinates(keyed)
    is Some((stage, input, _)) &&
    @strategy.graph_task_owner(prepared.graph, 0) is Some(owner) &&
    @strategy.graph_task_unit_index(prepared.graph, 0) == Some(stage) else {
    return Err(ForeignRun)
  }
  let program = @checked.source_identity(@strategy.graph_program(prepared.graph))
  let query = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  let acquisition = @query.query_sequence_requirement(query)
  guard physical_equal(@planning.query_requirement_program(requirement), program) &&
    physical_equal(@query.query_sequence_owner(query), owner) &&
    @context.program_identity_stage_requests(program, stage) is Some(requests) &&
    physical_equal(@acquisition.query_acquisition_owner(acquisition), requests) &&
    @acquisition.query_acquisition_source_index(acquisition) == input &&
    @acquisition.pipeline_request_at(requests, input)
    is Some(@acquisition.Direct(_, _)) else {
    return Err(ForeignRun)
  }
  if !@resources.original_ledger_prefix_available(scope.identity) {
    return Err(Resource(@resources.ChangedOriginalState))
  }
  Ok(scope.ledger)
}
