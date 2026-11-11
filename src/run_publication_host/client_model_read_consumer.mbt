///|
// A borrowed one-shot control for the same original read, not another owner.
// This reference, the resource control and its phase payload must be included
// in the Host's complete simultaneous envelope before calling the issuer.
// No separate origin/read graph is retained here after resource retirement.
struct ClientModelReadConsumer {
  consumer : @resources.FundedReadConsumer[ClientModelReadOrigin]
}

///|
pub fn claim_client_model_read_preparation(
  value : ClientModelReadPreparation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[ClientModelReadConsumer, ClientModelReadPreparationIssue] {
  if !client_model_read_origin_matches(value, compiled, definition, plan) {
    return Err(ForeignRun)
  }
  if value.consumer is Some(consumer) {
    if value.consumer_claimed {
      return Err(Resource(@resources.SpentClaim))
    }
    if !@resources.funded_read_consumer_available(
        consumer,
        value.origin,
        retained_bytes,
        execution_bytes,
      ) ||
      value.consumer_claimed {
      return Err(Resource(@resources.ChangedOriginalState))
    }
    value.consumer_claimed = true
    return Ok({ consumer, })
  }
  match
    @resources.claim_funded_read_preparation(
      value.claim,
      value.origin,
      retained_bytes,
      execution_bytes,
    ) {
    Ok(consumer) => Ok({ consumer, })
    Err(issue) => Err(Resource(issue))
  }
}

///|
pub fn client_model_read_consumer_available(
  value : ClientModelReadConsumer,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Bool {
  guard @resources.funded_read_consumer_origin(value.consumer) is Some(origin) else {
    return false
  }
  client_model_origin_matches(origin, compiled, definition, plan) &&
  @resources.funded_read_consumer_available(
    value.consumer,
    origin,
    retained_bytes,
    execution_bytes,
  )
}

///|
// The same ticket can be aliased by a caller, but can admit only one consuming
// Execution. Enter before constructing it; failed starts never reset the claim.
pub fn enter_client_model_read_consumer(
  value : ClientModelReadConsumer,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, ClientModelReadPreparationIssue] {
  guard @resources.funded_read_consumer_origin(value.consumer) is Some(origin) else {
    return Err(Resource(@resources.SpentClaim))
  }
  if !client_model_origin_matches(origin, compiled, definition, plan) {
    return Err(ForeignRun)
  }
  @resources.enter_funded_read_consumer(
    value.consumer,
    origin,
    retained_bytes,
    execution_bytes,
  ).map_err(issue => Resource(issue))
}

///|
/// Borrow the actual Plan's Model allowance on this same original consumer.
/// This immutable DATA is not remaining capacity or a dispatch permission;
/// the original input handoff still checks current rows and issues the token.
pub fn client_model_read_consumer_model_limits(
  value : ClientModelReadConsumer,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Result[@resources.LedgerLimits?, ClientModelReadPreparationIssue] {
  guard @resources.funded_read_consumer_origin(value.consumer) is Some(origin) &&
    client_model_origin_matches(origin, compiled, definition, plan) else {
    return Err(ForeignRun)
  }
  Ok(origin.model_limits)
}

///|
// Continue through the existing current scope/CompletedOutput input predicate,
// after the early allocation has claimed this exact read once. This is not
// permission to dispatch, or authentication of a restored response/Store.
pub fn handoff_client_model_read_consumer_input_capacity(
  value : ClientModelReadConsumer,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  scope : ClientInferCallScope,
  rows : @execution.PreparedInferRows,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[
  (@resources.Ledger, @resources.CapacityReservation),
  ClientModelInputCapacityIssue,
] {
  guard @resources.funded_read_consumer_origin(value.consumer) is Some(origin) else {
    return Err(Read(Resource(@resources.SpentClaim)))
  }
  if !client_model_origin_matches(origin, compiled, definition, plan) {
    return Err(Read(ForeignRun))
  }
  match check_client_model_input_scope(compiled, plan, scope, rows) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  @resources.handoff_funded_read_consumer_capacity(
    value.consumer,
    origin,
    retained_bytes,
    execution_bytes,
  ).map_err(issue => Read(Resource(issue)))
}

///|
pub fn stop_client_model_read_consumer(
  value : ClientModelReadConsumer,
) -> Result[Unit, ClientModelReadPreparationIssue] {
  @resources.stop_funded_read_consumer(value.consumer).map_err(issue => {
    Resource(issue)
  })
}

///|
pub fn settle_client_model_read_consumer(
  value : ClientModelReadConsumer,
  physical_cleanup_complete : Bool,
) -> Result[Unit, ClientModelReadPreparationIssue] {
  @resources.settle_funded_read_consumer(
    value.consumer,
    physical_cleanup_complete,
  ).map_err(issue => Resource(issue))
}
