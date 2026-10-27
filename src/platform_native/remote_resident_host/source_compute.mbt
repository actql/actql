///|
/// Trusted Native configuration for a checked single-input linear task
/// graph. Source paths never come from Program inputs. The common standard
/// Host selects and executes the suffix; this adapter does not parse a plan.
pub(all) struct ResidentSourceComputeConfiguration {
  source : ResidentSourceConfiguration
  installed_contracts : @local.ClientInstalledSequenceContracts
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
  EffectRun(@host.ClientEffectCompiledRunIssue)
  ForeignEffectMaterials
  EffectInput(@host.ClientEffectRetainedInputIssue)
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
  capture : @query.CapturedInputSource?
  acquired_source : ResidentAcquiredSourceCapture?
  effect_source : ResidentEffectSourceCapture?
  effect_retained : ResidentEffectRetainedCapture?
  effect_materials : (
    @host.ClientEffectRunMaterials,
    @host.PreparedClientEffectRun,
  )?
  run : @strategy.CapturedDAG
  effect_run : @strategy.CapturedEffectRunDAG?
  compute : @duckdb_native.NativeStandardStrategyRun
  mut stopping : Bool
  source_closed : Ref[Bool]
  mut released : Bool
  effect_captures : Map[String, ResidentEffectCaptureCustody]
  effect_checkpoints : Map[String, ResidentEffectCheckpointCustody]
  effect_previews : Map[String, ResidentEffectPreviewCustody]
  effect_payloads : Map[String, ResidentEffectSourceCustody]
  observe : ((ResidentSourceComputeEvent) -> Bool)?
}

///|
priv struct ResidentAcquiredSourceCapture {
  requirement : @planning.QueryRequirement
  capture : @duckdb_host.NativeHostSourceCapture
}

///|
// Both paths retain their existing checked owner. The Effect owner is never
// turned into an Effect-free Program or admitted by a second planner.
priv enum ResidentSourceOwner {
  Pure(@host.PreparedClientProgram)
  Effect(@host.PreparedClientEffectRun)
}

///|
fn resident_source_owner_graph(
  owner : ResidentSourceOwner,
) -> @strategy.CheckedDAG {
  match owner {
    Pure(prepared) => @host.prepared_client_graph(prepared)
    Effect(run) =>
      @strategy.checked_effect_run_graph(
        @host.prepared_client_effect_run_graph(run),
      )
  }
}

///|
fn resident_source_owner_supported(owner : ResidentSourceOwner) -> Bool {
  let graph = resident_source_owner_graph(owner)
  match owner {
    Pure(prepared) =>
      resident_linear_graph(graph) &&
      @host.prepared_client_acquisition_count(prepared) == 1 &&
      @host.prepared_client_result_count(prepared) == 1
    Effect(run) =>
      resident_linear_computation_graph(graph) &&
      @strategy.graph_captured_prefix(graph) == 1 &&
      @strategy.graph_task_count(graph) == 2 &&
      @strategy.graph_result_count(graph) == 1 &&
      @strategy.checked_effect_run_source_count(
        @host.prepared_client_effect_run_graph(run),
      ) ==
      1
  }
}

///|
/// The same structural support check used by the installed physical owner,
/// exposed so Local admission can refuse an unsupported legal graph before
/// claiming a physical start. This is not Source authority, configuration
/// validation, execution admission or a permission to open a database.
pub fn resident_source_compute_shape_supported(
  prepared : @host.PreparedClientProgram,
) -> Bool {
  resident_source_owner_supported(Pure(prepared))
}

///|
/// The same Effect shape predicate as the existing physical Owner. The Local
/// connection uses it before claiming a start; it grants no acquisition,
/// current authority, capture persistence, Preview or write permission.
pub fn resident_effect_source_compute_shape_supported(
  run : @host.PreparedClientEffectRun,
) -> Bool {
  resident_source_owner_supported(Effect(run))
}

///|
fn resident_source_owner_requirement(
  owner : ResidentSourceOwner,
  configuration : ResidentSourceComputeConfiguration,
) -> Result[@planning.QueryRequirement, ResidentSourceIssue] {
  let source = configuration.source
  match owner {
    Pure(prepared) =>
      @local.prepare_local_query_requirement(
        prepared,
        0,
        0,
        configuration.installed_contracts,
        configuration.values_body,
        Some(source.fragment_contract_body),
        None,
      ).map_err(issue => Query(issue))
    Effect(run) =>
      prepare_resident_effect_source_requirement(
        @host.prepared_client_effect_run_computation(run),
        0,
        0,
        configuration.installed_contracts,
        configuration.values_body,
        Some(source.fragment_contract_body),
        source.source_ref,
        source.source_contract_cid,
      )
  }
}

