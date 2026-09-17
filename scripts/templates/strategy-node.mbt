///|
pub(all) suberror NodeHostFailure {
  Diagnostics(@host_driver.ComputeDiagnosticsIssue)
  Dispatch(@host_driver.ComputeHostIssue[@strategy.RunIssue])
  Execution(@strategy.RunIssue)
  InvalidCommand
  Encoding(@encode.EncodeFailure)
}

///|
#export_name("strategyHostNext")
pub fn strategy_host_next(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> @host_driver.PreparedTaskDispatch? raise NodeHostFailure {
  match @host_driver.prepare_next_compute_task(@builtin.configured_host_runtime(host), ()) {
    Ok(value) => value
    Err(issue) => raise Dispatch(issue)
  }
}

///|
/// Producer indexes needed by the next managed task in exact input-port order.
/// This exposes topology only; opaque completions are checked by preparation.
#export_name("strategyHostManagedProducers")
pub fn strategy_host_managed_producers(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Array[Int] {
  @strategy.captured_next_managed_producers(
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
  )
}

///|
/// Compatibility accessor for installed unary implementations.
#export_name("strategyHostManagedProducer")
pub fn strategy_host_managed_producer(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Int {
  @strategy.captured_next_managed_producer(
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
  ).unwrap_or(-1)
}

///|
#export_name("strategyHostReleasableManagedProducers")
pub fn strategy_host_releasable_managed_producers(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Array[Int] {
  @strategy.captured_releasable_managed_producers(
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
  )
}

///|
#export_name("strategyHostNextTask")
pub fn strategy_host_next_task(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Int {
  @strategy.next_captured_task(
    @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
  ).unwrap_or(-1)
}

///|
#export_name("strategyHostManagedOutputMatches")
pub fn strategy_host_managed_output_matches(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  task : Int,
  output : @execution.ManagedCompletedOutput[Int],
) -> Bool {
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(host),
  )
  guard @strategy.captured_task_target(run, task) is Some(target) else {
    return false
  }
  @strategy.captured_managed_task_output_matches(run, task, target, output)
}

///|
#export_name("strategyHostModules")
pub fn strategy_host_modules(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Array[String] {
  @builtin.configured_compute_module_keys(@builtin.configured_host_modules(host))
}

///|
#export_name("strategyHostTask")
pub fn strategy_host_task(task : @host_driver.PreparedTaskDispatch) -> Int {
  @host_driver.prepared_task_index(task)
}

///|
#export_name("strategyHostRegistration")
pub fn strategy_host_registration(
  task : @host_driver.PreparedTaskDispatch,
) -> @connector.CapabilityRegistration? {
  Some(@host_driver.prepared_task_registration(task))
}



///|
#export_name("strategyHostTaskCompleted")
pub fn strategy_host_task_completed(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  task : Int,
) -> Bool {
  @strategy.captured_task_completed(@host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)), task)
}

///|
#export_name("strategyHostResident")
pub fn strategy_host_resident(task : @host_driver.PreparedTaskDispatch) -> Bool {
  strategy_host_resource_binding(task) is Some(_)
}

///|
#export_name("strategyHostRun")
pub fn strategy_host_run(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> @strategy.CapturedDAG {
  @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host))
}

///|
#export_name("strategyHostResourceBinding")
pub fn strategy_host_resource_binding(
  task : @host_driver.PreparedTaskDispatch,
) -> @connector.ResourceBinding? {
  @strategy.strategy_resident_profile(@host_driver.prepared_task_revision(task), @host_driver.prepared_task_index(task)).map(@strategy.resident_profile_resource_binding)
}

///|
#export_name("strategyHostResidentInputs")
pub fn strategy_host_resident_inputs(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  task : Int,
) -> Array[Array[Int64]] raise NodeHostFailure {
  guard @host_driver.compute_host_resident_inputs(@builtin.configured_host_runtime(host), task) is Some(inputs) else {
    raise InvalidCommand
  }
  inputs.map(input => {
    let (producer, bytes, entries, names) = input
    [producer.to_int64(), bytes, entries.to_int64(), names.to_int64()]
  })
}



///|
#export_name("strategyHostCount")
pub fn strategy_host_count(host : @builtin.ConfiguredComputeHost[@strategy.RunIssue]) -> Int {
  @strategy.graph_task_count(
    @strategy.captured_dag_graph(@host_driver.dispatch_driver_run(@builtin.configured_host_driver(host))),
  )
}

///|
#export_name("strategyHostFinished")
pub fn strategy_host_finished(host : @builtin.ConfiguredComputeHost[@strategy.RunIssue]) -> Bool {
  let run = @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host))
  for task in 1..<strategy_host_count(host) {
    if !@strategy.captured_task_completed(run, task) {
      return false
    }
  }
  true
}

///|
#export_name("strategyHostStop")
pub fn strategy_host_stop(host : @builtin.ConfiguredComputeHost[@strategy.RunIssue]) -> Unit {
  @host_driver.stop_dispatch_driver(@builtin.configured_host_driver(host))
}

///|
#export_name("strategyHostCloseOutputs")
pub fn strategy_host_close_outputs(host : @builtin.ConfiguredComputeHost[@strategy.RunIssue]) -> Unit {
  let run = @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host))
  for task = strategy_host_count(host) - 1; task > 0; task = task - 1 {
    @strategy.close_captured_task_output(run, task)
  }
}

///|
#export_name("strategyHostOutput")
pub fn strategy_host_output(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  task : Int,
) -> @execution.CompletedOutput? {
  let run = @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host))
  @strategy.captured_task_target(run, task).bind(target => {
    @strategy.captured_task_output(run, task, target)
  })
}

///|
#export_name("strategyHostExplain")
pub fn strategy_host_explain(
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  max_bytes : Int,
  max_nodes : Int,
) -> String raise NodeHostFailure {
  let excluded = match @host_driver.compute_host_exclusions(@builtin.configured_host_runtime(host), max_nodes) {
    Ok(value) => value
    Err(issue) => raise Diagnostics(issue)
  }
  match
    @strategy.explain_captured_strategy(
      @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
      max_bytes,
      max_nodes,
      excluded~,
    ) {
    Ok(value) => value
    Err(issue) => raise Encoding(issue)
  }
}

///|
#export_name("strategyHostUsage")
pub fn strategy_host_usage(host : @builtin.ConfiguredComputeHost[@strategy.RunIssue]) -> Array[Int64] {
  let usage = @resources.ledger_usage(
    @strategy.captured_dag_ledger(@host_driver.dispatch_driver_run(@builtin.configured_host_driver(host))),
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
