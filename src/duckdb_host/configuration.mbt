///|
/// Explicit Host-selected physical limits, never replacements for the owned
/// acquisition guards. Configuration carries no transport verifier or callback.
pub(all) struct NativeHostLimits {
  physical : @duckdb.PhysicalResultLimits
  metadata_work : Int
  measurement : @execution.FixedInputGuardMeasureLimits
  completion : @planning.DuckDBNativeCompletionLimits
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
  candidate : @planning.PreparedAcquisition[@planning.DuckDBNativePreparation]
  limits : NativeHostLimits
}

///|
/// Called by trusted application preparation using already owned checked data.
/// Startup performs candidate/authority admission before any source operation.
pub fn configure_native_host(
  contract : @planning.QueryTwoReceiptContract,
  requirement : @planning.QueryRequirement,
  choice : @planning.AcquisitionChoice,
  candidate : @planning.PreparedAcquisition[@planning.DuckDBNativePreparation],
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
pub fn start_configured_native_host(
  value : NativeHostConfiguration,
  nonce : String,
  verify : (@planning.DuckDBNativeAttempt) -> Bool,
) -> Result[NativeHostRun, NativeHostIssue] {
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
  )
}
