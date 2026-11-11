///|
pub(all) enum ClientOriginalKeyedChildIssue {
  Lookup(@publication_host.ClientKeyedRequestIssue)
  Acquisition(@row_source_host.RowHostIssue)
}

///|
// The checked selected request and assembly remain in the existing Host owner.
// Core Local selects the existing Row receiver, not a second Source executor.
// Preparation tuples/closures/Row controls must already fit original bootstrap;
// the ordinary wire budgets below do not establish a normal physical profile.
pub fn start_client_original_keyed_row_acquisition(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  prepared : @publication_host.PreparedClientProgram,
  keyed : @publication_host.ClientKeyedAcquisition,
  lookup : @publication_host.ClientKeyedLookupInput,
  request : @publication_host.ClientKeyedRequest,
  declaration : @row_source_host.RowDeclaration,
  limits : @row_source_host.RowKeyedLimits,
  nonce : String,
  verify : (@row_source_host.RowAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_scratch : Int64,
  cleanup_confirmed : (@row_source_host.RowAttempt) -> Bool,
) -> Result[@row_source_host.RowRun, ClientOriginalKeyedChildIssue] {
  let (_, _, _, _, original_request) = match
    @publication_host.borrow_client_original_keyed_child(
      scope, compiled, definition, plan, prepared, keyed, lookup, request,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Lookup(issue))
  }
  let available = () => {
    @publication_host.client_original_keyed_lookup_available(
      scope, compiled, definition, plan, prepared, keyed, lookup,
    )
  }
  let acquisition = match
    @row_source_host.prepare_keyed_row_acquisition(
      @publication_host.client_keyed_acquisition_owner(keyed),
      @publication_host.client_keyed_acquisition_facts(keyed),
      original_request,
      declaration,
      limits,
      input_available=Some(available),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Acquisition(issue))
  }
  let (ledger, identity, assembly, children, selected_request) = match
    @publication_host.borrow_client_original_keyed_child(
      scope, compiled, definition, plan, prepared, keyed, lookup, request,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Lookup(issue))
  }
  if !physical_equal(original_request, selected_request) {
    return Err(Lookup(@publication_host.ForeignLeft))
  }
  // Transport verification and current original custody are distinct. A true
  // transport callback cannot revive a synchronously stopped/parked Scope.
  let original_verify = attempt => verify(attempt) && available()
  @row_source_host.start_original_accounted_keyed_row_acquisition(
    acquisition, nonce, original_verify, ledger, identity, assembly, children, transfer_bytes,
    execution_scratch, cleanup_confirmed,
  ).map_err(issue => Acquisition(issue))
}

///|
// The caller still owns the same child RowRun until consumer/transport cleanup.
// Borrow only its actual retained exact request, never response-rebuilt input
// or a same-schema foreign capture. Response cardinality/correlation was checked
// by that Row owner and is rechecked by the existing bounded assembly admission.
pub fn begin_client_original_keyed_lookup_response(
  keyed : @publication_host.ClientKeyedAcquisition,
  lookup : @publication_host.ClientKeyedLookupInput,
  request : @publication_host.ClientKeyedRequest,
  capture : @row_source_host.RowKeyedSourceCapture,
) -> Result[Unit, ClientOriginalKeyedChildIssue] {
  guard @publication_host.client_keyed_request_value(request, keyed)
    is Some(original_request) &&
    @row_source_host.keyed_row_capture_matches_request(
      capture, original_request,
    ) else {
    return Err(Lookup(@publication_host.ForeignLeft))
  }
  let read = match @row_source_host.keyed_row_capture_read(capture) {
    Ok(value) => value
    Err(issue) => return Err(Acquisition(issue))
  }
  @publication_host.begin_client_keyed_lookup_response(
    lookup,
    request,
    read,
    capture=Some(capture),
  ).map_err(issue => Lookup(issue))
}
