///|
// This borrow is consumed synchronously by the Core Local row constructor.
// The original Scope exists before capture registration/reservation and stays
// with its Host owner. No Node export, Source grant or Model grant is issued.
pub fn borrow_client_original_row_acquisition_ledger(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  prepared : PreparedClientProgram,
  requirement : @planning.QueryRequirement,
) -> Result[@resources.Ledger, ClientModelReadPreparationIssue] {
  if !client_model_origin_matches(scope.origin, compiled, definition, plan) ||
    !client_compiled_run_matches(compiled, prepared) ||
    !physical_equal(plan.owner, prepared) ||
    check_client_compiled_run_definition(compiled, definition) is Err(_) {
    return Err(ForeignRun)
  }
  let graph = prepared.graph
  guard client_compiled_run_serialization(compiled) is Some(component) &&
    plan.serialization is Some(selected) &&
    physical_equal(component, selected) &&
    physical_equal(component.owner, prepared) &&
    prepared_client_acquisition_count(prepared) == 1 &&
    client_serialization_single_capture_shape(prepared, component.task) &&
    @strategy.graph_task_owner(graph, 0) is Some(owner) &&
    @strategy.graph_task_unit_index(graph, 0) is Some(stage) else {
    return Err(ForeignRun)
  }
  let program = @checked.source_identity(@strategy.graph_program(graph))
  let sequence = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  let acquisition = @query.query_sequence_requirement(sequence)
  guard physical_equal(@planning.query_requirement_program(requirement), program) &&
    physical_equal(@query.query_sequence_owner(sequence), owner) &&
    @context.program_identity_stage_requests(program, stage) is Some(requests) &&
    physical_equal(@acquisition.query_acquisition_owner(acquisition), requests) &&
    @acquisition.query_acquisition_source_index(acquisition) == 0 &&
    @acquisition.pipeline_request_at(requests, 0)
    is Some(@acquisition.Direct(_, _)) else {
    return Err(ForeignRun)
  }
  // The first capture, like a source-free prefix, must precede descriptor/read
  // issue. A used attempt stays spent after cleanup; it cannot mint a new scope.
  if !@resources.original_ledger_prefix_available(scope.identity) {
    return Err(Resource(@resources.ChangedOriginalState))
  }
  Ok(scope.ledger)
}
