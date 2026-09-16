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
  output_file_bytes : Int64?
}

///|
pub fn configure_strategy_compute_host(
  graph : @strategy.CapturedDAG,
  task : Int,
  compute : ComputeHostConfiguration,
  output_file_bytes? : Int64,
) -> StrategyComputeHostConfiguration {
  { graph, task, compute, output_file_bytes, }
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
  retained_storage? : (Int64, () -> Bool),
) -> Result[CapturedDuckDBTask, @strategy.RunIssue] {
  if setup.output_file_bytes is Some(expected) {
    match (expected, retained_storage) {
      (0L, None) => ()
      (bytes, Some((actual, _))) if bytes > 0L && actual == bytes => ()
      _ => return Err(Physical(InvalidCharge))
    }
  }
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
    retained_storage?,
  )
}

///|
pub fn configured_strategy_output_file_bytes(
  setup : StrategyComputeHostConfiguration,
) -> Int64? {
  setup.output_file_bytes
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
  retained? : Bool = false,
) -> Int64? {
  if retained || (setup.output_file_bytes is Some(bytes) && bytes > 0L) {
    @compute.duckdb_stream_retention_capacity(setup.compute.limits)
  } else {
    @compute.duckdb_task_retention_capacity(setup.compute.limits)
  }
}

///|
pub fn configured_strategy_scratch_capacity(
  setup : StrategyComputeHostConfiguration,
  retained? : Bool = false,
) -> Int64? {
  if retained || (setup.output_file_bytes is Some(bytes) && bytes > 0L) {
    @compute.duckdb_stream_scratch_capacity(
      setup.compute.limits,
      setup.compute.transport,
      compute?=@connector.fixed_compute_choice_payload(
        setup.compute.choice,
        setup.compute.prepared,
      ),
    )
  } else {
    @compute.duckdb_task_scratch_capacity(
      setup.compute.limits,
      setup.compute.transport,
    )
  }
}
