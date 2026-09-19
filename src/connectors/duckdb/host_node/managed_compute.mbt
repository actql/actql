///|
/// Installed Node Host state for a selected managed DuckDB task. The receipt
/// slot is private transport evidence: only this task's actual output finisher
/// can populate it.
struct ManagedComputeNodeRun {
  task : @duckdb_driver.CapturedManagedDuckDBTask[Int]
  transport : @duckdb.TransportColumnLimits
  limits : @duckdb_compute.DuckDBComputeLimits
  output_file_bytes : Int64
  max_index_cells : Int
  receipt : Ref[@execution.ManagedOutputValueReceipt?]
  mut closed : Bool
}

///|
#export_name("managedStrategyRetentionCapacity")
pub fn managed_strategy_retention_capacity(
  setup : @duckdb_driver.ManagedStrategyComputeHostConfiguration[Int],
) -> Int64 raise NodeHostFailure {
  match @duckdb_driver.configured_managed_strategy_retention_capacity(setup) {
    Some(value) => value
    None => raise Physical(InvalidLimits)
  }
}

///|
#export_name("managedStrategyScratchCapacity")
pub fn managed_strategy_scratch_capacity(
  setup : @duckdb_driver.ManagedStrategyComputeHostConfiguration[Int],
) -> Int64 raise NodeHostFailure {
  match @duckdb_driver.configured_managed_strategy_scratch_capacity(setup) {
    Some(value) => value
    None => raise Physical(InvalidLimits)
  }
}

///|
/// Synchronous registration only. Native work and Store reads start after this
/// returns, so preparation failure has no external cleanup ambiguity.
#export_name("managedStrategyHostOpen")
pub fn managed_strategy_host_open(
  setup : @duckdb_driver.ManagedStrategyComputeHostConfiguration[Int],
  transfer_bytes : Int64,
  execution_bytes : Int64,
  authorize : () -> Bool,
  retention_released : () -> Bool,
) -> ManagedComputeNodeRun raise NodeHostFailure {
  let receipt : Ref[@execution.ManagedOutputValueReceipt?] = Ref(None)
  let task = match
    @duckdb_driver.start_configured_managed_strategy_compute_host(
      setup,
      transfer_bytes,
      execution_bytes,
      authorize,
      fn(actual) {
        receipt.val is Some(expected) && physical_equal(actual, expected)
      },
      retention_released,
    ) {
    Ok(value) => value
    Err(issue) => raise Strategy(issue)
  }
  {
    task,
    transport: @duckdb_driver.configured_managed_strategy_transport(setup),
    limits: @duckdb_driver.configured_managed_strategy_limits(setup),
    output_file_bytes: @duckdb_driver.configured_managed_strategy_output_file_bytes(
      setup,
    ),
    max_index_cells: @duckdb_driver.configured_managed_strategy_max_index_cells(
      setup,
    ),
    receipt,
    closed: false,
  }
}

///|
#export_name("managedStrategyInput")
pub fn managed_strategy_input(
  run : ManagedComputeNodeRun,
) -> @execution.ManagedProducerRead[Int] raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  @duckdb_driver.captured_managed_duckdb_input(run.task)
}

///|
#export_name("managedStrategyInputCount")
pub fn managed_strategy_input_count(run : ManagedComputeNodeRun) -> Int {
  if run.closed {
    0
  } else {
    @duckdb_driver.captured_managed_duckdb_input_count(run.task)
  }
}

///|
#export_name("managedStrategyInputAt")
pub fn managed_strategy_input_at(
  run : ManagedComputeNodeRun,
  index : Int,
) -> @execution.ManagedProducerRead[Int] raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  match @duckdb_driver.captured_managed_duckdb_input_at(run.task, index) {
    Some(input) => input
    None => raise InvalidCommand
  }
}

///|
#export_name("managedStrategySql")
pub fn managed_strategy_sql(
  run : ManagedComputeNodeRun,
  create : Bool,
) -> String raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  let query = @duckdb_driver.captured_managed_duckdb_query(run.task)
  if create {
    @duckdb.managed_fixed_query_create_sql(query)
  } else {
    @duckdb.managed_fixed_query_sql(query)
  }
}

