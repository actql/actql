///|
// Use the selected checked Direct root, not input position or a second Ledger.
// This entry is preparation before physical I/O. The original Scope remains
// the census owner of Direct, keyed Row children, assembly and prefix holdings.
// Trusted bootstrap/preparation must fund transient selection/control first;
// no normal numeric profile, Source grant or Model send grant is supplied.
pub fn start_client_original_keyed_direct_row_acquisition(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  prepared : @publication_host.PreparedClientProgram,
  keyed : @publication_host.ClientKeyedAcquisition,
  acquisition : @row_source_host.RowAcquisition,
  nonce : String,
  verify : (@row_source_host.RowAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_scratch : Int64,
) -> Result[@row_source_host.RowRun, ClientOriginalRowAcquisitionIssue] {
  let ledger = match
    @publication_host.borrow_client_original_keyed_direct_ledger(
      scope,
      compiled,
      definition,
      plan,
      prepared,
      keyed,
      @row_source_host.row_acquisition_requirement(acquisition),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  @row_source_host.start_accounted_row_acquisition(
    acquisition, nonce, verify, ledger, transfer_bytes, execution_scratch,
  ).map_err(issue => Acquisition(issue))
}

///|
pub(all) enum ClientOriginalKeyedLookupIssue {
  Original(@publication_host.ClientModelReadPreparationIssue)
  Capture(@query.CapturedSourceIssue)
  Lookup(@publication_host.ClientKeyedRequestIssue)
}

///|
// Exact original Row custody, not a Source reconstructed from response bytes.
// The caller keeps this Direct capture and all later per-key RowRuns until
// existing assembly/consumer cleanup; no second Source acquisition on failure.
pub fn start_client_original_keyed_lookup(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  prepared : @publication_host.PreparedClientProgram,
  keyed : @publication_host.ClientKeyedAcquisition,
  capture : @row_source_host.RowSourceCapture,
  max_entries : Int,
  max_name_bytes : Int,
  max_bytes : Int,
  max_work : Int,
) -> Result[
  @publication_host.ClientKeyedLookupInput,
  ClientOriginalKeyedLookupIssue,
] {
  let source = match @row_source_host.row_capture_source(capture) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let ledger = match
    @publication_host.borrow_client_original_keyed_captured_ledger(
      scope, compiled, definition, plan, prepared, keyed, source,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  if @row_source_host.row_capture_original_prefix_requirement(capture, ledger)
    is None {
    return Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState)),
    )
  }
  let left = match
    @publication_host.prepare_client_keyed_capture_left_read(
      keyed, source, max_entries, max_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Lookup(issue))
  }
  // Input binding also invokes liveness; recheck exact Row tokens afterwards.
  if @row_source_host.row_capture_original_prefix_requirement(capture, ledger)
    is None {
    return Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState)),
    )
  }
  @publication_host.start_client_original_keyed_lookup_input(
    scope, compiled, definition, plan, prepared, keyed, left, max_bytes, max_work,
  ).map_err(issue => Lookup(issue))
}
