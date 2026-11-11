// Same-runtime original row response borrowing; no wire reconstructs these types.

///|
/// Host-private declaration DATA only. Selection, justification, actual
/// reservation and the original reader's physical retirement remain separate.
#export_name("clientProgramRowSourceProviderCapacity")
pub fn client_program_row_source_provider_capacity(
  retained : Int64,
  execution : Int64,
) -> @execution.ExecutionCapacity? {
  @execution.execution_capacity(retained, execution)
}

///|
#export_name("clientProgramInstalledProviderRowCaptureCapacity")
pub fn client_program_installed_provider_row_capture_capacity(
  acquisition : @client_row_source_host.RowAcquisition,
  capacity : @execution.ExecutionCapacity?,
) -> @client_local_host.ClientInstalledCaptureCapacity? {
  @client_local_host.installed_provider_row_capture_capacity(
    acquisition, capacity,
  )
}

///|
#export_name("clientProgramInstalledProviderRowCaptureCapacityMatches")
pub fn client_program_installed_provider_row_capture_capacity_matches(
  capacity : @client_local_host.ClientInstalledCaptureCapacity,
  acquisition : @client_row_source_host.RowAcquisition,
  declaration : @execution.ExecutionCapacity,
) -> Bool {
  @client_local_host.installed_provider_row_capture_capacity_matches(
    capacity, acquisition, declaration,
  )
}

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

///|
#export_name("clientProgramRowSourceRetireResponseWorkspace")
pub fn client_program_row_source_retire_response_workspace(
  value : @client_row_source_host.RowRunResponseBorrow,
) -> Result[Unit, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.retire_row_run_response_workspace(value)
}

///|
#export_name("clientProgramRowSourceGrowResponseCapacity")
pub fn client_program_row_source_grow_response_capacity(
  value : @client_row_source_host.RowRunResponseBorrow,
  capacity : @execution.ExecutionCapacity,
) -> Result[Unit, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.grow_row_run_response_capacity(value, capacity)
}

///|
#export_name("clientProgramRowSourceGrowResponseConstructionCapacity")
pub fn client_program_row_source_grow_response_construction_capacity(
  value : @client_row_source_host.RowRunResponseBorrow,
  capacity : @execution.ExecutionCapacity,
) -> Result[Unit, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.grow_row_run_response_construction_capacity(
    value, capacity,
  )
}

///|
/// Pure Local Table body-construction DATA. The installing caller retains
/// this SAME returned native capacity and grows its original RowRun before
/// allocation; this projection issues no page, attempt or cleanup proof.
#export_name("clientProgramInstalledTableSourceBodyCapacity")
pub fn client_program_installed_table_source_body_capacity(
  previous : @execution.ExecutionCapacity,
  body_bytes : Int,
  max_depth : Int,
) -> Result[@execution.ExecutionCapacity, @resources.PreparationCapacityIssue] {
  match
    @client_local_host.installed_table_source_body_capacity(
      previous, body_bytes, max_depth,
    ) {
    Some(value) => Ok(value)
    None => Err(@resources.InvalidExtent)
  }
}

///|
#export_name("clientProgramInstalledTableSourceReaderCapacity")
pub fn client_program_installed_table_source_reader_capacity(
  columns : Int,
  profile : @execution.ExecutionCapacity,
) -> @execution.ExecutionCapacity? {
  @client_local_host.installed_table_source_reader_capacity(columns, profile)
}

///|
#export_name("clientProgramInstalledTableSourceSerializationCapacity")
pub fn client_program_installed_table_source_serialization_capacity(
  previous : @execution.ExecutionCapacity,
  bytes : Int,
) -> Result[@execution.ExecutionCapacity, @resources.PreparationCapacityIssue] {
  match
    @client_local_host.installed_table_source_serialization_capacity(
      previous, bytes,
    ) {
    Some(value) => Ok(value)
    None => Err(@resources.InvalidExtent)
  }
}

///|
#export_name("clientProgramRowSourceChargeResponseBody")
pub fn client_program_row_source_charge_response_body(
  run : @client_row_source_host.RowRun,
  body : Bytes,
) -> Result[
  @client_row_source_host.RowPageCharge,
  @client_row_source_host.RowHostIssue,
] {
  @client_row_source_host.charge_row_run_response_body(run, body)
}

///|
#export_name("clientProgramRowSourceEnsureResponseTransferCapacity")
pub fn client_program_row_source_ensure_response_transfer_capacity(
  value : @client_row_source_host.RowRunResponseBorrow,
  bytes : Int64,
) -> Result[Unit, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.ensure_row_run_response_transfer_capacity(
    value, bytes,
  )
}

///|
/// Same original completed RowRun for Query and Whole input variants. This
/// cannot enlarge a foreign capture, mint Source evidence or acknowledge stop.
#export_name("clientProgramIdentifyRowCaptureSourceRelation")
pub fn client_program_identify_row_capture_source_relation(
  source : @query.CapturedInputSource,
  capture : @client_row_source_host.RowSourceCapture,
) -> Result[@query.CapturedSourceRelationIdentity, @query.CapturedSourceIssue] {
  guard @client_row_source_host.row_capture_schema_columns(capture, source)
    is Some(columns) else {
    return Err(@query.Unavailable)
  }
  identify_installed_captured_source(source, 0, columns~)
}

///|
#export_name("clientProgramIdentifyRowCaptureEffectSourceRelation")
pub fn client_program_identify_row_capture_effect_source_relation(
  source : @query.CapturedInputSource,
  capture : @client_row_source_host.RowSourceCapture,
) -> Result[@query.CapturedSourceRelationIdentity, @query.CapturedSourceIssue] {
  guard @client_row_source_host.row_capture_schema_columns(capture, source)
    is Some(columns) else {
    return Err(@query.Unavailable)
  }
  identify_installed_captured_source(source, 16777216, columns~)
}