///|
#export_name("managedStrategyCreateSql")
pub fn managed_strategy_create_sql(
  run : ManagedComputeNodeRun,
  index : Int,
) -> String raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  match
    @duckdb.managed_fixed_query_create_sql_at(
      @duckdb_driver.captured_managed_duckdb_query(run.task),
      index,
    ) {
    Some(sql) => sql
    None => raise InvalidCommand
  }
}

///|
/// Checked query with a private input-occurrence column. Unsupported shapes
/// return None and continue through the ordinary output validation path.
#export_name("managedStrategyOccurrenceSql")
pub fn managed_strategy_occurrence_sql(run : ManagedComputeNodeRun) -> String? {
  if run.closed {
    return None
  }
  @duckdb.managed_fixed_query_occurrence_sql(
    @duckdb_driver.captured_managed_duckdb_query(run.task),
  )
}

///|
#export_name("managedStrategySelection")
pub fn managed_strategy_selection(
  run : ManagedComputeNodeRun,
  rows : Array[Int],
) -> @execution.ManagedViewSelection[Int] raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  match
    @duckdb.prepare_managed_fixed_query_selection(
      @duckdb_driver.captured_managed_duckdb_query(run.task),
      rows,
      run.max_index_cells,
      // This pass copies bounded per-value measurements and row occurrences;
      // schema-only metadata_work is not its contract or a row-count ceiling.
      run.limits.values.max_work,
    ) {
    Ok(selection) => selection
    Err(_) => raise InvalidCommand
  }
}

///|
/// Exact positional storage order for the selected task's output schema. This
/// performs bounded metadata matching only and does not claim the output.
#export_name("managedStrategyStorageOrder")
pub fn managed_strategy_storage_order(
  run : ManagedComputeNodeRun,
  fields : String,
) -> Array[Int] raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  match
    @duckdb.prepare_managed_output_storage_order(
      @duckdb_compute.managed_input_duckdb_output_values(
        @duckdb_driver.captured_managed_duckdb_completion(run.task),
      ),
      transport_fields(run.transport, fields),
      run.limits.physical,
      run.limits.metadata_work,
    ) {
    Ok(order) => order
    Err(issue) => raise ManagedValues(issue)
  }
}

///|
/// Install the selected-view receipt only after native settlement. The copied
/// measurement index receives an exact holding from this task's existing
/// reservation; file retention remains a separate allocation.
#export_name("managedStrategySelectedOutputBegin")
pub fn managed_strategy_selected_output_begin(
  run : ManagedComputeNodeRun,
  selection : @execution.ManagedViewSelection[Int],
) -> ManagedNodeOutput raise NodeHostFailure {
  if run.closed ||
    !@duckdb_driver.captured_managed_duckdb_native_verified(run.task) {
    raise InvalidCommand
  }
  let cells = @execution.managed_view_selection_cells(selection)
  guard cells <= run.max_index_cells &&
    @execution.managed_row_measurement_capacity_bytes(cells) is Some(bytes) else {
    raise InvalidCommand
  }
  let output = managed_selected_output_open(
    @duckdb_compute.managed_input_duckdb_output_values(
      @duckdb_driver.captured_managed_duckdb_completion(run.task),
    ),
    selection,
    run.transport,
    fn() { @duckdb_driver.captured_managed_duckdb_native_verified(run.task) },
  )
  errdefer managed_output_cancel(output)
  let allocation = match
    @strategy.retain_task_execution_allocation(
      @duckdb_driver.captured_managed_duckdb_run(run.task),
      @duckdb_driver.captured_managed_duckdb_execution(run.task),
      bytes,
    ) {
    Ok(value) => value
    Err(issue) => raise Physical(issue)
  }
  output.index_allocation = Some(allocation)
  output.strategy_allocation = Some(
    (
      @duckdb_driver.captured_managed_duckdb_run(run.task),
      @duckdb_driver.captured_managed_duckdb_execution(run.task),
      run.output_file_bytes,
    ),
  )
  output
}

