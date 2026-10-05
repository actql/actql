///|
/// Trusted Native configuration for the existing one-acquisition/two-task
/// graph. Source paths never come from Program inputs. The common standard
/// Host selects and executes the suffix; this adapter does not parse a plan.
pub(all) struct ResidentSourceComputeConfiguration {
  source : ResidentSourceConfiguration
  registry_body : String
  values_body : String
  dispatch : @standard.TaskDispatchLimits
  estimates : Array[@standard.DispatchEstimateProfile]
  search : @strategy.SearchLimits
  imports : @duckdb_native.NativeComputeImportLimits
  transfer_bytes : Int64
  execution_bytes : Int64
  retained : @duckdb_native.NativeStrategyRetainedOutputProfile?
}

///|
pub(all) enum ResidentSourceComputeIssue {
  UnsupportedGraph
  Unavailable
  Source(ResidentSourceIssue)
  Acquisition(@duckdb_native.NativeReadOnlySourceIssue)
  Execution(@duckdb_native.NativeAcquisitionFailure)
  Capture
  RetainedInput(@output.NativeRemoteRetainedTaskSourceIssue)
  Run(@host.ClientRunOpenIssue)
  Dispatch(@standard.DispatchIssue)
  Compute(@duckdb_native.NativeStandardStrategyRunIssue)
  Export(@host.PublicationOutputExportIssue)
  Capacity(@resources.LedgerIssue)
  ObservationUnrecorded(ResidentSourceComputeEvent)
}

///|
/// Physical Owner boundaries, not remote authorization or journal transitions.
/// Entry events precede the actual acquisition/consumer Owner call; completion
/// events follow its confirmed result. A trusted caller may durably record or
/// pause these boundaries for evidence without replacing the execution Owner.
pub(all) enum ResidentSourceComputeEvent {
  AcquisitionEntered
  ProducerCaptured
  ConsumerEntered(Int)
  ConsumerCompleted(Int)
  CleanupPending
  CleanupCompleted
}

///|
/// The capture's physical acquisition outlives the exact checked consumer.
/// Native computation, reservations and cleanup stay with the existing Owners.
struct ResidentSourceCompute {
  close_source : () -> Bool
  capture : @query.CapturedInputSource
  run : @strategy.CapturedDAG
  compute : @duckdb_native.NativeStandardStrategyRun
  mut stopping : Bool
  source_closed : Ref[Bool]
  mut released : Bool
  observe : ((ResidentSourceComputeEvent) -> Bool)?
}

