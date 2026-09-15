///|
/// Connector-owned static preparation; no database is created by configuration.
pub(all) struct DuckDBComputeConfiguration {
  sequences : Array[@execution.CompletionPreparation]
  limits : DuckDBDispatchLimits
}

///|
pub fn configure_duckdb_compute(
  driver : @host.DispatchDriver,
  registry : @connector.CapabilityRegistry,
  registration : @connector.CapabilityRegistration,
  configuration : DuckDBComputeConfiguration,
) -> Result[DuckDBDispatchModule, DuckDBDispatchIssue] {
  prepare_duckdb_dispatch_module(
    driver,
    registry,
    registration,
    configuration.sequences,
    configuration.limits,
  )
}