///|
fn resident_source_owner_sequences(
  owner : ResidentSourceOwner,
  configuration : ResidentSourceComputeConfiguration,
) -> Array[@execution.GeneratedSequence]? {
  let fragment = Some(configuration.source.fragment_contract_body)
  match owner {
    Pure(prepared) =>
      @local.prepare_client_local_sequences(
        prepared,
        configuration.installed_contracts,
        configuration.values_body,
        fragment,
        None,
      )
    Effect(run) =>
      @local.prepare_client_effect_local_sequences(
        @host.prepared_client_effect_run_computation(run),
        configuration.installed_contracts,
        configuration.values_body,
        fragment,
        None,
      )
  }
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
  open_resident_source_compute_owned(
    Pure(prepared),
    configuration,
    occurrence,
    observe,
    None,
    None,
  )
}

///|
/// Acquire and compute the original bound Effect Run using the same Native
/// owners. The caller still needs current Source authority and an exclusive
/// start claim. Optional review materials bind the Host's retained request to
/// this exact checked Run before acquisition. Original request acceptance and
/// current authorization remain the Host's responsibility. This creates no
/// approval and performs no Effect write.
pub fn open_resident_effect_source_compute(
  run : @host.PreparedClientEffectRun,
  configuration : ResidentSourceComputeConfiguration,
  occurrence : String,
  observe? : (ResidentSourceComputeEvent) -> Bool,
  acquisition_limits? : @duckdb_host.NativeHostLimits,
  materials? : @host.ClientEffectRunMaterials,
) -> Result[
  ResidentSourceCompute,
  (ResidentSourceComputeIssue, @output.NativeRemoteStandardInputFailure),
] {
  open_resident_source_compute_owned(
    Effect(run),
    configuration,
    occurrence,
    observe,
    acquisition_limits,
    materials.map(value => (value, run)),
  )
}

