///|
// Only the Core Local prefix constructor receives this synchronous borrow.
// Scope custody stays in the original Host owner; no Node export or public
// wire projects the Ledger. The constructor immediately reserves its existing
// attempt before creating the managed provider, so reentry remains spent even
// after provider failure/cleanup. No new claim or resource owner is issued.
pub fn borrow_client_original_serialization_ledger(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  prepared : PreparedClientProgram,
  task : Int,
  step : Int,
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
    component.task == task &&
    component.step == step &&
    @strategy.graph_source_free_inputs_complete(prepared.graph) else {
    return Err(ForeignRun)
  }
  if !@resources.original_ledger_prefix_available(scope.identity) {
    return Err(Resource(@resources.ChangedOriginalState))
  }
  Ok(scope.ledger)
}
