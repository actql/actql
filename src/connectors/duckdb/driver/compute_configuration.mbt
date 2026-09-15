///|
/// Trusted application preparation. No connection, source grant or SQL string
/// is accepted; the selected candidate already owns its fixed producer input.
struct ComputeHostConfiguration {
  choice : @connector.FixedComputeChoice
  prepared : @connector.PreparedCompute[@duckdb.FixedCompute]
  generated : @execution.CompletionPreparation
  limits : @compute.DuckDBComputeLimits
  transport : @duckdb.TransportColumnLimits
}

///|
pub fn configure_compute_host(
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[@duckdb.FixedCompute],
  generated : @execution.CompletionPreparation,
  limits : @compute.DuckDBComputeLimits,
  transport : @duckdb.TransportColumnLimits,
) -> ComputeHostConfiguration {
  { choice, prepared, generated, limits, transport, }
}

///|
pub fn start_configured_compute_host(
  setup : ComputeHostConfiguration,
  verify : (@compute.DuckDBComputeAttempt) -> Bool,
) -> Result[@compute.DuckDBComputeAttempt, @compute.DuckDBComputeIssue] {
  @compute.start_duckdb_compute_attempt(
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
  verify : (@compute.DuckDBComputeAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_bytes : Int64,
  resident? : DuckDBResidentInputs,
) -> Result[CapturedDuckDBTask, @strategy.RunIssue] {
  let c = setup.compute
  start_captured_duckdb_task(
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
  env : DuckDBResidentStore,
  tables : Array[@strategy.ResidentTable],
  max_entries : Int,
  max_name_bytes : Int,
  max_sql_bytes : Int,
) -> Result[DuckDBResidentInputs, @strategy.RunIssue] {
  let c = setup.compute
  prepare_resident_inputs(
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

///|
pub fn configured_strategy_retention_capacity(
  setup : StrategyComputeHostConfiguration,
) -> Int64? {
  @compute.duckdb_task_retention_capacity(setup.compute.limits)
}

///|
pub fn configured_strategy_scratch_capacity(
  setup : StrategyComputeHostConfiguration,
) -> Int64? {
  @compute.duckdb_task_scratch_capacity(
    setup.compute.limits,
    setup.compute.transport,
  )
}
