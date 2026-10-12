///|
// Core Local is the only synchronous borrow receiver. Scope custody stays in
// Host; Local additionally proves the accounted capture's same-Ledger tokens
// before calling its existing acquired-prefix constructor. No Node getter.
pub fn borrow_client_original_captured_prefix_ledger(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  prepared : PreparedClientProgram,
  task : Int,
  step : Int,
  source : @query.CapturedInputSource,
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
    component.task == task && component.step == step &&
    prepared_client_acquisition_count(prepared) == 1 &&
    client_serialization_single_capture_shape(prepared, task) &&
    client_single_direct_observation_covers_sources(prepared) &&
    @strategy.graph_task_owner(prepared.graph, 0) is Some(owner) &&
    @query.captured_source_matches(
      source,
      @checked.source_identity(@strategy.graph_program(prepared.graph)),
      owner,
    ) else {
    return Err(ForeignRun)
  }
  if !@resources.original_ledger_preparation_available(scope.identity) {
    return Err(Resource(@resources.ChangedOriginalState))
  }
  Ok(scope.ledger)
}
