///|
// Same checked Scope/Run/consumer and its already reserved read bytes. No
// initial-aggregate comparison, Ledger projection, claim/reset or send grant.
pub fn client_model_handed_off_read_capacity_available(
  scope : ClientModelReadScope,
  value : ClientModelReadConsumer,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Bool {
  client_model_origin_matches(scope.origin, compiled, definition, plan) &&
  @resources.funded_read_consumer_handed_off_capacity_covers(
    value.consumer,
    scope.origin,
    retained_bytes,
    execution_bytes,
  )
}
