///|
// Same Row receiver and assembly, retaining the actual prefix reservation.
// No alternate acquisition, Ledger, Source permission or per-row budget.
pub fn start_client_original_keyed_prefix_row_acquisition(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  prepared : @publication_host.PreparedClientProgram,
  keyed : @publication_host.ClientKeyedAcquisition,
  value : @publication_host.ClientOriginalKeyedPrefixLookup,
  request : @publication_host.ClientKeyedRequest,
  declaration : @row_source_host.RowDeclaration,
  limits : @row_source_host.RowKeyedLimits,
  nonce : String,
  verify : (@row_source_host.RowAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_scratch : Int64,
  cleanup_confirmed : (@row_source_host.RowAttempt) -> Bool,
) -> Result[@row_source_host.RowRun, ClientOriginalKeyedChildIssue] {
  guard @publication_host.client_original_keyed_prefix_lookup_input(value)
    is Some(lookup) else {
    return Err(Lookup(@publication_host.ForeignLeft))
  }
  let (_, _, _, _, original_request, _) = match
    @publication_host.borrow_client_original_keyed_prefix_child(
      scope, compiled, definition, plan, prepared, keyed, value, request,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Lookup(issue))
  }
  let available = () => {
    @publication_host.client_original_keyed_prefix_lookup_input(value)
    is Some(_) &&
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
  let (ledger, identity, assembly, children, selected_request, prefix) = match
    @publication_host.borrow_client_original_keyed_prefix_child(
      scope, compiled, definition, plan, prepared, keyed, value, request,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Lookup(issue))
  }
  if !physical_equal(original_request, selected_request) {
    return Err(Lookup(@publication_host.ForeignLeft))
  }
  let original_verify = attempt => verify(attempt) && available()
  @row_source_host.start_original_accounted_keyed_row_acquisition(
    acquisition,
    nonce,
    original_verify,
    ledger,
    identity,
    assembly,
    children,
    transfer_bytes,
    execution_scratch,
    cleanup_confirmed,
    prefix=Some(prefix),
  ).map_err(issue => Acquisition(issue))
}