///|
fn open_resident_source_compute_owned(
  prepared : ResidentSourceOwner,
  configuration : ResidentSourceComputeConfiguration,
  occurrence : String,
  observe : ((ResidentSourceComputeEvent) -> Bool)?,
  acquisition_limits : @duckdb_host.NativeHostLimits?,
  effect_materials : (
    @host.ClientEffectRunMaterials,
    @host.PreparedClientEffectRun,
  )?,
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
  let graph = resident_source_owner_graph(prepared)
  if effect_materials is Some((materials, bound)) {
    if !resident_original_effect_materials_match(materials, bound) ||
      @host.bind_client_effect_compiled_run(
        materials.prepared,
        materials.allowed,
        materials.run_definition,
      )
      is Err(_) {
      return reject(ForeignEffectMaterials, () => true)
    }
  }
  if !resident_source_owner_supported(prepared) {
    return reject(UnsupportedGraph, () => true)
  }
  let source = configuration.source
  let requirement = match
    resident_source_owner_requirement(prepared, configuration) {
    Ok(value) => value
    Err(issue) => return reject(Source(issue), () => true)
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
      limits?=acquisition_limits,
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
  guard resident_source_owner_sequences(prepared, configuration)
    is Some(generated) &&
    generated.length() == @strategy.graph_task_count(graph) else {
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
      prepared,
      configuration,
      Some(captured),
      ledger,
      holding,
      generated,
      close_source,
      observe,
      acquired_source=Some({ requirement, capture, }),
      effect_materials~,
      effect_source=match prepared {
        Pure(_) => None
        Effect(bound) =>
          Some({
            bound,
            owner: @host.prepared_client_effect_run_computation(bound),
            requirement,
            capture,
          })
      },
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
  guard !self.stopping &&
    @strategy.next_captured_task(self.run) is Some(local_task) &&
    @strategy.graph_task_original_index(
      @strategy.captured_dag_graph(self.run),
      local_task,
    ) ==
    Some(task) else {
    return Err(Unavailable)
  }
  if self.observe is Some(record) && !record(ConsumerEntered(task)) {
    self.stopping = true
    return Err(ObservationUnrecorded(ConsumerEntered(task)))
  }
  match
    @duckdb_native.execute_next_native_standard_strategy_task(self.compute) {
    Ok(Some(completion)) if completion.task == local_task => {
      if self.observe is Some(record) && !record(ConsumerCompleted(task)) {
        self.stopping = true
        return Err(ObservationUnrecorded(ConsumerCompleted(task)))
      }
      Ok({ ..completion, task, })
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
/// The original checked Effect closure shares the same captured Compute DAG.
/// The existing Effect owner must pin/return its inputs; this grants no write.
pub fn ResidentSourceCompute::effect_run(
  self : ResidentSourceCompute,
) -> @strategy.CapturedEffectRunDAG? {
  if self.stopping {
    None
  } else {
    self.effect_run
  }
}

///|
/// The physical computation uses its own original admitted materials for capture.
/// This is preparation context, not completion, current approval or permission
/// to reopen a Source. Stopped or invalid destination custody is not returned.
pub fn ResidentSourceCompute::effect_materials_for_capture(
  self : ResidentSourceCompute,
) -> @host.ClientEffectRunMaterials? {
  guard !self.stopping &&
    self.effect_run is Some(run) &&
    self.effect_materials is Some((materials, bound)) &&
    physical_equal(
      @host.prepared_client_effect_run_computation(bound),
      materials.prepared,
    ) &&
    @strategy.captured_effect_run_matches_checked(
      run,
      @host.prepared_client_effect_run_graph(bound),
    ) else {
    return None
  }
  let original_current = match self.effect_retained {
    Some(retained) =>
      @output.validate_native_remote_retained_task_input_borrow(
        retained.input,
        retained.material,
        retained.current,
      )
      is Ok(_)
    None =>
      !self.source_closed.val &&
      self.effect_source is Some(original) &&
      physical_equal(original.bound, bound) &&
      resident_original_effect_materials_match(materials, bound)
  }
  if !original_current {
    return None
  }
  Some(materials)
}

///|
/// Validate optional Local review context before physical Source acquisition.
/// The bound Run is authoritative; rebinding equal Program bytes cannot replace
/// its checked owner or Run Definition. The Host retains original acceptance;
/// this check validates the supplied request's checked scope, not its journal.
fn resident_original_effect_materials_match(
  materials : @host.ClientEffectRunMaterials,
  bound : @host.PreparedClientEffectRun,
) -> Bool {
  guard materials.request is Some(request) &&
    physical_equal(
      materials.prepared,
      @host.prepared_client_effect_run_computation(bound),
    ) &&
    physical_equal(materials.compilation, materials.allowed.compilation) &&
    @host.prepared_client_effect_request_scope(materials.prepared, request)
    is Ok(_) &&
    @publication.publication_contract_identity(materials.run_definition) ==
    @publication.publication_contract_identity(
      @effect_binding.effect_program_run_definition(
        @strategy.checked_effect_run_owner(
          @host.prepared_client_effect_run_graph(bound),
        ),
      ),
    ) else {
    return false
  }
  true
}

///|
pub fn ResidentSourceCompute::usage(
  self : ResidentSourceCompute,
) -> @resources.LedgerUsage {
  @resources.ledger_usage(@strategy.captured_dag_ledger(self.run))
}

///|
fn resident_source_compute_capacity_released(
  ledger : @resources.Ledger,
) -> Bool {
  // This final accounting observation follows the original physical closes.
  // Zero-byte live tokens remain pending; cumulative spent history does not.
  !@resources.ledger_usage_has_pending_resources(
    @resources.ledger_usage(ledger),
  )
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
  if !resident_source_compute_capacity_released(
      @strategy.captured_dag_ledger(self.run),
    ) {
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
  prepared : ResidentSourceOwner,
  configuration : ResidentSourceComputeConfiguration,
  captured : @query.CapturedInputSource?,
  ledger : @resources.Ledger,
  holding : @resources.Holding,
  generated : Array[@execution.GeneratedSequence],
  close_source : () -> Bool,
  observe : ((ResidentSourceComputeEvent) -> Bool)?,
  retained_input? : (
    @strategy.RetainedTaskProjection,
    @execution.CompletedOutput,
    Int,
  )? = None,
  effect_source? : ResidentEffectSourceCapture? = None,
  acquired_source? : ResidentAcquiredSourceCapture? = None,
  effect_retained? : ResidentEffectRetainedCapture? = None,
  effect_materials? : (
    @host.ClientEffectRunMaterials,
    @host.PreparedClientEffectRun,
  )? = None,
) -> Result[
  ResidentSourceCompute,
  (ResidentSourceComputeIssue, @output.NativeRemoteStandardInputFailure),
] {
  let graph = resident_source_owner_graph(prepared)
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
  // A single trusted profile applies uniformly; otherwise each original
  // Compute task must have exactly its own profile, with none silently ignored.
  if configuration.estimates.length() != 1 &&
    configuration.estimates.length() != @strategy.graph_task_count(graph) - 1 {
    return reject(UnsupportedGraph, close_unbound)
  }
  let opened : Result[
    (@strategy.CapturedDAG, @strategy.CapturedEffectRunDAG?),
    @host.ClientRunOpenIssue,
  ] = match (prepared, captured, retained_input) {
    (Pure(_), Some(source), None) =>
      @strategy.open_captured_dag(graph, source, ledger)
      .map(run => (run, None))
      .map_err(issue => Run(issue))
    (Pure(_), None, Some((projection, output, wire_bytes))) =>
      @strategy.open_retained_task_dag(
        projection,
        output,
        ledger,
        canonical_wire_bytes=wire_bytes,
      )
      .map(run => (run, None))
      .map_err(issue => Run(issue))
    (Effect(bound), Some(source), None) =>
      @strategy.open_captured_effect_run_dag(
        @host.prepared_client_effect_run_graph(bound),
        source,
        ledger,
      )
      .map(run => (@strategy.captured_effect_run_dag(run), Some(run)))
      .map_err(issue => Run(issue))
    (Effect(bound), None, Some((projection, output, wire_bytes))) =>
      @strategy.open_retained_effect_task_dag(
        @host.prepared_client_effect_run_graph(bound),
        projection,
        output,
        ledger,
        canonical_wire_bytes=wire_bytes,
      )
      .map(run => (@strategy.captured_effect_run_dag(run), Some(run)))
      .map_err(issue => Run(issue))
    _ => return reject(UnsupportedGraph, close_unbound)
  }
  let (run, effect_run) = match opened {
    Ok(value) => value
    Err(issue) => return reject(Run(issue), close_unbound)
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
    for
      task in 0..<@strategy.graph_task_count(@strategy.captured_dag_graph(run)) {
      @strategy.close_captured_task_output(run, task)
    }
    if !close_source() {
      return false
    }
    source_closed.val = true
    @strategy.refresh_captured_retention(run)
    resident_source_compute_capacity_released(
      @strategy.captured_dag_ledger(run),
    )
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
  let view = @strategy.captured_dag_graph(run)
  let selected : Array[@execution.GeneratedSequence] = []
  let estimates : Array[@standard.DispatchEstimateProfile] = []
  for task in 1..<@strategy.graph_task_count(view) {
    guard @strategy.graph_task_original_index(view, task) is Some(original) &&
      generated.get(original) is Some(sequence) else {
      return reject(UnsupportedGraph, close_run)
    }
    let estimate = if configuration.estimates.length() == 1 {
      configuration.estimates.get(0)
    } else {
      configuration.estimates.get(original - 1)
    }
    guard estimate is Some(profile) else {
      return reject(UnsupportedGraph, close_run)
    }
    selected.push(sequence)
    estimates.push(profile)
  }
  let dispatch = match
    @standard.configure_strategy_dispatch(
      run,
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      @connector.capability_registration_at(registry, 1).unwrap(),
      selected,
      configuration.dispatch,
    ) {
    Ok(value) => value
    Err(issue) => return reject(Dispatch(issue), close_run)
  }
  match
    @standard.configure_dispatch_estimates(
      dispatch,
      estimates,
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
    effect_run,
    effect_source,
    effect_retained,
    effect_materials,
    close_source,
    capture: captured,
    acquired_source,
    run,
    compute,
    stopping: false,
    source_closed,
    released: false,
    effect_payloads: {},
    effect_captures: {},
    effect_previews: {},
    effect_checkpoints: {},
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
  guard !self.stopping &&
    !self.source_closed.val &&
    self.capture is Some(capture) else {
    return Err(Unavailable)
  }
  @query.prepare_captured_source_relation_export(
    capture,
    limits.max_rows,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  ).map_err(_ => Capture)
}
