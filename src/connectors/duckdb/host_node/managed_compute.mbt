///|
/// Installed Node Host state for a selected managed DuckDB task. The receipt
/// slot is private transport evidence: only this task's actual output finisher
/// can populate it.
struct ManagedComputeNodeRun {
  task : @duckdb_driver.CapturedManagedDuckDBTask[Int]
  transport : @duckdb.TransportColumnLimits
  limits : @duckdb_compute.DuckDBComputeLimits
  output_file_bytes : Int64
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
    @duckdb.fixed_query_sql(@duckdb.managed_fixed_query_query(query))
  }
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
  @duckdb.managed_fixed_query_numeric_file_sql(
    @duckdb_driver.captured_managed_duckdb_query(run.task),
    max_sql_bytes,
  )
}

///|
#export_name("managedStrategyParameterCount")
pub fn managed_strategy_parameter_count(run : ManagedComputeNodeRun) -> Int {
  if run.closed {
    return 0
  }
  @duckdb.fixed_query_parameter_count(
    @duckdb.managed_fixed_query_query(
      @duckdb_driver.captured_managed_duckdb_query(run.task),
    ),
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
  guard @duckdb.fixed_query_parameter(
      @duckdb.managed_fixed_query_query(
        @duckdb_driver.captured_managed_duckdb_query(run.task),
      ),
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
  if run.closed {
    raise InvalidCommand
  }
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
      managed_inputs=[@duckdb_driver.captured_managed_duckdb_input(run.task)],
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
