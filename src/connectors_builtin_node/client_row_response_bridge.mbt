// Same-runtime original row response borrowing; no wire reconstructs these types.

///|
#export_name("clientProgramRowSourceStartProviderAccounted")
pub fn client_program_row_source_start_provider_accounted(
  acquisition : @client_row_source_host.RowAcquisition,
  capacity : @execution.ExecutionCapacity?,
  nonce : String,
  verify : (@client_row_source_host.RowAttempt) -> Bool,
  ledger : @resources.Ledger,
  transfer_bytes : Int64,
  execution_scratch : Int64,
) -> Result[
  @client_row_source_host.RowRun,
  @client_row_source_host.RowHostIssue,
] {
  @client_row_source_host.start_accounted_provider_row_acquisition(
    acquisition, capacity, nonce, verify, ledger, transfer_bytes, execution_scratch,
  )
}

///|
#export_name("clientProgramRowSourceCheckOriginalAcquisition")
pub fn client_program_row_source_check_original_acquisition(
  acquisition : @client_row_source_host.RowAcquisition,
  declaration : @client_row_source_host.RowDeclaration,
  requirement : @planning.QueryRequirement,
) -> Result[Unit, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.check_row_acquisition_original(
    acquisition, declaration, requirement,
  )
}

///|
#export_name("clientProgramRowSourceBorrowResponses")
pub fn client_program_row_source_borrow_responses(
  run : @client_row_source_host.RowRun,
  acquisition : @client_row_source_host.RowAcquisition,
) -> Result[
  @client_row_source_host.RowRunResponseBorrow,
  @client_row_source_host.RowHostIssue,
] {
  @client_row_source_host.borrow_row_run_responses(run, acquisition)
}

///|
#export_name("clientProgramRowSourceBindResponseCleanup")
pub fn client_program_row_source_bind_response_cleanup(
  value : @client_row_source_host.RowRunResponseBorrow,
  cleanup : () -> Bool,
) -> Result[Unit, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.bind_row_run_response_borrow_cleanup(value, cleanup)
}
