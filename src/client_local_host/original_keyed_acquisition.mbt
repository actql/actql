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
