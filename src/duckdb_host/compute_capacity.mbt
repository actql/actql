///|
pub fn configured_strategy_retention_capacity(
  setup : StrategyComputeHostConfiguration,
) -> Int64? {
  @duckdb_compute.duckdb_task_retention_capacity(setup.compute.limits)
}