///|
#export_name("managedStrategyInputFileSql")
pub fn managed_strategy_input_file_sql(
  run : ManagedComputeNodeRun,
  max_sql_bytes : Int,
) -> String? {
  if run.closed {
    return None
  }
  @duckdb.managed_fixed_query_column_file_sql(
    @duckdb_driver.captured_managed_duckdb_query(run.task),
    max_sql_bytes,
  )
}

///|
#export_name("managedStrategyInputFileSqlAt")
pub fn managed_strategy_input_file_sql_at(
  run : ManagedComputeNodeRun,
  input_index : Int,
  max_sql_bytes : Int,
) -> String? {
  if run.closed {
    return None
  }
  @duckdb.managed_fixed_query_column_file_sql_at(
    @duckdb_driver.captured_managed_duckdb_query(run.task),
    input_index,
    max_sql_bytes,
  )
}

///|
#export_name("managedStrategyInputFileViewSqlAt")
pub fn managed_strategy_input_file_view_sql_at(
  run : ManagedComputeNodeRun,
  input_index : Int,
  max_sql_bytes : Int,
) -> String? {
  if run.closed {
    return None
  }
  @duckdb.managed_fixed_query_column_file_view_sql_at(
    @duckdb_driver.captured_managed_duckdb_query(run.task),
    input_index,
    max_sql_bytes,
  )
}

///|
#export_name("managedStrategyInputParquetSql")
pub fn managed_strategy_input_parquet_sql(
  run : ManagedComputeNodeRun,
  max_sql_bytes : Int,
) -> String? {
  if run.closed {
    return None
  }
  @duckdb.managed_fixed_query_parquet_file_sql(
    @duckdb_driver.captured_managed_duckdb_query(run.task),
    max_sql_bytes,
  )
}

///|
#export_name("managedStrategyInputParquetSqlAt")
pub fn managed_strategy_input_parquet_sql_at(
  run : ManagedComputeNodeRun,
  input_index : Int,
  max_sql_bytes : Int,
) -> String? {
  if run.closed {
    return None
  }
  @duckdb.managed_fixed_query_parquet_file_sql_at(
    @duckdb_driver.captured_managed_duckdb_query(run.task),
    input_index,
    max_sql_bytes,
  )
}

///|
#export_name("managedStrategyInputParquetViewSqlAt")
pub fn managed_strategy_input_parquet_view_sql_at(
  run : ManagedComputeNodeRun,
  input_index : Int,
  max_sql_bytes : Int,
) -> String? {
  if run.closed {
    return None
  }
  @duckdb.managed_fixed_query_parquet_file_view_sql_at(
    @duckdb_driver.captured_managed_duckdb_query(run.task),
    input_index,
    max_sql_bytes,
  )
}

///|
#export_name("managedStrategyParameterCount")
pub fn managed_strategy_parameter_count(run : ManagedComputeNodeRun) -> Int {
  if run.closed {
    return 0
  }
  @duckdb.managed_fixed_query_parameter_count(
    @duckdb_driver.captured_managed_duckdb_query(run.task),
  )
}

///|
#export_name("managedStrategyParameter")
pub fn managed_strategy_parameter(
  run : ManagedComputeNodeRun,
  index : Int,
) -> String raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  guard @duckdb.managed_fixed_query_parameter(
      @duckdb_driver.captured_managed_duckdb_query(run.task),
      index,
    )
    is Some(parameter) else {
    raise InvalidCommand
  }
  try {
    let writer = @encode.writer(
      run.transport.max_bytes,
      run.transport.max_nodes,
      4,
    )
    @duckdb.emit_physical_parameter(parameter, writer)
    @encode.finish(writer)
  } catch {
    issue => raise Encoding(issue)
  }
}

///|
#export_name("managedStrategyOutputFileCapacity")
pub fn managed_strategy_output_file_capacity(
  run : ManagedComputeNodeRun,
) -> Int64 {
  if run.closed {
    0L
  } else {
    run.output_file_bytes
  }
}

