///|
// Trusted installation DATA declaration only. The existing Source Owner must
// reserve the complete selected report envelope on its original Ledger. This
// function issues neither reservation, source authority nor physical adequacy.
#export_name("clientProgramRowSourceListingReportCapacity")
pub fn client_program_row_source_listing_report_capacity(
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> @execution.ExecutionCapacity? {
  if retained_bytes <= 0L || execution_bytes < retained_bytes {
    return None
  }
  @execution.execution_capacity(retained_bytes, execution_bytes)
}

///|
// A selected Node installation forwards its original opaque acquisition and
// declaration to the same RowRun/Source Ledger. No second allowance or Owner.
#export_name("clientProgramRowSourceStartListingAccounted")
pub fn client_program_row_source_start_listing_accounted(
  acquisition : @client_row_source_host.RowAcquisition,
  declaration : @execution.ExecutionCapacity?,
  nonce : String,
  verify : (@client_row_source_host.RowAttempt) -> Bool,
  ledger : @resources.Ledger,
  transfer_bytes : Int64,
  execution_scratch : Int64,
) -> Result[
  @client_row_source_host.RowRun,
  @client_row_source_host.RowHostIssue,
] {
  @client_row_source_host.start_accounted_listing_row_acquisition(
    acquisition, declaration, nonce, verify, ledger, transfer_bytes, execution_scratch,
  )
}
