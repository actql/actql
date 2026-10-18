///|
/// Consume only the existing Resource owner's original imported Source child.
/// No wire/scalar constructor or bare Ledger projection is provided here.
#export_name("clientProgramInstalledSourceReadBegin")
pub fn client_program_installed_source_read_begin(
  child : @resources.ImportedChildLedger,
) -> Result[
  @client_local_host.ClientInstalledSourceRead,
  @client_local_host.ClientInstalledSourceReadIssue,
] {
  @client_local_host.begin_installed_source_read(child)
}

///|
#export_name("clientProgramInstalledSourceReadCheckCurrent")
pub fn client_program_installed_source_read_check_current(
  value : @client_local_host.ClientInstalledSourceRead,
) -> Result[Unit, @client_local_host.ClientInstalledSourceReadIssue] {
  @client_local_host.check_installed_source_read_current(value)
}

///|
#export_name("clientProgramInstalledSourceReadCheckLedger")
pub fn client_program_installed_source_read_check_ledger(
  value : @client_local_host.ClientInstalledSourceRead,
  expected : @resources.Ledger,
) -> Result[Unit, @client_local_host.ClientInstalledSourceReadIssue] {
  @client_local_host.check_installed_source_read_ledger(value, expected)
}

///|
#export_name("clientProgramInstalledSourceReadBindProgram")
pub fn client_program_installed_source_read_bind_program(
  value : @client_local_host.ClientInstalledSourceRead,
  prepared : @publication_host.PreparedClientProgram,
) -> Result[Unit, @client_local_host.ClientInstalledSourceReadIssue] {
  @client_local_host.bind_installed_source_read_program(value, prepared)
}

///|
#export_name("clientProgramInstalledSourceReadBindEffectProgram")
pub fn client_program_installed_source_read_bind_effect_program(
  value : @client_local_host.ClientInstalledSourceRead,
  prepared : @publication_host.PreparedClientEffectComputation,
) -> Result[Unit, @client_local_host.ClientInstalledSourceReadIssue] {
  @client_local_host.bind_installed_source_read_effect_program(value, prepared)
}

///|
#export_name("clientProgramInstalledSourceReadAttachAcquisition")
pub fn client_program_installed_source_read_attach_acquisition(
  value : @client_local_host.ClientInstalledSourceRead,
  declaration : @client_row_source_host.RowDeclaration,
  requirement : @planning.QueryRequirement,
  acquisition : @client_row_source_host.RowAcquisition,
  stage : Int,
  source_index : Int,
) -> Result[Unit, @client_local_host.ClientInstalledSourceReadIssue] {
  @client_local_host.attach_installed_source_read_acquisition(
    value, declaration, requirement, acquisition, stage, source_index,
  )
}

///|
#export_name("clientProgramInstalledSourceReadStartRows")
pub fn client_program_installed_source_read_start_rows(
  value : @client_local_host.ClientInstalledSourceRead,
  acquisition : @client_row_source_host.RowAcquisition,
  nonce : String,
  original_stop : (@client_row_source_host.RowAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_bytes : Int64,
) -> Result[
  @client_row_source_host.RowRun,
  @client_local_host.ClientInstalledSourceReadIssue,
] {
  @client_local_host.start_installed_source_read_rows(
    value, acquisition, nonce, original_stop, transfer_bytes, execution_bytes,
  )
}

///|
#export_name("clientProgramInstalledSourceReadStartProviderRows")
pub fn client_program_installed_source_read_start_provider_rows(
  value : @client_local_host.ClientInstalledSourceRead,
  acquisition : @client_row_source_host.RowAcquisition,
  capacity : @execution.ExecutionCapacity?,
  nonce : String,
  original_stop : (@client_row_source_host.RowAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_bytes : Int64,
) -> Result[
  @client_row_source_host.RowRun,
  @client_local_host.ClientInstalledSourceReadIssue,
] {
  @client_local_host.start_installed_source_read_provider_rows(
    value, acquisition, capacity, nonce, original_stop, transfer_bytes, execution_bytes,
  )
}

///|
#export_name("clientProgramInstalledSourceReadStartListingRows")
pub fn client_program_installed_source_read_start_listing_rows(
  value : @client_local_host.ClientInstalledSourceRead,
  acquisition : @client_row_source_host.RowAcquisition,
  capacity : @execution.ExecutionCapacity?,
  nonce : String,
  original_stop : (@client_row_source_host.RowAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_bytes : Int64,
) -> Result[
  @client_row_source_host.RowRun,
  @client_local_host.ClientInstalledSourceReadIssue,
] {
  @client_local_host.start_installed_source_read_listing_rows(
    value, acquisition, capacity, nonce, original_stop, transfer_bytes, execution_bytes,
  )
}

///|
/// Retires consumer references only; the physical issuer still owns child
/// reporting, external backing and the distinct physical cleanup ACK.
#export_name("clientProgramInstalledSourceReadRetire")
pub fn client_program_installed_source_read_retire(
  value : @client_local_host.ClientInstalledSourceRead,
) -> Result[Unit, @client_local_host.ClientInstalledSourceReadIssue] {
  @client_local_host.retire_installed_source_read(value)
}
