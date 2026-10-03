///|
/// Read the existing Run ledger for bounded installed-Host diagnostics.
#export_name("clientProgramMultiCapturedLedgerUsage")
pub fn client_program_multi_captured_ledger_usage(
  ledger : @resources.Ledger,
) -> Array[Int64] {
  let usage = @resources.ledger_usage(ledger)
  [
    usage.planning_work.to_int64(),
    usage.attempts.to_int64(),
    usage.holdings.to_int64(),
    usage.transferred_bytes,
    usage.reserved_transfer_bytes,
    usage.held_bytes,
    usage.reserved_retention_bytes,
    usage.reserved_execution_bytes,
    usage.uncertain_transfer_bytes,
  ]
}

///|
#export_name("clientProgramPrepareMultiCapturedLocalLedger")
pub fn client_program_prepare_multi_captured_local_ledger(
  prepared : @publication_host.PreparedClientProgram,
  acquisitions : Array[@duckdb_host.NativeHostConfiguration],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  @client_local_host.prepare_multi_captured_local_ledger(
    prepared, acquisitions, transport_bytes, transport_execution_bytes, registry_body,
    values_body, fragment_body, ordered_body,
  )
}

///|
#export_name("clientProgramOpenMultiCapturedLocalHost")
pub fn client_program_open_multi_captured_local_host(
  prepared : @publication_host.PreparedClientProgram,
  sources : Array[@query.CapturedInputSource],
  ledger : @resources.Ledger,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  if sources.length() != 2 {
    return None
  }
  @client_local_host.open_multi_captured_local_host(
    prepared,
    [(0, sources[0]), (1, sources[1])],
    ledger,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    provider_factory=installed_client_family_providers,
  )
}