///|
#export_name("managedStrategyCharge")
pub fn managed_strategy_charge(
  run : ManagedComputeNodeRun,
  bytes : Int64,
) -> Unit raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  match
    @strategy.charge_task_execution_transfer(
      @duckdb_driver.captured_managed_duckdb_run(run.task),
      @duckdb_driver.captured_managed_duckdb_execution(run.task),
      bytes,
    ) {
    Ok(_) => ()
    Err(issue) => raise Physical(issue)
  }
}

///|
/// Begin the exact output receiver owned by this task. The common reservation
/// already includes its bounded physical file and optional measurement index.
#export_name("managedStrategyOutputBegin")
pub fn managed_strategy_output_begin(
  run : ManagedComputeNodeRun,
  fields : String,
) -> ManagedNodeOutput raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  let output = managed_output_open(
    @duckdb_compute.managed_input_duckdb_output_values(
      @duckdb_driver.captured_managed_duckdb_completion(run.task),
    ),
    fields,
    run.limits.physical,
    run.transport,
    run.limits.metadata_work,
  )
  errdefer managed_output_cancel(output)
  if run.max_index_cells > 0 {
    guard @execution.managed_row_measurement_capacity_bytes(run.max_index_cells)
      is Some(bytes) else {
      raise InvalidCommand
    }
    match
      @execution.enable_managed_row_measurements(
        @duckdb_compute.managed_input_duckdb_output_values(
          @duckdb_driver.captured_managed_duckdb_completion(run.task),
        ),
        run.max_index_cells,
      ) {
      Ok(_) => ()
      Err(issue) => raise ManagedValues(Values(issue))
    }
    let allocation = match
      @strategy.retain_task_execution_allocation(
        @duckdb_driver.captured_managed_duckdb_run(run.task),
        @duckdb_driver.captured_managed_duckdb_execution(run.task),
        bytes,
      ) {
      Ok(value) => value
      Err(issue) => raise Physical(issue)
    }
    output.index_allocation = Some(allocation)
  }
  output.strategy_allocation = Some(
    (
      @duckdb_driver.captured_managed_duckdb_run(run.task),
      @duckdb_driver.captured_managed_duckdb_execution(run.task),
      run.output_file_bytes,
    ),
  )
  output
}

///|
#export_name("managedStrategyOutputFinish")
pub fn managed_strategy_output_finish(
  run : ManagedComputeNodeRun,
  output : ManagedNodeOutput,
) -> Unit raise NodeHostFailure {
  guard !run.closed &&
    output.strategy_allocation is Some((graph, execution, _)) &&
    physical_equal(graph, @duckdb_driver.captured_managed_duckdb_run(run.task)) &&
    physical_equal(
      execution,
      @duckdb_driver.captured_managed_duckdb_execution(run.task),
    ) else {
    raise InvalidCommand
  }
  managed_output_finish(output)
  guard output.receipt is Some(receipt) else { raise InvalidCommand }
  run.receipt.val = Some(receipt)
}

///|
#export_name("managedStrategySettle")
pub fn managed_strategy_settle(
  run : ManagedComputeNodeRun,
  confirmed : Bool,
) -> Unit raise NodeHostFailure {
  // Cancellation may close logical use before the native session reports its
  // actual stop. This exact task must still be able to settle its physical
  // reservation afterward; every execution/output operation remains closed.
  match
    @duckdb_driver.settle_captured_managed_duckdb_task(run.task, confirmed) {
    Ok(_) => ()
    Err(issue) => raise Physical(issue)
  }
}

///|
#export_name("managedStrategyComplete")
pub fn managed_strategy_complete(
  run : ManagedComputeNodeRun,
  output : ManagedNodeOutput,
) -> @execution.ManagedCompletedOutput[Int] raise NodeHostFailure {
  guard !run.closed &&
    output.receipt is Some(receipt) &&
    run.receipt.val is Some(expected) &&
    physical_equal(receipt, expected) &&
    output.material is Some(_) else {
    raise InvalidCommand
  }
  let completed = managed_output_complete_input(
    output,
    @duckdb_driver.captured_managed_duckdb_completion(run.task),
  )
  let graph = @duckdb_driver.captured_managed_duckdb_run(run.task)
  match
    @strategy.complete_managed_task_execution(
      graph,
      @duckdb_driver.captured_managed_duckdb_execution(run.task),
      completed,
      allocation?=output.material_allocation,
      managed_inputs=@duckdb_driver.captured_managed_duckdb_inputs(run.task),
    ) {
    Err(issue) => {
      managed_output_cancel(output)
      @strategy.stop_captured_dag(graph)
      raise Strategy(issue)
    }
    Ok(_) => {
      output.material_allocation = None
      completed
    }
  }
}

