///|
/// Pure original-parent membership for an already accepted Model execution.
/// The consuming Host supplies its own current boundary. This exposes no
/// Ledger, capacity, dispatch permission or physical cleanup acknowledgement.
pub fn original_completed_model_matches_parent(
  execution : ModelExecution,
  ledger : @resources.Ledger,
) -> Bool {
  let state = execution.state
  !execution.advancing &&
  !state.reclaimed &&
  state.accepted &&
  state.original_startup is Some(startup) &&
  startup.used &&
  physical_equal(startup.ledger, state.ledger) &&
  physical_equal(state.ledger, ledger) &&
  physical_equal(startup.rows, state.rows) &&
  startup.scope is Some(scope) &&
  state.call_scope is Some(original) &&
  physical_equal(scope, original)
}
