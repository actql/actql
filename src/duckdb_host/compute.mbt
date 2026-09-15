///|
/// Trusted application preparation. No connection, source grant or SQL string
/// is accepted; the selected candidate already owns its fixed producer input.
struct ComputeHostConfiguration {
  choice : @connector.FixedComputeChoice
  prepared : @connector.PreparedCompute[@duckdb.FixedCompute]
  generated : @execution.GeneratedSequence
  limits : @duckdb_compute.DuckDBComputeLimits
  transport : @duckdb.TransportColumnLimits
}

///|
pub fn configure_compute_host(
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[@duckdb.FixedCompute],
  generated : @execution.GeneratedSequence,
  limits : @duckdb_compute.DuckDBComputeLimits,
  transport : @duckdb.TransportColumnLimits,
) -> ComputeHostConfiguration {
  { choice, prepared, generated, limits, transport, }
}

///|
pub fn start_configured_compute_host(
  setup : ComputeHostConfiguration,
  verify : (@duckdb_compute.DuckDBComputeAttempt) -> Bool,
) -> Result[
  @duckdb_compute.DuckDBComputeAttempt,
  @duckdb_compute.DuckDBComputeIssue,
] {
  @duckdb_compute.start_duckdb_compute_attempt(
    setup.choice,
    setup.prepared,
    setup.generated,
    setup.limits,
    verify,
  )
}

///|
pub fn configured_compute_transport(
  setup : ComputeHostConfiguration,
) -> @duckdb.TransportColumnLimits {
  setup.transport
}

///|
struct StrategyComputeHostConfiguration {
  graph : @strategy.CapturedDAG
  task : Int
  compute : ComputeHostConfiguration
}

///|
pub fn configure_strategy_compute_host(
  graph : @strategy.CapturedDAG,
  task : Int,
  compute : ComputeHostConfiguration,
) -> StrategyComputeHostConfiguration {
  { graph, task, compute, }
}

///|
pub fn configured_strategy_compute_ledger(
  setup : StrategyComputeHostConfiguration,
) -> @resources.Ledger {
  @strategy.captured_dag_ledger(setup.graph)
}

///|
pub fn start_configured_strategy_compute_host(
  setup : StrategyComputeHostConfiguration,
  verify : (@duckdb_compute.DuckDBComputeAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_bytes : Int64,
  resident? : @strategy.ResidentInputs,
) -> Result[@duckdb_driver.CapturedDuckDBTask, @strategy.RunIssue] {
  let c = setup.compute
  @duckdb_driver.start_captured_duckdb_task(
    setup.graph,
    setup.task,
    c.choice,
    c.prepared,
    c.generated,
    c.limits,
    c.transport,
    transfer_bytes,
    execution_bytes,
    verify,
    resident?,
  )
}

///|
pub fn configured_strategy_compute_graph(
  setup : StrategyComputeHostConfiguration,
) -> (@strategy.CapturedDAG, Int) {
  (setup.graph, setup.task)
}

///|
pub fn configured_strategy_compute_transport(
  setup : StrategyComputeHostConfiguration,
) -> @duckdb.TransportColumnLimits {
  setup.compute.transport
}

///|
pub fn borrow_configured_resident_inputs(
  setup : StrategyComputeHostConfiguration,
  env : @strategy.ResidentEnvironment,
  tables : Array[@strategy.ResidentTable],
  max_entries : Int,
  max_name_bytes : Int,
  max_sql_bytes : Int,
) -> Result[@strategy.ResidentInputs, @strategy.RunIssue] {
  let c = setup.compute
  @duckdb_driver.prepare_resident_inputs(
    setup.graph,
    env,
    setup.task,
    tables,
    c.choice,
    c.prepared,
    max_entries,
    max_name_bytes,
    max_sql_bytes,
  )
}
