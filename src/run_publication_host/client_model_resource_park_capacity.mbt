///|
// Validate the same checked Scope/Run and original read reservation before
// physical metadata acquisition. No Ledger/token projection, allocation or
// profile is added. A true predicate is not proof of physical adequacy, Store
// ACK, current-cut admission or permission to send. An absent/unjustified
// installation supplier must still refuse before acquisition, not pass zero.
pub fn client_model_parked_read_capacity_available(
  park : ClientModelResourcePark,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Bool {
  client_model_origin_matches(scope.origin, compiled, definition, plan) &&
  @resources.original_resource_park_read_capacity_covers(
    park,
    scope.origin,
    retained_bytes,
    execution_bytes,
  )
}
