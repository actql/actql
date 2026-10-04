///|
/// Host-private Source custody; no provider read or completed Run is created.
#export_name("clientProgramExportSourceCapture")
pub fn client_program_export_source_capture(
  source : @query.CapturedInputSource,
  requirement : @planning.QueryRequirement,
  binding : String,
) -> Result[
  @client_local_host.ClientSourceCaptureExport,
  @client_local_host.ClientSourceCaptureIssue,
] {
  @client_local_host.export_client_source_capture(source, requirement, binding)
}

///|
#export_name("clientProgramSourceCaptureExportRequirement")
pub fn client_program_source_capture_export_requirement(
  value : @client_local_host.ClientSourceCaptureExport,
) -> String {
  @client_local_host.client_source_capture_export_requirement(value)
}

///|
#export_name("clientProgramSourceCaptureExportBinding")
pub fn client_program_source_capture_export_binding(
  value : @client_local_host.ClientSourceCaptureExport,
) -> String {
  @client_local_host.client_source_capture_export_binding(value)
}

///|
#export_name("clientProgramSourceCaptureExportDescriptor")
pub fn client_program_source_capture_export_descriptor(
  value : @client_local_host.ClientSourceCaptureExport,
) -> String {
  @client_local_host.client_source_capture_export_descriptor(value)
}

///|
#export_name("clientProgramSourceCaptureExportRows")
pub fn client_program_source_capture_export_rows(
  value : @client_local_host.ClientSourceCaptureExport,
) -> Array[String] {
  @client_local_host.client_source_capture_export_rows(value)
}

///|
#export_name("clientProgramRestoreSourceCapture")
pub fn client_program_restore_source_capture(
  requirement : @planning.QueryRequirement,
  saved_requirement_cid : String,
  expected_binding : String,
  saved_binding : String,
  descriptor : String,
  rows : Array[String],
  ledger : @resources.Ledger?,
  capacity : @client_local_host.ClientDuckDBCaptureCapacity,
  custody_available : () -> Bool,
) -> Result[
  @client_local_host.ClientAccountedSourceCapture,
  @client_local_host.ClientSourceCaptureIssue,
] {
  let receiving_ledger = match ledger {
    Some(value) => value
    None => {
      let capacity = @client_local_host.client_duckdb_capture_capacity_values(
        capacity,
      )
      match
        @resources.create_ledger({
          planning_work: 0,
          attempts: 1,
          holdings: 1,
          transfer_bytes: 0L,
          retained_bytes: capacity[0],
          execution_bytes: capacity[1],
        }) {
        Ok(value) => value
        Err(issue) => return Err(@client_local_host.Physical(issue))
      }
    }
  }
  @client_local_host.restore_accounted_client_source_capture(
    requirement, saved_requirement_cid, expected_binding, saved_binding, descriptor,
    rows, receiving_ledger, capacity, custody_available,
  )
}

///|
#export_name("clientProgramSourceCaptureSource")
pub fn client_program_source_capture_source(
  value : @client_local_host.ClientAccountedSourceCapture,
) -> @query.CapturedInputSource? {
  @client_local_host.accounted_client_source_capture_source(value)
}

///|
#export_name("clientProgramCloseSourceCapture")
pub fn client_program_close_source_capture(
  value : @client_local_host.ClientAccountedSourceCapture,
) -> Bool {
  @client_local_host.close_accounted_client_source_capture(value)
}

///|
#export_name("clientProgramSourceCaptureRetainTask")
pub fn client_program_source_capture_retain_task(
  value : @client_local_host.ClientAccountedSourceCapture,
  dag : @strategy.CapturedDAG,
  task : Int,
) -> Result[Unit, @client_local_host.ClientSourceCaptureIssue] {
  @client_local_host.retain_accounted_client_source_capture_task(
    value, dag, task,
  )
}

///|
#export_name("clientProgramSourceCaptureCleanupPending")
pub fn client_program_source_capture_cleanup_pending(
  value : @client_local_host.ClientAccountedSourceCapture,
) -> Bool {
  @client_local_host.accounted_client_source_capture_cleanup_pending(value)
}

///|
#export_name("clientProgramSourceCaptureUsage")
pub fn client_program_source_capture_usage(
  value : @client_local_host.ClientAccountedSourceCapture,
) -> Array[Int64] {
  let usage = @client_local_host.accounted_client_source_capture_usage(value)
  [
    usage.held_bytes,
    usage.reserved_retention_bytes,
    usage.reserved_execution_bytes,
  ]
}
