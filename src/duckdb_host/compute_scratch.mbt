///|
pub fn configured_strategy_scratch_capacity(
  setup : StrategyComputeHostConfiguration,
) -> Int64? {
  @duckdb_compute.duckdb_task_scratch_capacity(
    setup.compute.limits,
    setup.compute.transport,
  )
}
