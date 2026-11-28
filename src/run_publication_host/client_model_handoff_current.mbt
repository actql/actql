///|
/// Keep the same checked Run/plan binding after the one-shot Model handoff.
/// This observes the existing ticket's lifetime, not the initial aggregate,
/// another startup, durable Store authentication or current dispatch authority.
pub fn client_model_read_consumer_handed_off_current(
  value : ClientModelReadConsumer,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Bool {
  guard @resources.funded_read_consumer_handed_off_origin(value.consumer)
    is Some(origin) else {
    return false
  }
  client_model_origin_matches(origin, compiled, definition, plan)
}

///|
/// The earlier Model may lend its Result only under the exact Scope that
/// funded its handed-off Read on this Run's ledger.
pub fn client_model_read_scope_handed_off_from(
  scope : ClientModelReadScope,
  consumer : ClientModelReadConsumer,
  ledger : @resources.Ledger,
) -> Bool {
  physical_equal(scope.ledger, ledger) &&
  @resources.original_ledger_inventory_live(scope.identity) &&
  @resources.funded_read_consumer_handed_off_origin(consumer.consumer)
  is Some(origin) &&
  physical_equal(origin, scope.origin)
}