///|
/// Native composition entry, called only after existing Host admission,
/// current Source authority/lifetime checks and the exclusive acquisition
/// start claim. Opening this owner acquires exactly once; retries use the same
/// owner, never this constructor. It grants no remote dispatch authority.
pub fn open_resident_source_compute(
  prepared : @host.PreparedClientProgram,
  configuration : ResidentSourceComputeConfiguration,
  occurrence : String,
  observe? : (ResidentSourceComputeEvent) -> Bool,
) -> Result[
  ResidentSourceCompute,
  (ResidentSourceComputeIssue, @output.NativeRemoteStandardInputFailure),
] {
  let reject = fn(issue : ResidentSourceComputeIssue, cleanup : () -> Bool) {
    Err(
      (
        issue,
        @output.prepare_native_remote_standard_input_failure(
          "source-compute-preparation", cleanup,
        ).unwrap(),
      ),
    )
  }
  let graph = @host.prepared_client_graph(prepared)
  if @strategy.graph_program_has_effects(graph) ||
    @strategy.graph_task_count(graph) != 2 ||
    @host.prepared_client_acquisition_count(prepared) != 1 ||
    @host.prepared_client_result_count(prepared) != 1 ||
    @strategy.graph_result_task(graph, 0) != Some(1) ||
    @strategy.graph_task_target(graph, 0) is Some(_) ||
    @strategy.graph_task_target(graph, 1) is None {
    return reject(UnsupportedGraph, () => true)
  }
  let source = configuration.source
  let requirement = match
    @local.prepare_local_query_requirement(
      prepared,
      0,
      0,
      configuration.registry_body,
      configuration.values_body,
      Some(source.fragment_contract_body),
      None,
    ) {
    Ok(value) => value
    Err(issue) => return reject(Source(Query(issue)), () => true)
  }
  match
    require_resident_source_identity(
      requirement,
      source.source_ref,
      source.source_contract_cid,
    ) {
    Ok(_) => ()
    Err(issue) => return reject(Source(issue), () => true)
  }
  let setup = match
    @local.prepare_client_duckdb_acquisition(
      requirement,
      source.database_schema,
      source.table,
      source.query_contract_body,
      source.evidence_contract_body,
      source.two_receipt_contract_body,
    ) {
    Ok(value) => value
    Err(issue) => return reject(Source(Acquisition(issue)), () => true)
  }
  let physical = match
    @duckdb_native.prepare_native_read_only_source_binding(
      setup,
      source.database_path,
      source.memory_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return reject(Source(Binding(issue)), () => true)
  }
  guard @local.prepare_client_local_sequences(
      prepared,
      configuration.registry_body,
      configuration.values_body,
      Some(source.fragment_contract_body),
      None,
    )
    is Some(generated) &&
    generated.length() == 2 else {
    return reject(UnsupportedGraph, () => true)
  }
  let ledger = match @resources.create_ledger(source.ledger) {
    Ok(value) => value
    Err(issue) => return reject(Capacity(issue), () => true)
  }
  guard @duckdb_host.configured_native_capacity(setup) is Some(capacity) else {
    return reject(UnsupportedGraph, () => true)
  }
  if source.memory_bytes > 9223372036854775807L - capacity.execution_bytes {
    return reject(Capacity(InvalidCharge), () => true)
  }
  // Receiver scratch and the live native database share this reservation. It
  // remains open until physical Source cleanup, including while consumers run.
  let reservation = match
    @resources.reserve_attempt(
      ledger,
      0L,
      capacity.retained_bytes,
      capacity.execution_bytes + source.memory_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return reject(Capacity(issue), () => true)
  }
  let acquisition = match
    @duckdb_native.open_native_read_only_source_acquisition(
      physical,
      setup,
      source.library,
      occurrence,
    ) {
    Ok(value) => value
    Err(issue) =>
      return reject(Acquisition(issue), () => {
        !@resources.reservation_open(reservation) ||
        @resources.settle_reservation(ledger, reservation) is Ok(_)
      })
  }
  let close_source = () => {
    @duckdb_native.close_native_acquisition_runtime(acquisition)
    !@resources.reservation_open(reservation) ||
    @resources.settle_reservation(ledger, reservation) is Ok(_)
  }
  if observe is Some(record) && !record(AcquisitionEntered) {
    return reject(ObservationUnrecorded(AcquisitionEntered), close_source)
  }
  match @duckdb_native.execute_native_acquisition_runtime(acquisition) {
    Ok(_) => ()
    Err(issue) => return reject(Execution(issue), close_source)
  }
  guard @duckdb_native.native_acquisition_runtime_source_capture(acquisition)
    is Ok(capture) &&
    @duckdb_host.native_host_source_capture_source(capture) is Ok(captured) else {
    return reject(Capture, close_source)
  }
  let holding = match
    @resources.retain_allocation(ledger, reservation, capacity.retained_bytes) {
    Ok(value) => value
    Err(issue) => return reject(Capacity(issue), close_source)
  }
  let owner = match
    open_resident_captured_compute(
      prepared, configuration, captured, ledger, holding, generated, close_source,
      observe,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if observe is Some(record) && !record(ProducerCaptured) {
    return reject(ObservationUnrecorded(ProducerCaptured), () => owner.close())
  }
  Ok(owner)
}

///|
/// The existing graph chooses readiness and input correspondence. The remote
/// caller must separately admit the exact task's dispatch before this call.
pub fn ResidentSourceCompute::execute_task(
  self : ResidentSourceCompute,
  task : Int,
) -> Result[
  @duckdb_native.NativeStandardStrategyTaskCompletion,
  ResidentSourceComputeIssue,
] {
  if self.stopping || @strategy.next_captured_task(self.run) != Some(task) {
    return Err(Unavailable)
  }
  if self.observe is Some(record) && !record(ConsumerEntered(task)) {
    self.stopping = true
    return Err(ObservationUnrecorded(ConsumerEntered(task)))
  }
  match
    @duckdb_native.execute_next_native_standard_strategy_task(self.compute) {
    Ok(Some(completion)) if completion.task == task => {
      if self.observe is Some(record) && !record(ConsumerCompleted(task)) {
        self.stopping = true
        return Err(ObservationUnrecorded(ConsumerCompleted(task)))
      }
      Ok(completion)
    }
    Ok(_) => {
      self.stopping = true
      Err(Unavailable)
    }
    Err(issue) => {
      self.stopping = true
      Err(Compute(issue))
    }
  }
}

///|
/// Re-admit the physical completed output for the same graph's Named Result.
/// This exports bytes; public publication and reader grants remain separate.
pub fn ResidentSourceCompute::prepare_result_export(
  self : ResidentSourceCompute,
  limits : @host.PublicationOutputExportLimits,
) -> Result[@host.PublicationOutputExport, ResidentSourceComputeIssue] {
  if self.stopping {
    return Err(Unavailable)
  }
  guard @strategy.graph_result_task(@strategy.captured_dag_graph(self.run), 0)
    is Some(task) else {
    return Err(Unavailable)
  }
  let output = match
    @duckdb_native.read_native_standard_task_output(
      self.compute,
      task,
      limits.max_rows,
      limits.values,
      limits.payload_wire,
      limits.max_batch_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  @host.prepare_captured_result_publication_export(
    self.run,
    0,
    limits,
    converted_output=output,
  ).map_err(issue => Export(issue))
}

///|
pub fn ResidentSourceCompute::usage(
  self : ResidentSourceCompute,
) -> @resources.LedgerUsage {
  @resources.ledger_usage(@strategy.captured_dag_ledger(self.run))
}

///|
fn resident_source_compute_capacity_released(
  run : @strategy.CapturedDAG,
) -> Bool {
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  // Holding identifiers are cumulative admission counters, not live resources.
  usage.held_bytes == 0L &&
  usage.uncertain_transfer_bytes == 0L &&
  usage.reserved_transfer_bytes == 0L &&
  usage.reserved_retention_bytes == 0L &&
  usage.reserved_execution_bytes == 0L
}

///|
/// Cancel/release stop new tasks but retain the same physical cleanup owner.
/// A pending close never returns capacity and never restarts acquisition or
/// Compute. The existing remote runtime decides the formal terminal state.
pub fn ResidentSourceCompute::close(self : ResidentSourceCompute) -> Bool {
  if self.released {
    return true
  }
  self.stopping = true
  @strategy.stop_captured_dag(self.run)
  match @duckdb_native.close_native_standard_strategy_run(self.compute) {
    Ok(true) => ()
    Ok(false) | Err(_) => {
      if self.observe is Some(record) {
        ignore(record(CleanupPending))
      }
      return false
    }
  }
  for
    task in 0..<@strategy.graph_task_count(
      @strategy.captured_dag_graph(self.run),
    ) {
    @strategy.close_captured_task_output(self.run, task)
  }
  if !self.source_closed.val {
    if !(self.close_source)() {
      if self.observe is Some(record) {
        ignore(record(CleanupPending))
      }
      return false
    }
    self.source_closed.val = true
  }
  @strategy.refresh_captured_retention(self.run)
  if !resident_source_compute_capacity_released(self.run) {
    if self.observe is Some(record) {
      ignore(record(CleanupPending))
    }
    return false
  }
  // Missing completion evidence keeps this exact cleanup owner retryable even
  // when its physical resources are already gone. Never reopen acquisition or
  // return a successful close before the caller records that boundary.
  if self.observe is Some(record) && !record(CleanupCompleted) {
    return false
  }
  self.released = true
  self.released
}

///|
/// Both acquisition and independent Transfer captures enter the same checked
/// graph, selection, Native execution and cleanup Owners.
fn open_resident_captured_compute(
  prepared : @host.PreparedClientProgram,
  configuration : ResidentSourceComputeConfiguration,
  captured : @query.CapturedInputSource,
  ledger : @resources.Ledger,
  holding : @resources.Holding,
  generated : Array[@execution.GeneratedSequence],
  close_source : () -> Bool,
  observe : ((ResidentSourceComputeEvent) -> Bool)?,
) -> Result[
  ResidentSourceCompute,
  (ResidentSourceComputeIssue, @output.NativeRemoteStandardInputFailure),
] {
  let graph = @host.prepared_client_graph(prepared)
  let source = configuration.source
  let reject = fn(issue : ResidentSourceComputeIssue, cleanup : () -> Bool) {
    Err(
      (
        issue,
        @output.prepare_native_remote_standard_input_failure(
          "source-compute-preparation", cleanup,
        ).unwrap(),
      ),
    )
  }
  let source_closed = Ref(false)
  let close_unbound = () => {
    let closed = close_source()
    if closed {
      source_closed.val = true
    }
    closed &&
    (
      !@resources.holding_available(ledger, holding) ||
      @resources.release_allocation(ledger, holding) is Ok(_)
    )
  }
  let run = match @strategy.open_captured_dag(graph, captured, ledger) {
    Ok(value) => value
    Err(issue) =>
      return reject(Run(@host.ClientRunOpenIssue::Run(issue)), close_unbound)
  }
  match
    @strategy.retain_captured_task_allocation(run, 0, holding, release_confirmed=() => {
      source_closed.val
    }) {
    Ok(_) => ()
    Err(issue) => return reject(Capacity(issue), close_unbound)
  }
  let close_run = () => {
    @strategy.stop_captured_dag(run)
    @strategy.close_captured_task_output(run, 0)
    @strategy.close_captured_task_output(run, 1)
    if !close_source() {
      return false
    }
    source_closed.val = true
    @strategy.refresh_captured_retention(run)
    resident_source_compute_capacity_released(run)
  }
  let registry = @connector.prepare_capability_registry(
    [
      { name: "local", acquisition: false, fixed_compute: true, effect: false, },
      {
        name: "duckdb",
        acquisition: false,
        fixed_compute: true,
        effect: false,
      },
    ],
    2,
    100,
  ).unwrap()
  let dispatch = match
    @standard.configure_strategy_dispatch(
      run,
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      @connector.capability_registration_at(registry, 1).unwrap(),
      [generated[1]],
      configuration.dispatch,
    ) {
    Ok(value) => value
    Err(issue) => return reject(Dispatch(issue), close_run)
  }
  match
    @standard.configure_dispatch_estimates(
      dispatch,
      configuration.estimates,
      configuration.search,
    ) {
    Ok(_) => ()
    Err(issue) => return reject(Dispatch(issue), close_run)
  }
  let compute = match
    @duckdb_native.open_native_standard_strategy_run(
      dispatch,
      configuration.imports,
      configuration.transfer_bytes,
      configuration.execution_bytes,
      library=Some(source.library),
      retained_profile?=configuration.retained,
    ) {
    Ok(value) => value
    Err(issue) => return reject(Compute(issue), close_run)
  }
  let owner : ResidentSourceCompute = {
    close_source,
    capture: captured,
    run,
    compute,
    stopping: false,
    source_closed,
    released: false,
    observe,
  }
  Ok(owner)
}

///|
/// Export the already acquired producer through the existing query capture
/// Owner. This neither executes a consumer nor opens another Source query.
pub fn ResidentSourceCompute::prepare_source_export(
  self : ResidentSourceCompute,
  limits : @host.PublicationOutputExportLimits,
) -> Result[@execution.CompletedOutputExport, ResidentSourceComputeIssue] {
  if self.stopping || self.source_closed.val {
    return Err(Unavailable)
  }
  @query.prepare_captured_source_relation_export(
    self.capture,
    limits.max_rows,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  ).map_err(_ => Capture)
}
