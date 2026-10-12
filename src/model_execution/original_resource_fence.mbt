///|
// Read the same existing Ledger fence before mutating this Model owner. Ok is
// only absence of that restriction, never current authority or send permission.
fn check_model_original_resources_mutable(
  state : ModelState,
) -> Result[Unit, ModelExecutionIssue] {
  @resources.check_original_resources_mutable(state.ledger).map_err(issue => Ledger(issue))
}

///|
/// The consuming Host checks this before changing its enclosing execution.
/// It neither parks resources nor proves a stable Model/Entry/Store cut.
pub fn model_execution_mutation_current(
  execution : ModelExecution,
) -> Result[Unit, ModelExecutionIssue] {
  check_model_original_resources_mutable(execution.state)
}

///|
/// Initial quiescent candidate only, not a Resource park, Store ACK or grant.
/// Return the same original Model, not a copied snapshot or a new control.
pub fn model_original_park_candidate(
  execution : ModelExecution,
  rows : @relation.PreparedInferRows,
  scope : @publication_host.ClientInferCallScope,
) -> ModelExecution? {
  let state = execution.state
  guard !execution.advancing && !state.reclaimed && !state.accepted &&
    !state.stop_requested && !@bounded.session_stopped(execution.session) &&
    state.phase is DispatchSlot && state.entering is None &&
    state.pending_response is None && state.settlement_pending is None &&
    state.request is None && state.output_uses == 0 &&
    state.source is Provider(_) &&
    physical_equal(state.rows, rows) &&
    state.call_scope is Some(current_scope) && physical_equal(current_scope, scope) &&
    state.original_startup is Some(startup) && startup.used &&
    physical_equal(startup.rows, rows) && physical_equal(startup.ledger, state.ledger) &&
    startup.scope is Some(original_scope) && physical_equal(original_scope, scope) &&
    @resources.capacity_reservation_open(startup.capacity) &&
    state.prepared_call_set is Some(prepared) &&
    physical_equal(prepared.owner, execution) && prepared_model_current(prepared) &&
    state.requests.length() == @relation.prepared_infer_rows_count(rows) else {
    return None
  }
  Some(execution)
}

///|
/// The same actual Resource token and the same quiescent original Model are
/// both required. Ledger equality alone does not establish this observation.
pub fn[T] model_original_resource_park_current(
  execution : ModelExecution,
  rows : @relation.PreparedInferRows,
  scope : @publication_host.ClientInferCallScope,
  park : @resources.OriginalResourcePark[T],
) -> ModelExecution? {
  guard model_original_park_candidate(execution, rows, scope) is Some(original) &&
    @resources.original_resource_park_current_for_ledger(park, execution.state.ledger)
    is Some(_) else {
    return None
  }
  Some(original)
}
