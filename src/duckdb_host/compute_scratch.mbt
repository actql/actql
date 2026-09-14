///|
pub fn configured_strategy_scratch_capacity(
  setup : StrategyComputeHostConfiguration,
) -> Int64? {
  @strategy.duckdb_task_scratch_capacity(
    setup.compute.limits,
    setup.compute.transport,
  )
}
