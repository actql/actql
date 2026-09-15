///|
pub(all) suberror NodeHostFailure {
  Dispatch(@host.DispatchIssue)
  InvalidCommand
  Encoding(@encode.EncodeFailure)
}

///|
#export_name("strategyHostNext")
pub fn strategy_host_next(
  host : @host.StrategyHostDispatch,
) -> @host.TaskDispatch? raise NodeHostFailure {
  match @host.prepare_next_dispatch(host) {
    Ok(value) => value
    Err(issue) => raise Dispatch(issue)
  }
}

///|
#export_name("strategyHostTask")
pub fn strategy_host_task(task : @host.TaskDispatch) -> Int {
  @host.dispatch_task(task)
}

///|
#export_name("strategyHostRegistration")
pub fn strategy_host_registration(
  task : @host.TaskDispatch,
) -> @connector.CapabilityRegistration? {
  @host.dispatch_registration(task)
}

///|
#export_name("strategyHostLocalRegistration")
pub fn strategy_host_local_registration(
  host : @host.StrategyHostDispatch,
) -> @connector.CapabilityRegistration {
  @host.dispatch_local_registration(host)
}

///|
#export_name("strategyHostDuckdbRegistration")
pub fn strategy_host_duckdb_registration(
  host : @host.StrategyHostDispatch,
) -> @connector.CapabilityRegistration {
  @host.dispatch_duckdb_registration(host)
}

///|
#export_name("strategyHostTaskCompleted")
pub fn strategy_host_task_completed(
  host : @host.StrategyHostDispatch,
  task : Int,
) -> Bool {
  @strategy.captured_task_completed(@host.dispatch_run(host), task)
}

///|
#export_name("strategyHostResident")
pub fn strategy_host_resident(task : @host.TaskDispatch) -> Bool {
  @host.dispatch_is_resident(task)
}

///|
#export_name("strategyHostRun")
pub fn strategy_host_run(
  host : @host.StrategyHostDispatch,
) -> @strategy.CapturedDAG {
  @host.dispatch_run(host)
}

///|
#export_name("strategyHostResourceBinding")
pub fn strategy_host_resource_binding(
  task : @host.TaskDispatch,
) -> @connector.ResourceBinding? {
  @host.dispatch_resource_binding(task)
}

///|
#export_name("strategyHostResidentInputs")
pub fn strategy_host_resident_inputs(
  host : @host.StrategyHostDispatch,
  task : Int,
) -> Array[Array[Int64]] raise NodeHostFailure {
  guard @host.dispatch_resident_inputs(host, task) is Some(inputs) else {
    raise InvalidCommand
  }
  inputs.map(input => {
    let (producer, bytes, entries, names) = input
    [producer.to_int64(), bytes, entries.to_int64(), names.to_int64()]
  })
}

///|
#export_name("strategyHostTakeNative")
pub fn strategy_host_take_native(
  task : @host.TaskDispatch,
) -> @duckdb_driver.StrategyComputeHostConfiguration raise NodeHostFailure {
  match @host.take_native_dispatch(task) {
    Ok(value) => value
    Err(issue) => raise Dispatch(issue)
  }
}

///|
#export_name("strategyHostExecuteLocal")
pub fn strategy_host_execute_local(
  task : @host.TaskDispatch,
) -> Unit raise NodeHostFailure {
  match @host.execute_synchronous_dispatch(task) {
    Ok(_) => ()
    Err(issue) => raise Dispatch(issue)
  }
}

///|
#export_name("strategyHostCount")
pub fn strategy_host_count(host : @host.StrategyHostDispatch) -> Int {
  @strategy.graph_task_count(
    @strategy.captured_dag_graph(@host.dispatch_run(host)),
  )
}

///|
#export_name("strategyHostFinished")
pub fn strategy_host_finished(host : @host.StrategyHostDispatch) -> Bool {
  let run = @host.dispatch_run(host)
  for task in 1..<strategy_host_count(host) {
    if !@strategy.captured_task_completed(run, task) {
      return false
    }
  }
  true
}

///|
#export_name("strategyHostStop")
pub fn strategy_host_stop(host : @host.StrategyHostDispatch) -> Unit {
  @host.stop_strategy_dispatch(host)
}

///|
#export_name("strategyHostCloseOutputs")
pub fn strategy_host_close_outputs(host : @host.StrategyHostDispatch) -> Unit {
  let run = @host.dispatch_run(host)
  for task = strategy_host_count(host) - 1; task > 0; task = task - 1 {
    @strategy.close_captured_task_output(run, task)
  }
}

///|
#export_name("strategyHostOutput")
pub fn strategy_host_output(
  host : @host.StrategyHostDispatch,
  task : Int,
) -> @execution.CompletedOutput? {
  let run = @host.dispatch_run(host)
  @strategy.captured_task_target(run, task).bind(target => {
    @strategy.captured_task_output(run, task, target)
  })
}

///|
#export_name("strategyHostExplain")
pub fn strategy_host_explain(
  host : @host.StrategyHostDispatch,
  max_bytes : Int,
  max_nodes : Int,
) -> String raise NodeHostFailure {
  match
    @strategy.explain_captured_strategy(
      @host.dispatch_run(host),
      max_bytes,
      max_nodes,
      excluded=@host.dispatch_excluded_realizations(host),
    ) {
    Ok(value) => value
    Err(issue) => raise Encoding(issue)
  }
}

///|
#export_name("strategyHostUsage")
pub fn strategy_host_usage(host : @host.StrategyHostDispatch) -> Array[Int64] {
  let usage = @resources.ledger_usage(
    @strategy.captured_dag_ledger(@host.dispatch_run(host)),
  )
  [
    usage.planning_work.to_int64(),
    usage.attempts.to_int64(),
    usage.holdings.to_int64(),
    usage.transferred_bytes,
    usage.reserved_transfer_bytes,
    usage.held_bytes,
    usage.reserved_retention_bytes,
    usage.reserved_execution_bytes,
  ]
}
