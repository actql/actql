///|
// A borrowed custody view of the EXISTING keyed assembly, not another Owner
// or an execution state machine. Only prefixed callers allocate this record.
struct ClientOriginalKeyedPrefixLookup {
  mut lookup : ClientKeyedLookupInput?
  mut prefix : @resources.Reservation?
  mut scope : ClientModelReadScope?
}

///|
pub fn client_original_keyed_prefix_lookup_input(
  value : ClientOriginalKeyedPrefixLookup,
) -> ClientKeyedLookupInput? {
  value.lookup
}

///|
// Closed Core Local supplies its real prefix completion and the exact input
// retained by that execution. Shape/CID/count equality cannot substitute them.
pub fn start_client_original_keyed_prefix_lookup(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  prepared : PreparedClientProgram,
  keyed : ClientKeyedAcquisition,
  source : @query.CapturedInputSource,
  output : @execution.CompletedOutput,
  input : @execution.ProducerRead,
  prefix : @resources.Reservation,
  max_entries : Int,
  max_name_bytes : Int,
  max_bytes : Int,
  max_work : Int,
) -> Result[ClientOriginalKeyedPrefixLookup, ClientKeyedRequestIssue] {
  guard @query.captured_source_matches_segment_input(source, input) &&
    @execution.completed_output_matches_segment_input(output, input) else {
    return Err(ForeignLeft)
  }
  let ledger = match
    borrow_client_original_keyed_captured_ledger(
      scope,
      compiled,
      definition,
      plan,
      prepared,
      keyed,
      source,
      prefix=Some(prefix),
    ) {
    Ok(value) => value
    Err(_) => return Err(Assembly("original_prefix_custody_changed"))
  }
  let owner = keyed.owner
  let bound = match
    @execution.bind_completed_operation_input(
      owner,
      @acquisition.keyed_join_step(keyed.binding.join),
      0,
      owner,
      output,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignLeft)
  }
  let read = match
    @execution.prepare_producer_read(owner, bound, max_entries, max_name_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Read(issue))
  }
  let left : ClientKeyedLeftRead = {
    acquisition: keyed,
    source: Some(source),
    composed: None,
    read,
    requests: 0L,
    attempts: 0L,
    request_bytes: 0L,
    response_bytes: 0L,
    decoded_bytes: 0L,
    started_ms: None,
    observed_ms: 0L,
    lookup_issue: None,
    assembly_started: false,
  }
  // Producer liveness above can synchronously stop or alter the original.
  // The existing constructor checks its exact prefix census again before
  // reservation/materialization; ordinary None paths remain unchanged.
  let lookup = match
    start_client_keyed_lookup_input_owned(
      left,
      ledger,
      max_bytes,
      max_work,
      Some(scope.identity),
      prefix=Some(prefix),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ lookup: Some(lookup), prefix: Some(prefix), scope: Some(scope), })
}

///|
// Same existing borrower as the ordinary child, plus its exact live prefix
// reservation. No external row aggregate or replacement Ledger is trusted.
pub fn borrow_client_original_keyed_prefix_child(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  prepared : PreparedClientProgram,
  keyed : ClientKeyedAcquisition,
  value : ClientOriginalKeyedPrefixLookup,
  request : ClientKeyedRequest,
) -> Result[
  (
    @resources.Ledger,
    @resources.OriginalLedgerIdentity,
    @resources.Reservation,
    Int,
    @acquisition.KeyedRowRequest,
    @resources.Reservation,
  ),
  ClientKeyedRequestIssue,
] {
  guard value.scope is Some(original) &&
    physical_equal(original, scope) &&
    value.lookup is Some(lookup) &&
    value.prefix is Some(prefix) else {
    return Err(ForeignLeft)
  }
  borrow_client_original_keyed_child(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    keyed,
    lookup,
    request,
    prefix=Some(prefix),
  ).map(tuple => (tuple.0, tuple.1, tuple.2, tuple.3, tuple.4, prefix))
}

///|
pub fn cleanup_client_original_keyed_prefix_lookup(
  value : ClientOriginalKeyedPrefixLookup,
  quantum : Int,
) -> Result[Bool, ClientKeyedRequestIssue] {
  guard value.lookup is Some(lookup) else { return Ok(true) }
  if !@resources.original_keyed_lookup_dependents_retired(
      lookup.ledger,
      lookup.reservation,
    ) {
    return Ok(false)
  }
  let complete = match cleanup_client_keyed_lookup_input(lookup, quantum) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if complete {
    value.lookup = None
    value.prefix = None
    value.scope = None
  }
  Ok(complete)
}
