///|
/// Explicit Host-selected physical limits, never replacements for the owned
/// acquisition guards. Configuration carries no transport verifier or callback.
pub(all) struct NativeHostLimits {
  physical : @duckdb.PhysicalResultLimits
  metadata_work : Int
  measurement : @execution.FixedInputGuardMeasureLimits
  completion : @duckdb_query.DuckDBNativeCompletionLimits
  retention : @execution.ValueLimits
  output_rows : Int
  output_entries : Int
  output_name_bytes : Int
  transport : @duckdb.TransportColumnLimits
}

///|
struct NativeHostConfiguration {
  contract : @planning.QueryTwoReceiptContract
  requirement : @planning.QueryRequirement
  choice : @planning.AcquisitionChoice
  candidate : @planning.PreparedAcquisition[
    @duckdb_query.DuckDBNativePreparation,
  ]
  limits : NativeHostLimits
}

///|
/// Called by trusted application preparation using already owned checked data.
/// Startup performs candidate/authority admission before any source operation.
pub fn configure_native_host(
  contract : @planning.QueryTwoReceiptContract,
  requirement : @planning.QueryRequirement,
  choice : @planning.AcquisitionChoice,
  candidate : @planning.PreparedAcquisition[
    @duckdb_query.DuckDBNativePreparation,
  ],
  limits : NativeHostLimits,
) -> NativeHostConfiguration {
  { contract, requirement, choice, candidate, limits, }
}

///|
pub fn configured_native_host_limits(
  value : NativeHostConfiguration,
) -> NativeHostLimits {
  value.limits
}

///|
/// Read the actual admitted acquisition choice; this grants no new authority
/// and does not change the configured candidate or execution limits.
pub fn configured_native_host_choice(
  value : NativeHostConfiguration,
) -> @planning.AcquisitionChoice {
  value.choice
}

///|
/// The checked logical Source selected by this configuration. Physical
/// location is independently supplied by the trusted Site binding.
pub fn configured_native_host_source(
  value : NativeHostConfiguration,
) -> (String, String) {
  @planning.query_requirement_source(value.requirement)
}

///|
pub fn start_configured_native_host(
  value : NativeHostConfiguration,
  nonce : String,
  verify : (@duckdb_query.DuckDBNativeAttempt) -> Bool,
) -> Result[NativeHostRun, NativeHostIssue] {
  let run = match
    start_native_host(
      value.contract,
      value.requirement,
      value.choice,
      value.candidate,
      nonce,
      128,
      value.limits.physical,
      value.limits.metadata_work,
      value.limits.measurement,
      verify,
    ) {
    Ok(run) => run
    Err(issue) => return Err(issue)
  }
  match
    @duckdb_query.stream_duckdb_native_validation(
      run.attempt,
      value.limits.completion.receipts,
      value.limits.completion.demand,
      value.limits.transport.max_rows,
    ) {
    Ok(_) => Ok(run)
    Err(issue) => {
      close_native_host(run)
      Err(Attempt(issue))
    }
  }
}
