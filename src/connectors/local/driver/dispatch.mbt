///|
/// Connector-owned sequence installation and typed dispatch channel. The common
/// Host transports only registration-bound work; it never unwraps Local state.
struct LocalDispatchModule {
  run : @strategy.CapturedDAG
  registration : @connector.CapabilityRegistration
  implementation : @local.LocalComputeModule
  channel : @host.DispatchChannel[LocalDispatchPlan]
  carrier_paths : Array[Bool]
  mut estimate_configuration : LocalEstimateConfiguration?
  mut import_policy : (@local.LocalImportLimits, Int64?)?
  mut output_policy : (@local.LocalExportLimits, Int64?)?
  mut policy_sealed : Bool
}

///|
fn local_task_slot(installed : LocalDispatchModule, task : Int) -> Int {
  task - @strategy.captured_compute_first_task(installed.run)
}

///|
/// Pure typed path decision for the next physical task. It does not admit a
/// candidate or turn a Carrier generation into a row Store representation.
pub fn local_dispatch_next_carrier_path(
  installed : LocalDispatchModule,
) -> Bool {
  guard @strategy.next_captured_task(installed.run) is Some(task) else {
    return false
  }
  local_dispatch_carrier_path(installed, task)
}

///|
/// A row-file predecessor may be read through captured_task_input. A
/// Carrier predecessor must supply its exact managed material instead.
pub fn local_dispatch_predecessor_is_carrier(
  installed : LocalDispatchModule,
  producer : Int,
) -> Bool {
  let first = @strategy.captured_compute_first_task(installed.run)
  if producer < first ||
    producer >=
    @strategy.graph_task_count(@strategy.captured_dag_graph(installed.run)) {
    return false
  }
  @local.local_module_sequence_outputs_carrier(
    installed.implementation,
    local_task_slot(installed, producer),
  )
}

///|
priv enum LocalDispatchPlan {
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
  // A completed output could not be exported under the Host's import limits
  // while establishing a result identity: a resource limit, not an
  // unsupported identity.
  IdentityExport(@execution.CompletedExportIssue)
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
  let first = @strategy.captured_compute_first_task(run)
  if sequences.length() != @strategy.graph_task_count(graph) - first {
    return Err(Configuration(ForeignPreparation))
  }
  let physical_sequences = []
  for index, sequence in sequences {
    if !(@strategy.graph_task_owner(graph, index + first) is Some(owner) &&
      physical_equal(owner, @execution.generated_sequence_owner(sequence))) {
      return Err(Configuration(ForeignPreparation))
    }
    let physical = match
      @strategy.graph_task_selected_step(graph, index + first) {
      Some(step) =>
        match @execution.select_generated_sequence_step(sequence, step) {
          Some(value) => value
          None => return Err(Configuration(ForeignPreparation))
        }
      None =>
        match @strategy.graph_task_prefix_end(graph, index + first) {
          Some(last) =>
            match @execution.select_generated_sequence_prefix(sequence, last) {
              Some(value) => value
              None => return Err(Configuration(ForeignPreparation))
            }
          None => sequence
        }
    }
    physical_sequences.push(physical)
  }
  let implementation = match
    @local.prepare_local_compute_module(
      registry,
      registration,
      physical_sequences,
      execution,
      measurement,
      max_work,
      physical_sequences.length(),
      managed_capacity?,
      managed_providers~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Configuration(issue))
  }
  let carrier_paths = local_dispatch_carrier_path_table(run, implementation)
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
    carrier_paths,
    estimate_configuration: None,
    import_policy: None,
    output_policy: None,
    policy_sealed: false,
  })
}

///|
/// Import limits a bounded materializing attempt uses: the Host's
/// configuration, or the module's own defaults when none was configured.
fn local_effective_import_limits(
  installed : LocalDispatchModule,
) -> @local.LocalImportLimits {
  match installed.import_policy {
    Some((configured, _)) => configured
    None =>
      @local.local_default_import_limits(
        @local.local_module_execution_limits(installed.implementation),
        @local.local_module_measurement_limits(installed.implementation),
      )
  }
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
  if !local_dispatch_offer_supported(installed, task) {
    return Err(Configuration(ComputeUnsupported))
  }
  guard @local.local_module_capacity(
      installed.implementation,
      local_task_slot(installed, task),
    )
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
    is Some(join_output_ceilings) &&
    local_task_expansion_output_ceilings(installed.run, task)
    is Some(expansion_output_ceilings) &&
    local_task_interval_search_ceilings(installed.run, task)
    is Some(interval_search_ceilings) &&
    local_task_asof_search_ceilings(installed.run, task)
    is Some(asof_search_ceilings) &&
    local_task_aggregate_output_ceilings(installed.run, task)
    is Some(aggregate_output_ceilings) &&
    local_task_analytic_envelopes(installed.run, task)
    is Some(analytic_envelopes) else {
    return Err(Configuration(InvalidLimits))
  }
  // Every Local task runs as a bounded materializing attempt: its provider
  // advances in quanta, and retained inputs and outputs keep their Store path.
  let limits = local_effective_import_limits(installed)
  let output_limits = installed.output_policy.map(value => value.0)
  let compute = match
    @local.prepare_local_module_materializing_compute(
      installed.implementation,
      local_task_slot(installed, task),
      request,
      limits,
      _ => @strategy.RunIssue::Compute(InvalidLimits),
      None,
      output_limits~,
      join_output_ceilings~,
      expansion_output_ceilings~,
      interval_search_ceilings~,
      asof_search_ceilings~,
      aggregate_output_ceilings~,
      analytic_envelopes~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  @host.stage_dispatch_work(
    installed.channel,
    task,
    revision,
    request,
    Materializing(compute, limits, output_limits),
  ).map_err(issue => Dispatch(issue))
}

///|
/// Drain one staged Local task on a Host without an event loop. The same
/// bounded attempt runs to completion; inputs must already be cell-readable.
pub fn[C, E] execute_local_dispatch(
  installed : LocalDispatchModule,
  host : @host.DispatchHost[C, E],
  task : @host.PreparedTaskDispatch,
) -> Result[Unit, LocalDispatchIssue] {
  let operations = match start_local_dispatch(installed, host, task) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let result = if operations.inputs.length() != 0 ||
    operations.output is Some(_) {
    Err(Configuration(InputUnavailable))
  } else {
    (operations.execute)()
    .bind(_ => (operations.settle)())
    .bind(_ => (operations.complete)())
  }
  // A completed output belongs to the captured DAG; closing the attempt would
  // also close that output. Only a failed attempt is closed here.
  if result is Err(_) {
    (operations.close)()
  }
  result
}