///|
/// Exact logical comparison demand for this completed task. Direct count,
/// view, and join demand report zero scalar-comparison usage.
#export_name("managedStrategyComparisonUsage")
pub fn managed_strategy_comparison_usage(
  run : ManagedComputeNodeRun,
) -> Array[String] raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  guard @duckdb_compute.managed_input_duckdb_demand_usage(
      @duckdb_driver.captured_managed_duckdb_completion(run.task),
    )
    is Some(demand) else {
    raise InvalidCommand
  }
  guard demand is Comparison(usage) else {
    return ["0", "0", "-1", "0", "0", "0", "0", "0", "0", "0"]
  }
  [
    usage.rows.to_string(),
    usage.field_bytes.to_string(),
    usage.rhs_bytes.unwrap_or(-1).to_string(),
    usage.true_rows.to_string(),
    usage.false_rows.to_string(),
    usage.null_rows.to_string(),
    usage.predicate_bytes.to_string(),
    usage.physical_work.to_string(),
    usage.physical_bytes.to_string(),
    usage.physical_nodes.to_string(),
  ]
}

///|
#export_name("managedStrategyClose")
pub fn managed_strategy_close(run : ManagedComputeNodeRun) -> Unit {
  if run.closed {
    return
  }
  run.closed = true
  @duckdb_driver.close_captured_managed_duckdb_task(run.task)
}

///|
/// Poll the exact Store-release predicate after asynchronous physical cleanup.
/// Closing a task revokes logical use immediately, but its allocation cannot be
/// returned until the installed Store confirms that the body has disappeared.
#export_name("managedStrategyRefreshRetention")
pub fn managed_strategy_refresh_retention(run : ManagedComputeNodeRun) -> Unit {
  @strategy.refresh_captured_retention(
    @duckdb_driver.captured_managed_duckdb_run(run.task),
  )
}

///|
/// Confirm disposal of a failed managed task only after its native settlement
/// and installed retention-release predicate are both true. Merely rescanning
/// completed output retention cannot discharge this execution reservation.
#export_name("managedStrategyCleanupRefresh")
pub fn managed_strategy_cleanup_refresh(
  run : ManagedComputeNodeRun,
) -> Result[Bool, @resources.LedgerIssue] {
  @strategy.refresh_task_execution_cleanup(
    @duckdb_driver.captured_managed_duckdb_run(run.task),
    @duckdb_driver.captured_managed_duckdb_execution(run.task),
  )
}

///|
/// Portable DuckDB driver decision for one managed failure-cleanup step. The
/// Node adapter performs only the selected physical operation.
#export_name("managedStrategyFailureAction")
pub fn managed_strategy_failure_action(
  output_cancel_attempted : Bool,
  output_owners_close_attempted : Bool,
  output_reclaim_attempted : Bool,
  execution_close_attempted : Bool,
  native_stopped : Bool,
  execution_settled : Bool,
  execution_cleanup_confirmed : Bool,
  output_reclaimed : Bool,
) -> Int {
  @duckdb_driver.managed_duckdb_failure_step_code(
    output_cancel_attempted, output_owners_close_attempted, output_reclaim_attempted,
    execution_close_attempted, native_stopped, execution_settled, execution_cleanup_confirmed,
    output_reclaimed,
  )
}

///|
/// Portable retry ordering for independent native and Store cleanup owners.
#export_name("managedStrategyFailureRetryAction")
pub fn managed_strategy_failure_retry_action(
  native_pending : Bool,
  native_retry_attempted : Bool,
  output_pending : Bool,
  output_retry_attempted : Bool,
) -> Int {
  @duckdb_driver.managed_duckdb_failure_retry_step_code(
    native_pending, native_retry_attempted, output_pending, output_retry_attempted,
  )
}
