///|
pub(all) enum ClientOriginalRowAcquisitionIssue {
  Original(@publication_host.ClientModelReadPreparationIssue)
  Acquisition(@row_source_host.RowHostIssue)
}

///|
// Only the existing accounted row Owner receives the borrowed Ledger. Its
// registration, reservation, pages, capture and cleanup remain unchanged.
// The trusted installation must separately fund preparation/control overlap
// before this entry; these transport bounds are not a complete Model profile.
pub fn start_client_original_row_acquisition(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  prepared : @publication_host.PreparedClientProgram,
  acquisition : @row_source_host.RowAcquisition,
  nonce : String,
  verify : (@row_source_host.RowAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_scratch : Int64,
) -> Result[@row_source_host.RowRun, ClientOriginalRowAcquisitionIssue] {
  let ledger = match
    @publication_host.borrow_client_original_row_acquisition_ledger(
      scope,
      compiled,
      definition,
      plan,
      prepared,
      @row_source_host.row_acquisition_requirement(acquisition),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  // `verify` is the existing exact-attempt transport settlement callback, not
  // a Scope/Model admission callback or a generic executor receiving Ledger.
  @row_source_host.start_accounted_row_acquisition(
    acquisition, nonce, verify, ledger, transfer_bytes, execution_scratch,
  ).map_err(issue => Acquisition(issue))
}
