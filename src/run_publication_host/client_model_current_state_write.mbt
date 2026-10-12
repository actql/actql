///|
// Exact existing Resource cursor, not another wrapper/control/Owner. Host
// installation still funds the complete Writer/Store/control overlap first.
pub type ClientModelCurrentStateWrite = @resources.OriginalCurrentStateWrite[
  ClientModelReadOrigin,
]

///|
// The actual Model caller checks quiescence immediately before this synchronous
// issuer. Ordinary park is not prepaid, and cannot be substituted for this.
pub fn park_client_model_read_consumer_for_state_write(
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
  @resources.park_original_resource_consumer_for_state_write(
    consumer.consumer,
    scope.origin,
  ).map_err(issue => Resource(issue))
}

///|
pub fn start_client_model_current_state_write(
  park : ClientModelResourcePark,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  writer : @encode.Writer,
) -> Result[ClientModelCurrentStateWrite, @resources.OriginalStateWriteIssue] {
  guard client_model_resource_park_current(
      park, scope, compiled, definition, plan,
    )
    is Some(_) else {
    return Err(@resources.Original(@resources.ChangedOriginalState))
  }
  @resources.start_original_current_state_write(park, scope.origin, writer)
}

///|
// Repeat original Scope and exact cursor/park checks before advancing. A
// foreign caller refuses without cancelling or spending another cursor.
pub fn advance_client_model_current_state_write(
  value : ClientModelCurrentStateWrite,
  park : ClientModelResourcePark,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  quantum : Int,
) -> @resources.OriginalStateWritePoll {
  guard client_model_resource_park_current(
      park, scope, compiled, definition, plan,
    )
    is Some(_) &&
    @resources.original_current_state_write_current(value, park) is Some(_) else {
    return @resources.StateWriteFailed(
      @resources.Original(@resources.ChangedOriginalState),
      work=0,
    )
  }
  @resources.advance_original_current_state_write(value, quantum)
}

///|
pub fn cancel_client_model_current_state_write(
  value : ClientModelCurrentStateWrite,
) -> Unit {
  @resources.cancel_original_current_state_write(value)
  // This retires a cursor only. Original park/Model/Store custody stays live.
}
