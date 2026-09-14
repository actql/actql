///|
pub fn configured_strategy_retention_capacity(
  setup : StrategyComputeHostConfiguration,
) -> Int64? {
  @strategy.duckdb_task_retention_capacity(setup.compute.limits)
}
