///|
/// Connector-owned sequence installation and typed dispatch channel. The common
/// Host transports only registration-bound work; it never unwraps Local state.
struct LocalDispatchModule {
  run : @strategy.CapturedDAG
  mut preparation : LocalDispatchPreparation
  registration : @connector.CapabilityRegistration
  implementation : @local.LocalComputeModule
  channel : @host.DispatchChannel[LocalDispatchPlan]
  carrier_paths : Array[Bool]
  mut estimate_configuration : LocalEstimateConfiguration?
  mut import_policy : (@local.LocalImportLimits, Int64?)?
  mut import_metadata : LocalManagedMetadataLimits?
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
  CarrierSnapshot(@carrier_runtime.SnapshotIssue)
  ControlWorkLimit(Int)
  // Exact failed reservation DATA; the original quota cause stays distinct
  // from current/foreign/cleanup and generic physical failures.
  ExecutionCapacityRefusal(@resources.LedgerIssue, Int64, Int64, Int64)
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
  let original = match
    prepare_local_dispatch_plan(
      @strategy.captured_dag_graph(@host.dispatch_driver_run(driver)),
      registry,
      registration,
      sequences,
      execution,
      measurement,
      max_work,
      managed_capacity?,
      managed_providers~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // First-time configuration may still install its policies before any quote
  // escapes. Both paths retain the same selected module, not another calculator.
  bind_local_dispatch_original(driver, original, false)
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
// Refine only an already-ready captured input of this exact Run. Future tasks
// retain the frozen conservative quote. The existing DAG owns each admitted
// read and its current/cleanup fence; observation does not grant execution.
fn local_dispatch_ready_input_capacity(
  installed : LocalDispatchModule,
  task : Int,
) -> Result[@strategy.PhysicalEnvelope, LocalDispatchIssue] {
  guard local_dispatch_preparation_task_capacity(installed.preparation, task)
    is Some(planned) else {
    return Err(Configuration(InvalidLimits))
  }
  if installed.import_policy is None ||
    @strategy.next_captured_task(installed.run) != Some(task) {
    return Ok(planned)
  }
  guard installed.import_policy is Some((imports, _)) &&
    installed.import_metadata is Some(metadata) &&
    installed.preparation.input_counts.get(local_task_slot(installed, task))
    is Some(total) else {
    return Err(Configuration(InvalidLimits))
  }
  let first = @strategy.captured_compute_first_task(installed.run)
  let mut missing = total
  for
    index, producer in @strategy.captured_next_managed_producers(installed.run) {
    if producer >= 0 && producer < first {
      let read = match
        @strategy.captured_task_input(
          installed.run,
          task,
          @local.local_module_execution_limits(installed.implementation).rows.metadata_entries,
          metadata.name_bytes,
          input_index=index,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Execution(issue))
      }
      if @execution.producer_read_has_cell_access(read) {
        if missing <= 0 {
          return Err(Configuration(InvalidLimits))
        }
        missing -= 1
      }
    }
  }
  if missing == total {
    return Ok(planned)
  }
  guard installed.preparation.capacities.get(local_task_slot(installed, task))
    is Some(Some(base)) &&
    @local.local_import_retention_capacity(imports) is Some(imported) &&
    (match installed.output_policy {
      None => Some(0L)
      Some((limits, _)) => @local.local_export_retention_capacity(limits)
    })
    is Some(exported) &&
    local_dispatch_copy_capacity(
      base,
      metadata.retained_bytes,
      imported,
      exported,
      imports.wire.max_bytes.to_int64(),
      missing,
      true,
    )
    is Some(capacity) else {
    return Err(Configuration(InvalidLimits))
  }
  Ok(capacity)
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
  if installed.import_policy is Some(_) &&
    @strategy.graph_data_count(installed.preparation.graph) > max_work {
    return Err(Configuration(InvalidLimits))
  }
  let capacity = match local_dispatch_ready_input_capacity(installed, task) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let offers = lines.copy()
  let mut slots = local_dispatch_work_slots()
  if installed.import_policy is Some((_, milliseconds)) {
    offers.push({ work_slots: [slots], milliseconds, })
    slots += 1
  }
  if installed.output_policy is Some((_, milliseconds)) {
    offers.push({ work_slots: [slots], milliseconds, })
    slots += 1
  }
  @strategy.prepare_task_offer(
    installed.run,
    task,
    installed.registration,
    slots,
    offers,
    capacity,
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
    local_task_session_output_ceilings(installed.run, task)
    is Some(session_output_ceilings) &&
    local_task_interval_search_ceilings(installed.run, task)
    is Some(interval_search_ceilings) &&
    local_task_asof_search_ceilings(installed.run, task)
    is Some(asof_search_ceilings) &&
    local_task_sequence_match_ceilings(installed.run, task)
    is Some(sequence_match_ceilings) &&
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
      session_output_ceilings~,
      interval_search_ceilings~,
      asof_search_ceilings~,
      sequence_match_ceilings~,
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
