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
  auxiliary_retention_bytes? : Int64,
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
    auxiliary_retention_bytes?,
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

///|
/// Bounded cell ceiling for the first standard task when it publishes a
/// managed output. It derives from the selected request and checked schema.
pub fn configured_strategy_managed_index_cells(
  setup : StrategyComputeHostConfiguration,
) -> Int? {
  let c = setup.compute
  guard @connector.fixed_compute_choice_payload(c.choice, c.prepared)
    is Some(compute) else {
    return None
  }
  let request = @connector.fixed_compute_candidate_request(
    @connector.prepared_compute_candidate(c.prepared),
  )
  let mut rows = @connector.fixed_compute_request_capacity(request).max_rows
  if @duckdb.fixed_compute_join_output_ceiling(compute) is Some(ceiling) &&
    ceiling < rows {
    rows = ceiling
  }
  let width = @duckdb.fixed_compute_output_column_count(compute)
  if rows < 0 || width < 0 || (width > 0 && rows > 2147483647 / width) {
    None
  } else {
    Some(rows * width)
  }
}

///|
/// Trusted application preparation for one selected managed task. The exact
/// request, query payload and completion owner are already fixed; configuration
/// performs no Store access or native I/O.
struct ManagedStrategyComputeHostConfiguration[T] {
  graph : @strategy.CapturedDAG
  task : Int
  choice : @connector.ManagedFixedComputeChoice[T]
  prepared : @connector.PreparedManagedCompute[T, @duckdb.ManagedFixedQuery[T]]
  generated : @execution.CompletionPreparation
  profile : @execution.ManagedExecutionProfile
  limits : @compute.DuckDBComputeLimits
  transport : @duckdb.TransportColumnLimits
  output_file_bytes : Int64
  max_index_cells : Int
}

///|
pub fn[T] configure_managed_strategy_compute_host(
  graph : @strategy.CapturedDAG,
  task : Int,
  choice : @connector.ManagedFixedComputeChoice[T],
  prepared : @connector.PreparedManagedCompute[T, @duckdb.ManagedFixedQuery[T]],
  generated : @execution.CompletionPreparation,
  profile : @execution.ManagedExecutionProfile,
  limits : @compute.DuckDBComputeLimits,
  transport : @duckdb.TransportColumnLimits,
  output_file_bytes : Int64,
  max_index_cells : Int,
) -> Result[ManagedStrategyComputeHostConfiguration[T], @strategy.RunIssue] {
  if output_file_bytes < 0L ||
    max_index_cells < 0 ||
    @execution.managed_row_measurement_capacity_bytes(max_index_cells) is None {
    return Err(Physical(InvalidLimits))
  }
  Ok({
    graph,
    task,
    choice,
    prepared,
    generated,
    profile,
    limits,
    transport,
    output_file_bytes,
    max_index_cells,
  })
}

///|
pub fn[T] configured_managed_strategy_retention_capacity(
  setup : ManagedStrategyComputeHostConfiguration[T],
) -> Int64? {
  guard @compute.duckdb_stream_retention_capacity(setup.limits) is Some(base) &&
    @execution.managed_row_measurement_capacity_bytes(setup.max_index_cells)
    is Some(index) &&
    base <= 9223372036854775807L - setup.output_file_bytes &&
    base + setup.output_file_bytes <= 9223372036854775807L - index else {
    return None
  }
  Some(base + setup.output_file_bytes + index)
}

///|
pub fn[T] configured_managed_strategy_scratch_capacity(
  setup : ManagedStrategyComputeHostConfiguration[T],
) -> Int64? {
  @compute.duckdb_managed_stream_scratch_capacity(setup.limits, setup.transport)
}

///|
pub fn[T] configured_managed_strategy_transport(
  setup : ManagedStrategyComputeHostConfiguration[T],
) -> @duckdb.TransportColumnLimits {
  setup.transport
}

///|
pub fn[T] configured_managed_strategy_limits(
  setup : ManagedStrategyComputeHostConfiguration[T],
) -> @compute.DuckDBComputeLimits {
  setup.limits
}

///|
pub fn[T] configured_managed_strategy_output_file_bytes(
  setup : ManagedStrategyComputeHostConfiguration[T],
) -> Int64 {
  setup.output_file_bytes
}

///|
pub fn[T] configured_managed_strategy_max_index_cells(
  setup : ManagedStrategyComputeHostConfiguration[T],
) -> Int {
  setup.max_index_cells
}

///|
pub fn[T] start_configured_managed_strategy_compute_host(
  setup : ManagedStrategyComputeHostConfiguration[T],
  transfer_bytes : Int64,
  native_execution_bytes : Int64,
  authorize : () -> Bool,
  transport_matches : (@execution.ManagedOutputValueReceipt) -> Bool,
  retention_released : () -> Bool,
) -> Result[CapturedManagedDuckDBTask[T], @strategy.RunIssue] {
  guard configured_managed_strategy_retention_capacity(setup) is Some(retention) &&
    configured_managed_strategy_scratch_capacity(setup) is Some(scratch) &&
    transfer_bytes >= 0L &&
    native_execution_bytes >= 0L &&
    native_execution_bytes <= 9223372036854775807L - scratch else {
    return Err(Physical(InvalidLimits))
  }
  start_captured_managed_duckdb_task(
    setup.graph,
    setup.task,
    setup.choice,
    setup.prepared,
    setup.generated,
    setup.profile,
    setup.limits,
    {
      transfer_bytes,
      retained_bytes: retention,
      scratch_bytes: scratch,
      execution_bytes: native_execution_bytes + scratch,
    },
    [],
    authorize,
    transport_matches,
    retention_released,
  )
}
