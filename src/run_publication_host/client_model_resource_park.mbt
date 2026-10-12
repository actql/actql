///|
// The exact resource token is reused, not wrapped in another retained record,
// map or scope field. Its origin remains the checked original Host binding.
// This API freezes Resource facts only; it proves no Model/Entry park, Store
// ACK, journal COMMIT, restoration, physical layout or permission to send.
pub type ClientModelResourcePark = @resources.OriginalResourcePark[
  ClientModelReadOrigin,
]

///|
// The installed Host must fund the resource fence/control and transient checks
// in the same original envelope before entry. No default numerical grant is
// derived from the existence of this issuer or a synthetic fixture allowance.
pub fn park_client_model_read_consumer(
  scope : ClientModelReadScope,
  consumer : ClientModelReadConsumer,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Result[ClientModelResourcePark, ClientModelReadPreparationIssue] {
  if !client_model_origin_matches(scope.origin, compiled, definition, plan) {
    return Err(ForeignRun)
  }
  if !@resources.original_ledger_inventory_available(scope.identity) {
    return Err(Resource(@resources.ChangedOriginalState))
  }
  @resources.park_original_resource_consumer(consumer.consumer, scope.origin).map_err(issue => {
      Resource(issue)
    },
  )
}

///|
// Return the same nominal Resource control while its original fence remains
// current. In particular, an async journal invalidation in flight does not
// unpark it. Only the future closed confirmed-COMMIT bridge may resume it.
pub fn client_model_resource_park_current(
  value : ClientModelResourcePark,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> ClientModelResourcePark? {
  if !client_model_origin_matches(scope.origin, compiled, definition, plan) {
    return None
  }
  @resources.original_resource_park_current(value, scope.origin)
}

///|
// Retire only an escaped stale control after actual original cleanup. This
// cannot accept a caller Bool/CID, clear a live fence, or issue a COMMIT ACK.
pub fn retire_client_model_resource_park(
  value : ClientModelResourcePark,
) -> Result[Unit, ClientModelReadPreparationIssue] {
  @resources.retire_original_resource_park(value).map_err(issue => {
    Resource(issue)
  })
}
