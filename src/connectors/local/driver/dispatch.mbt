///|
/// Connector-owned sequence installation and typed dispatch channel. The common
/// Host transports only registration-bound work; it never unwraps Local state.
struct LocalDispatchModule {
  run : @strategy.CapturedDAG
  registration : @connector.CapabilityRegistration
  implementation : @local.LocalComputeModule
  channel : @host.DispatchChannel[LocalDispatchPlan]
  mut estimate_configuration : LocalEstimateConfiguration?
  mut import_policy : (@local.LocalImportLimits, Int64?)?
  mut output_policy : (@local.LocalExportLimits, Int64?)?
  mut policy_sealed : Bool
}

///|
priv enum LocalDispatchPlan {
  Synchronous(@connector.SynchronousCompute)
  Materializing(
    @connector.PreparedExecution[
      @local.LocalMaterializingAttempt,
      @strategy.RunIssue,
    ],
    @local.LocalImportLimits,
    @local.LocalExportLimits?
  )
}

///|
pub(all) enum LocalDispatchIssue {
  Configuration(@connector.FixedComputeIssue)
  Preparation(@local.LocalModuleIssue)
  Dispatch(@host.DispatchIssue)
  Execution(@strategy.RunIssue)
  Search(@strategy.SearchIssue)
  ManagedValues(@execution.ManagedOutputValueIssue)
  ManagedCopy(@execution.ManagedIndependentOutputIssue)
  ManagedRetention(@execution.ManagedOutputRetentionIssue)
  ManagedCompletion(@execution.TrustedOutputIssue)
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
  managed_capacity? : @connector.FixedComputeCapacity,
  managed_providers? : Array[@local.ManagedProvider] = [],
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
      managed_capacity?,
      managed_providers~,
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
    import_policy: None,
    output_policy: None,
    policy_sealed: false,
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
  let mut transfer = 0L
  let mut retained = capacity.retained_bytes
  let offers = lines.copy()
  let mut slots = local_dispatch_work_slots()
  if installed.import_policy is Some((limits, milliseconds)) {
    guard @local.local_import_retention_capacity(limits) is Some(per_input) else {
      return Err(Configuration(InvalidLimits))
    }
    let graph = @strategy.captured_dag_graph(installed.run)
    let edges = @strategy.graph_data_count(graph)
    if edges > max_work {
      return Err(Configuration(InvalidLimits))
    }
    for edge in 0..<edges {
      if @strategy.graph_data_at(graph, edge).unwrap().consumer == task {
        if per_input > 9223372036854775807L - retained ||
          limits.wire.max_bytes.to_int64() > 9223372036854775807L - transfer {
          return Err(Configuration(InvalidLimits))
        }
        transfer += limits.wire.max_bytes.to_int64()
        retained += per_input
      }
    }
    offers.push({ work_slots: [slots], milliseconds, })
    slots += 1
  }
  if installed.output_policy is Some((limits, milliseconds)) {
    guard @local.local_export_retention_capacity(limits) is Some(extra) &&
      extra <= 9223372036854775807L - retained else {
      return Err(Configuration(InvalidLimits))
    }
    retained += extra
    offers.push({ work_slots: [slots], milliseconds, })
    slots += 1
  }
  let execution = if installed.import_policy is Some(_) ||
    installed.output_policy is Some(_) {
    if retained > 9223372036854775807L - capacity.execution_bytes {
      return Err(Configuration(InvalidLimits))
    }
    // Managed import may keep the admitted input representation and the
    // independent output allocation live together until completion commits.
    // Advertise that peak before selection; execution must never discover a
    // larger requirement than the selected envelope.
    capacity.execution_bytes + retained
  } else {
    capacity.execution_bytes
  }
  @strategy.prepare_task_offer(
    installed.run,
    task,
    installed.registration,
    slots,
    offers,
    {
      transfer_bytes: transfer,
      retained_bytes: retained,
      execution_bytes: execution,
    },
    max_work,
  )
  .map(offer => {
    installed.policy_sealed = true
    offer
  })
  .map_err(issue => Search(issue))
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
  guard local_task_join_output_ceilings(installed.run, task)
    is Some(join_output_ceilings) else {
    return Err(Configuration(InvalidLimits))
  }
  if installed.import_policy is Some((limits, _)) &&
    (
      installed.output_policy is Some(_) ||
      @connector.fixed_compute_request_inputs(request).any(input => {
        !@execution.producer_read_has_cell_access(input)
      })
    ) {
    let output_limits = installed.output_policy.map(value => value.0)
    let compute = match
      @local.prepare_local_module_materializing_compute(
        installed.implementation,
        task - 1,
        request,
        limits,
        _ => @strategy.RunIssue::Compute(InvalidLimits),
        None,
        output_limits~,
        join_output_ceilings~,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Preparation(issue))
    }
    return @host.stage_dispatch_work(
      installed.channel,
      task,
      revision,
      request,
      Materializing(compute, limits, output_limits),
    ).map_err(issue => Dispatch(issue))
  }
  let compute = match
    @local.prepare_local_module_compute(
      installed.implementation,
      task - 1,
      request,
      None,
      join_output_ceilings~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  @host.stage_dispatch_work(
    installed.channel,
    task,
    revision,
    request,
    Synchronous(compute),
  ).map_err(issue => Dispatch(issue))
}

///|
pub fn[C, E] execute_local_dispatch(
  installed : LocalDispatchModule,
  host : @host.DispatchHost[C, E],
  task : @host.PreparedTaskDispatch,
) -> Result[Unit, LocalDispatchIssue] {
  let compute = match @host.take_installed_task(host, task, installed.channel) {
    Ok(Synchronous(value)) => value
    Ok(Materializing(_, _, _)) => return Err(Configuration(ComputeUnsupported))
    Err(issue) => return Err(Dispatch(issue))
  }
  @strategy.execute_captured_synchronous_task(
    installed.run,
    @host.prepared_task_index(task),
    compute,
  ).map_err(issue => Execution(issue))
}
