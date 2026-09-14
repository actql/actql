///|
/// Trusted application preparation. No connection, source grant or SQL string
/// is accepted; the selected candidate already owns its fixed producer input.
struct ComputeHostConfiguration {
  choice : @planning.FixedComputeChoice
  prepared : @planning.PreparedCompute[@duckdb.FixedCompute]
  generated : @execution.GeneratedSequence
  limits : @planning.DuckDBComputeLimits
  transport : @duckdb.TransportColumnLimits
}

///|
pub fn configure_compute_host(
  choice : @planning.FixedComputeChoice,
  prepared : @planning.PreparedCompute[@duckdb.FixedCompute],
  generated : @execution.GeneratedSequence,
  limits : @planning.DuckDBComputeLimits,
  transport : @duckdb.TransportColumnLimits,
) -> ComputeHostConfiguration {
  { choice, prepared, generated, limits, transport, }
}

///|
pub fn start_configured_compute_host(
  setup : ComputeHostConfiguration,
  verify : (@planning.DuckDBComputeAttempt) -> Bool,
) -> Result[@planning.DuckDBComputeAttempt, @planning.DuckDBComputeIssue] {
  @planning.start_duckdb_compute_attempt(
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
) -> @strategy.Ledger {
  @strategy.captured_dag_ledger(setup.graph)
}

///|
pub fn start_configured_strategy_compute_host(
  setup : StrategyComputeHostConfiguration,
  verify : (@planning.DuckDBComputeAttempt) -> Bool,
) -> Result[@planning.DuckDBComputeAttempt, @strategy.RunIssue] {
  let c = setup.compute
  @strategy.start_captured_duckdb_task(
    setup.graph,
    setup.task,
    c.choice,
    c.prepared,
    c.generated,
    c.limits,
    verify,
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
