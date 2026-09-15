///|
/// Connector-owned sequence installation and typed dispatch channel. The common
/// Host transports only registration-bound work; it never unwraps Local state.
struct LocalDispatchModule {
  run : @strategy.CapturedDAG
  registration : @connector.CapabilityRegistration
  implementation : @local.LocalComputeModule
  channel : @host.DispatchChannel[@connector.SynchronousCompute]
  mut estimate_configuration : LocalEstimateConfiguration?
}

///|
pub(all) enum LocalDispatchIssue {
  Configuration(@connector.FixedComputeIssue)
  Preparation(@local.LocalModuleIssue)
  Dispatch(@host.DispatchIssue)
  Execution(@strategy.RunIssue)
  Search(@strategy.SearchIssue)
}

///|
pub fn prepare_local_dispatch_module(
  driver : @host.DispatchDriver,
  registry : @connector.CapabilityRegistry,
  registration : @connector.CapabilityRegistration,
  sequences : Array[@execution.GeneratedSequence],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_work : Int,
) -> Result[LocalDispatchModule, LocalDispatchIssue] {
  let run = @host.dispatch_driver_run(driver)
  let graph = @strategy.captured_dag_graph(run)
  if sequences.length() != @strategy.graph_task_count(graph) - 1 {
    return Err(Configuration(ForeignPreparation))
  }
  for index, sequence in sequences {
    if !(@strategy.graph_task_owner(graph, index + 1) is Some(owner) &&
      physical_equal(owner, @execution.generated_sequence_owner(sequence))) {
      return Err(Configuration(ForeignPreparation))
    }
  }
  let implementation = match
    @local.prepare_local_compute_module(
      registry,
      registration,
      sequences,
      execution,
      measurement,
      max_work,
      sequences.length(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Configuration(issue))
  }
  let channel = match
    @host.open_dispatch_channel(driver, registry, registration) {
    Ok(value) => value
    Err(issue) => return Err(Dispatch(issue))
  }
  Ok({
    run,
    registration,
    implementation,
    channel,
    estimate_configuration: None,
  })
}

///|
/// The connector owns its work inventory and capacity formula. Common planning
/// only collects the resulting owned offer and composes its declared work.
pub fn estimate_local_dispatch_offer(
  installed : LocalDispatchModule,
  task : Int,
  lines : Array[@cost.SerialEstimateLine],
  max_work : Int,
) -> Result[@strategy.TaskOffer, LocalDispatchIssue] {
  if local_dispatch_rejection(installed, task) is Some(_) {
    return Err(Configuration(ComputeUnsupported))
  }
  guard @local.local_module_capacity(installed.implementation, task - 1)
    is Some(capacity) else {
    return Err(Configuration(InvalidLimits))
  }
  @strategy.prepare_task_offer(
    installed.run,
    task,
    installed.registration,
    local_dispatch_work_slots(),
    lines,
    {
      transfer_bytes: 0L,
      retained_bytes: capacity.retained_bytes,
      execution_bytes: capacity.execution_bytes,
    },
    max_work,
  ).map_err(issue => Search(issue))
}

///|
/// Work inventory owned by this realization, not by the Host's rate policy.
pub fn local_dispatch_work_slots() -> Int {
  5
}

///|
pub fn prepare_local_dispatch(
  installed : LocalDispatchModule,
  task : Int,
  revision : @strategy.StrategyRevision,
  request : @connector.FixedComputeRequest,
) -> Result[@host.DispatchWork, LocalDispatchIssue] {
  if local_dispatch_rejection(installed, task) is Some(_) {
    return Err(Configuration(ComputeUnsupported))
  }
  let compute = match
    @local.prepare_local_module_compute(
      installed.implementation,
      task - 1,
      request,
      @strategy.captured_task_join_output_at(installed.run, task, 0),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  @host.stage_dispatch_work(installed.channel, task, revision, request, compute).map_err(issue => {
      Dispatch(issue)
    },
  )
}

///|
pub fn[C, E] execute_local_dispatch(
  installed : LocalDispatchModule,
  host : @host.DispatchHost[C, E],
  task : @host.PreparedTaskDispatch,
) -> Result[Unit, LocalDispatchIssue] {
  let compute = match @host.take_installed_task(host, task, installed.channel) {
    Ok(value) => value
    Err(issue) => return Err(Dispatch(issue))
  }
  @strategy.execute_captured_synchronous_task(
    installed.run,
    @host.prepared_task_index(task),
    compute,
  ).map_err(issue => Execution(issue))
}
