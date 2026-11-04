///|
// The checked original Run owns this scope, bootstrap, census and dedicated
// Writer before entry. Reuse its opaque origin and existing read preparation;
// no new Owner, reservation, permission or persistent control is introduced.
// The supplied complete physical envelope must cover Writer/backing, snapshots
// and authentication overlap. This connection does not adopt numeric layout
// coefficients, authenticate stored bytes or restore a Ledger after restart.
pub fn prepare_client_model_read_state(
  scope : ClientModelReadScope,
  writer : @encode.Writer,
  retained_bytes : Int64,
  execution_bytes : Int64,
  binding_work? : Int = 0,
) -> Result[ClientModelReadPreparation, @resources.OriginalStateWriteIssue] {
  // The closed group has one shared descriptor/read. A singular state writer
  // cannot claim that census for one member and strand the other children.
  // Its existing singular path is unchanged; group persistence needs the
  // same complete group holder rather than a per-member competing issuer.
  if scope.group is Some(_) {
    return Err(@resources.Original(@resources.SpentClaim))
  }
  match
    @resources.prepare_original_state_write(
      scope.identity,
      scope.origin,
      writer,
      retained_bytes,
      execution_bytes,
      binding_work~,
    ) {
    Ok((claim, _)) =>
      Ok({
        origin: scope.origin,
        claim,
        consumer: None,
        consumer_claimed: false,
        retired: false,
      })
    Err(issue) => Err(issue)
  }
}

///|
// Every advance stays bound to the same checked Run/Host. Foreign arguments
// are rejected without advancing/cancelling the original Writer. Its existing
// claim phase retains the cursor until completion or original cleanup.
pub fn advance_client_model_read_state(
  value : ClientModelReadPreparation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  quantum : Int,
) -> @resources.OriginalStateWritePoll {
  if !client_model_read_origin_matches(value, compiled, definition, plan) {
    return @resources.StateWriteFailed(
      @resources.Original(@resources.ForeignOrigin),
      work=0,
    )
  }
  @resources.advance_funded_read_state_write(value.claim, value.origin, quantum)
}
