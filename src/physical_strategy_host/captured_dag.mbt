///|
/// Host-private serial execution state. Task success is not Program publication.
/// A captured acquisition is borrowed; a source-free root is an ordinary task.
struct CapturedDAG {
  graph : CheckedDAG
  offer_owner : StrategyOfferOwner
  original_sources : Array[@query.CapturedInputSource?]
  sources : Array[@query.CapturedInputSource?]
  imported_root_statistics : CapturedExecutionRootStatistics?
  ledger : @resources.Ledger
  outputs : Array[CommittedTaskOutput?]
  done : Array[Bool]
  lifetimes : Array[TaskLifetime]
  effect_dependency_outputs : Array[Bool]
  resources : Array[TaskRetention?]
  join_limits : Array[Array[(Int, Int64)]]
  interval_search_limits : Array[Array[(Int, Int64)]]
  asof_search_limits : Array[Array[(Int, Int64)]]
  aggregate_limits : Array[Array[@connector.AggregateOutputCeiling]]
  analytic_envelopes : Array[Array[@connector.AnalyticEnvelope]]
  inputs : Array[Array[@execution.ProducerRead?]]
  supplied : Array[Array[@execution.CapturedRows?]]
  supplied_reads : Array[Array[@execution.SuppliedRelationRead?]]
  mut running : (Int, TaskExecution)?
  executions : Array[TaskExecution?]
  mut resident_environments : Array[ResidentEnvironment]
  mut stopped : Bool
  mut failure : (Int, RunIssue)?
  mut generation : Int
  mut search : SearchLimits?
  mut revisions : Int
  mut searched_generation : Int?
  mut searched_resources : SearchResources?
  mut strategy : StrategyRevision?
  mut search_report : Array[StrategyAssessment]
  mut search_report_complete : Bool
  revision_history : Array[StrategyRevision]
  mut managed_publication_identity : Bool
  mut managed_consumer_identity : Bool
  mut managed_host_identity : Bool
  mut managed_identity_policy_sealed : Bool
  managed_selections : Array[@connector.CapabilityRegistration?]
  mut activation_required : Bool
  mut activation_grant : (Int, Int)?
}

///|
/// An exact admitted Effect Run retained through physical capture. Compute
/// access does not authorize Preview admission or mutation dispatch.
struct CapturedEffectRunDAG {
  checked : CheckedEffectRunDAG
  captured : CapturedDAG
}

///|
/// One authoritative committed output slot per checked task. The variants
/// preserve representation-specific typed access; they are not independent
/// completion ledgers. A task can occupy this slot only once.
priv enum CommittedTaskOutput {
  Materialized(@execution.CompletedOutput)
  Managed(@execution.ManagedCompletionReference)
  CarrierManaged(@execution.CarrierManagedCompletionReference)
}

///|
fn materialized_task_output(
  run : CapturedDAG,
  task : Int,
) -> @execution.CompletedOutput? {
  match run.outputs.get(task).bind(value => value) {
    Some(Materialized(output)) => Some(output)
    _ => None
  }
}

///|
fn managed_task_output_reference(
  run : CapturedDAG,
  task : Int,
) -> @execution.ManagedCompletionReference? {
  match run.outputs.get(task).bind(value => value) {
    Some(Managed(reference)) => Some(reference)
    _ => None
  }
}

///|
fn carrier_managed_task_output_reference(
  run : CapturedDAG,
  task : Int,
) -> @execution.CarrierManagedCompletionReference? {
  match run.outputs.get(task).bind(value => value) {
    Some(CarrierManaged(reference)) => Some(reference)
    _ => None
  }
}

///|
pub(all) enum RunIssue {
  UnsupportedGraph
  ForeignCapture
  NotReady
  Stopped
  ForeignCandidate
  PreviewWorkLimit
  MissingOutput
  Capture(@query.CapturedSourceIssue)
  Binding(@execution.ProducerBindingIssue)
  Read(@execution.ProducerReadIssue)
  Compute(@connector.FixedComputeIssue)
  Implementation(Error)
  Physical(@resources.LedgerIssue)
  ActivationNotAuthorized
}

///|
/// Compare every owned requirement with an exact Connector declaration. A
/// stricter declaration is safe; a missing, mismatched, or looser one is not.
fn aggregate_output_limits_satisfied(
  required : Array[@connector.AggregateOutputCeiling],
  declared : (Int, String, @connector.AggregateOutputUnit) -> Int64?,
) -> Bool {
  for value in required {
    let step = @connector.aggregate_output_ceiling_step(value)
    let name = @connector.aggregate_output_ceiling_name(value)
    let unit = @connector.aggregate_output_ceiling_unit(value)
    let maximum = @connector.aggregate_output_ceiling_maximum(value)
    match declared(step, name, unit) {
      Some(actual) if actual <= maximum => ()
      _ => return false
    }
  }
  true
}

///|
fn analytic_envelopes_satisfied(
  required : Array[@connector.AnalyticEnvelope],
  declared : (Int) -> @connector.AnalyticEnvelope?,
) -> Bool {
  for selected in required {
    let step = @connector.analytic_envelope_step(selected)
    guard declared(step) is Some(actual) else { return false }
    if @connector.analytic_envelope_input_wire_bytes(actual) >
      @connector.analytic_envelope_input_wire_bytes(selected) ||
      @connector.analytic_envelope_output_wire_bytes(actual) >
      @connector.analytic_envelope_output_wire_bytes(selected) ||
      @connector.analytic_envelope_partition_wire_bytes(actual) >
      @connector.analytic_envelope_partition_wire_bytes(selected) ||
      @connector.analytic_envelope_frame_memberships(actual) >
      @connector.analytic_envelope_frame_memberships(selected) ||
      @connector.analytic_envelope_output_rows(actual) >
      @connector.analytic_envelope_output_rows(selected) {
      return false
    }
  }
  true
}

///|
/// Initial profile: one captured acquisition at unit zero, ordered checked
/// data inputs per task and one final output. No fresh reads are synthesized.
/// Bindings are indexed by checked receiving port.
pub fn open_captured_dag(
  graph : CheckedDAG,
  source : @query.CapturedInputSource,
  ledger : @resources.Ledger,
  supplied? : Array[@execution.CapturedRows] = [],
  supplied_reads? : Array[(Int, Int, @execution.SuppliedRelationRead)] = [],
) -> Result[CapturedDAG, RunIssue] {
  if graph.captured_prefix_value() != 1 || graph_program_has_effects(graph) {
    return Err(UnsupportedGraph)
  }
  open_checked_dag(graph, [(0, source)], ledger, supplied, supplied_reads~)
}

///|
/// Open the exact two-acquisition prefix using occurrence/task-indexed handles.
/// Missing, repeated, substituted or later source slots fail before execution.
pub fn open_multi_captured_dag(
  graph : CheckedDAG,
  sources : Array[(Int, @query.CapturedInputSource)],
  ledger : @resources.Ledger,
  supplied? : Array[@execution.CapturedRows] = [],
) -> Result[CapturedDAG, RunIssue] {
  if graph.captured_prefix_value() < 1 || graph_program_has_effects(graph) {
    return Err(UnsupportedGraph)
  }
  open_checked_dag(graph, sources, ledger, supplied)
}

///|
/// Admit a checked source-free root to the same serial task lifecycle used by
/// captured acquisitions. The root must have no external input or predecessor.
pub fn open_source_free_dag(
  graph : CheckedDAG,
  ledger : @resources.Ledger,
) -> Result[CapturedDAG, RunIssue] {
  if !valid_source_free_root(graph) || graph_program_has_effects(graph) {
    return Err(UnsupportedGraph)
  }
  open_checked_dag(graph, [], ledger, [])
}

///|
/// Whole Source input is supplied to the original root computation, not
/// installed as its completed output. Existing task/current/cleanup machinery
/// owns the resulting execution and retains the exact live Source borrow.
pub fn open_source_input_dag(
  graph : CheckedDAG,
  source : @query.CapturedInputSource,
  ledger : @resources.Ledger,
) -> Result[CapturedDAG, RunIssue] {
  open_source_inputs_dag(graph, [source], ledger)
}

///|
/// Complete input captures retain their checked task/input slots. The same
/// checked runner owns their resources and retirement; none completes a task.
pub fn open_source_inputs_dag(
  graph : CheckedDAG,
  sources : Array[@query.CapturedInputSource],
  ledger : @resources.Ledger,
) -> Result[CapturedDAG, RunIssue] {
  let (reads, _) = match source_inputs_original_reads(graph, sources) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if reads.length() != graph.supplied_slots_count() {
    return Err(ForeignCapture)
  }
  open_checked_dag(graph, [], ledger, [], supplied_reads=reads)
}

///|
/// The live root has the same original supplied input, not an equal row wire.
pub fn source_input_dag_matches_read(
  run : CapturedDAG,
  read : @execution.SuppliedRelationRead,
) -> Bool {
  source_input_dag_matches_read_at(run, read, 0)
}

///|
/// The selected task borrows this exact live original input binding.
pub fn source_input_dag_matches_read_at(
  run : CapturedDAG,
  read : @execution.SuppliedRelationRead,
  task : Int,
) -> Bool {
  !run.stopped &&
  run.graph.captured_prefix_value() == 0 &&
  !run.graph.source_free_root_value() &&
  run.supplied_reads
  .get(task)
  .map(ports => {
    ports.any(value => {
      value
      .map(actual => {
        @execution.supplied_relation_read_same_binding(actual, read) &&
        @execution.supplied_relation_read_available(actual)
      })
      .unwrap_or(false)
    })
  })
  .unwrap_or(false)
}

///|
/// Retain cleanup custody for a Source whose exact producer completion was
/// imported. Its execution read remains unavailable after completion; the
/// original input and complete output provenance must still be live here.
pub fn source_input_dag_retains_completed_read_at(
  run : CapturedDAG,
  read : @execution.SuppliedRelationRead,
  task : Int,
) -> Bool {
  guard !run.stopped &&
    run.graph.captured_prefix_value() == 0 &&
    !run.graph.source_free_root_value() &&
    task >= 0 &&
    task < run.done.length() &&
    run.done[task] &&
    run.lifetimes[task].live &&
    materialized_task_output(run, task) is Some(output) &&
    @execution.supplied_relation_read_available(read) &&
    run.supplied_reads[task].any(port => {
      port
      .map(actual => {
        @execution.supplied_relation_read_same_binding(actual, read)
      })
      .unwrap_or(false)
    }) &&
    @execution.completed_output_available(output) else {
    return false
  }
  // The same committed slot was admitted by completed_segment_inputs_output
  // when imported, or by the ordinary completion input check when executed.
  // Imported Source roots retain ProducerRead provenance from their original
  // prefix; it must not be recast as a fresh SuppliedRelation execution.
  // Original availability callbacks can retire this port reentrantly. This
  // result is custody correspondence only, never renewed execution access.
  !run.stopped &&
  run.lifetimes[task].live &&
  materialized_task_output(run, task)
  .map(actual => physical_equal(actual, output))
  .unwrap_or(false)
}

///|
fn valid_source_free_root(graph : CheckedDAG) -> Bool {
  !(graph.owners_count() == 0) &&
  graph.input_counts_at(0).unwrap() == 0 &&
  graph.source_free_root_value() &&
  @checked.source_execution_count(graph.program_value()) == 0 &&
  !graph.data_iter().any(edge => edge.consumer == 0) &&
  !graph.control_iter().any(edge => edge.consumer == 0) &&
  graph.supplied_slots_count() == 0
}

///|
/// A no-external-sources observation requires the checked Program and every
/// physical task input to be source-free, not just an omitted source argument.
pub fn graph_source_free_inputs_complete(graph : CheckedDAG) -> Bool {
  valid_source_free_root(graph)
}

///|
/// An Effect Run may use a Values root only through its checked Run owner.
/// Both captured and source-free roots enter the same private task lifecycle.
pub fn open_source_free_effect_run_dag(
  checked : CheckedEffectRunDAG,
  ledger : @resources.Ledger,
) -> Result[CapturedEffectRunDAG, RunIssue] {
  let graph = checked.computation.graph_value()
  if !valid_source_free_root(graph) || !graph_program_has_effects(graph) {
    return Err(UnsupportedGraph)
  }
  let dependencies = match
    effect_dependency_ports(checked.computation, 4096, 65536, 64) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let captured = match open_checked_dag(graph, [], ledger, []) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for dependency in dependencies {
    captured.effect_dependency_outputs[dependency.task] = true
  }
  Ok({ checked, captured, })
}

///|
/// Open physical compute only from the bound Effect Run graph. The returned
/// owner keeps the static closure and admitted Run beside the captured DAG.
pub fn open_captured_effect_run_dag(
  checked : CheckedEffectRunDAG,
  source : @query.CapturedInputSource,
  ledger : @resources.Ledger,
  supplied? : Array[@execution.CapturedRows] = [],
) -> Result[CapturedEffectRunDAG, RunIssue] {
  if checked.computation.graph_value().captured_prefix_value() != 1 {
    return Err(UnsupportedGraph)
  }
  open_effect_run_captures(checked, [(0, source)], ledger, supplied)
}

///|
/// Keep all original acquisition holdings on their existing ledger while
/// opening the same admitted Effect Run. The common DAG owner checks each
/// source's task coordinate, identity and retained holdings before Compute.
pub fn open_multi_captured_effect_run_dag(
  checked : CheckedEffectRunDAG,
  sources : Array[(Int, @query.CapturedInputSource)],
  ledger : @resources.Ledger,
  supplied? : Array[@execution.CapturedRows] = [],
) -> Result[CapturedEffectRunDAG, RunIssue] {
  if checked.computation.graph_value().captured_prefix_value() < 2 ||
    sources.length() !=
    checked.computation.graph_value().captured_prefix_value() {
    return Err(UnsupportedGraph)
  }
  open_effect_run_captures(checked, sources, ledger, supplied)
}

///|
fn open_effect_run_captures(
  checked : CheckedEffectRunDAG,
  sources : Array[(Int, @query.CapturedInputSource)],
  ledger : @resources.Ledger,
  supplied : Array[@execution.CapturedRows],
) -> Result[CapturedEffectRunDAG, RunIssue] {
  if checked.computation.graph_value().source_free_root_value() {
    return Err(UnsupportedGraph)
  }
  let dependencies = match
    effect_dependency_ports(checked.computation, 4096, 65536, 64) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let captured = match
    open_checked_dag(
      checked.computation.graph_value(),
      sources,
      ledger,
      supplied,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for dependency in dependencies {
    captured.effect_dependency_outputs[dependency.task] = true
  }
  Ok({ checked, captured, })
}

///|
// The selected caller supplies an actual completed keyed read. The checked
// Source port and original live input, never planned metadata, discharge the
// one deferred slot. No original graph or Source holding is mutated.
pub fn open_multi_captured_effect_run_keyed_dag(
  checked : CheckedEffectRunDAG,
  sources : Array[(Int, @query.CapturedInputSource)],
  ledger : @resources.Ledger,
  task : Int,
  model_step : Int,
  read : @execution.SuppliedRelationRead,
) -> Result[CapturedEffectRunDAG, RunIssue] {
  let original = checked.computation.graph_value()
  guard @graph.graph_with_completed_keyed_model_input(
      original, task, model_step, read,
    )
    is Some(graph) else {
    return Err(ForeignCapture)
  }
  let mut slot = None
  for value in graph.supplied_slots_iter() {
    if value.consumer == task &&
      @execution.supplied_relation_read_matches_input(
        read,
        graph.owners_at(task).unwrap(),
        value.source_input,
      ) {
      if slot is Some(_) {
        return Err(ForeignCapture)
      }
      slot = Some(value.input)
    }
  }
  guard slot is Some(input) else { return Err(ForeignCapture) }
  let dependencies = match
    effect_dependency_ports(checked.computation, 4096, 65536, 64) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let captured = match
    open_checked_dag(graph, sources, ledger, [], supplied_reads=[
      (task, input, read),
    ]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for dependency in dependencies {
    captured.effect_dependency_outputs[dependency.task] = true
  }
  Ok({ checked, captured, })
}

///|
pub fn captured_effect_run_dag(value : CapturedEffectRunDAG) -> CapturedDAG {
  value.captured
}

///|
// The runtime keyed-input view is constructed from this exact checked Effect
// graph. Its added live input slot does not replace the preparation original.
// This nominal association conveys no input liveness, capacity or permission.
pub fn captured_effect_run_matches_preparation(
  value : CapturedEffectRunDAG,
  run : CapturedDAG,
  graph : CheckedDAG,
) -> Bool {
  physical_equal(value.captured, run) &&
  (
    physical_equal(checked_effect_run_graph(value.checked), graph) ||
    @graph.source_inputs_dag_matches_original(
      graph,
      checked_effect_run_graph(value.checked),
    )
  )
}

///|
pub fn captured_effect_run_owner(
  value : CapturedEffectRunDAG,
) -> @effect_binding.EffectProgramRunCandidate {
  value.checked.run
}

///|
/// Retain the checked source occurrence through capture without implying a
/// live read pin. Physical output availability is checked at each use-site.
pub fn captured_effect_run_source_count(value : CapturedEffectRunDAG) -> Int {
  value.checked.computation.sources_count()
}

///|
pub fn captured_effect_run_source_at(
  value : CapturedEffectRunDAG,
  index : Int,
) -> CheckedEffectSourcePort? {
  value.checked.computation.sources_at(index).bind(source => source)
}

///|
fn open_checked_dag(
  graph : CheckedDAG,
  captures : Array[(Int, @query.CapturedInputSource)],
  ledger : @resources.Ledger,
  supplied : Array[@execution.CapturedRows],
  completed? : Array[(Int, @execution.CompletedOutput)] = [],
  root_wire_bytes? : Int? = None,
  supplied_reads? : Array[(Int, Int, @execution.SuppliedRelationRead)] = [],
  retained_model? : (Int, Int, @execution.CompletedOutput)? = None,
  retained_models? : Array[(Int, Int, @execution.CompletedOutput)] = [],
  retained_source_tasks? : Array[(Int, @execution.CompletedOutput)] = [],
) -> Result[CapturedDAG, RunIssue] {
  let count = graph.owners_count()
  if count == 0 {
    return Err(UnsupportedGraph)
  }
  if captures.length() + completed.length() != graph.captured_prefix_value() {
    return Err(ForeignCapture)
  }
  let sources : Array[@query.CapturedInputSource?] = Array::make(count, None)
  for (task, captured) in captures {
    if task < 0 ||
      task >= graph.captured_prefix_value() ||
      sources[task] is Some(_) ||
      !@query.captured_source_matches(
        captured,
        @checked.source_identity(graph.program_value()),
        graph.owners_at(task).unwrap(),
      ) {
      return Err(ForeignCapture)
    }
    sources[task] = Some(captured)
  }
  let outputs : Array[CommittedTaskOutput?] = Array::make(count, None)
  for (task, output) in completed {
    if task < 0 ||
      task >= graph.captured_prefix_value() ||
      sources[task] is Some(_) ||
      outputs[task] is Some(_) ||
      !@execution.completed_output_available(output) {
      return Err(ForeignCapture)
    }
    guard graph.targets_at(task).unwrap() is Some(target) &&
      @execution.completed_output_matches_port(
        output,
        graph.owners_at(task).unwrap(),
        target,
      ) else {
      return Err(ForeignCapture)
    }
    outputs[task] = Some(Materialized(output))
  }
  let imported_root_statistics = match root_wire_bytes {
    None => None
    Some(canonical_wire_bytes) => {
      guard canonical_wire_bytes >= 0 &&
        outputs[0] is Some(Materialized(output)) else {
        return Err(ForeignCapture)
      }
      Some({
        rows: @execution.completed_row_count(output),
        canonical_wire_bytes,
      })
    }
  }
  let first_task = graph.captured_prefix_value()
  let input_counts = Array::makei(count, task => {
    graph.input_counts_at(task).unwrap()
  })
  let join_limits : Array[Array[(Int, Int64)]] = Array::makei(count, _ => [])
  let interval_search_limits : Array[Array[(Int, Int64)]] = Array::makei(
    count,
    _ => [],
  )
  let asof_search_limits : Array[Array[(Int, Int64)]] = Array::makei(count, _ => {
    []
  })
  let aggregate_limits : Array[Array[@connector.AggregateOutputCeiling]] = Array::makei(
    count,
    _ => [],
  )
  let analytic_envelopes : Array[Array[@connector.AnalyticEnvelope]] = Array::makei(
    count,
    _ => [],
  )
  // A restored Model task has already executed on its original retained
  // input. Its completion is not a newly completed keyed Source port.
  let retained_task = match retained_model {
    None => None
    Some((task, step, output)) => {
      guard task >= first_task &&
        task < count &&
        graph_keyed_model_plan_inputs_complete(graph, task, step) &&
        graph.targets_at(task).unwrap() is Some(target) &&
        @execution.completed_output_matches_port(
          output,
          graph.owners_at(task).unwrap(),
          target,
        ) &&
        @execution.completed_output_available(output) else {
        return Err(ForeignCapture)
      }
      outputs[task] = Some(Materialized(output))
      Some(task)
    }
  }
  // The closed plural Model caller supplies actual original completed
  // outputs, not planned supplied rows. Keep the scalar entrance unchanged.
  if retained_models.length() > count ||
    (retained_task is Some(_) && !retained_models.is_empty()) {
    return Err(ForeignCapture)
  }
  let retained_tasks : Array[Int] = []
  let mut retained_keyed_input = false
  for (task, step, output) in retained_models {
    guard task >= first_task &&
      task < count &&
      outputs[task] is None &&
      graph.targets_at(task).unwrap() is Some(target) &&
      @execution.completed_output_matches_port(
        output,
        graph.owners_at(task).unwrap(),
        target,
      ) &&
      @execution.completed_output_available(output) else {
      return Err(ForeignCapture)
    }
    outputs[task] = Some(Materialized(output))
    retained_tasks.push(task)
    if graph_keyed_model_plan_inputs_complete(graph, task, step) {
      retained_keyed_input = true
    }
  }
  for (task, output) in retained_source_tasks {
    guard task >= first_task &&
      task < count &&
      outputs[task] is None &&
      graph.targets_at(task).unwrap() is Some(target) &&
      @execution.completed_output_matches_port(
        output,
        graph.owners_at(task).unwrap(),
        target,
      ) &&
      @execution.completed_output_available(output) else {
      return Err(ForeignCapture)
    }
    outputs[task] = Some(Materialized(output))
    retained_tasks.push(task)
  }
  if !graph_ordered_inputs_complete(graph) &&
    retained_task is None &&
    !retained_keyed_input {
    return Err(UnsupportedGraph)
  }
  if supplied.length() + supplied_reads.length() != graph.supplied_slots_count() {
    return Err(UnsupportedGraph)
  }
  let supplied_inputs : Array[Array[@execution.CapturedRows?]] = Array::makei(
    count,
    task => Array::make(input_counts[task], None),
  )
  for rows in supplied {
    let mut matched = false
    for input in graph.supplied_slots_iter() {
      guard graph.owners_at(input.consumer) is Some(owner) else {
        return Err(UnsupportedGraph)
      }
      if physical_equal(@execution.captured_owner(rows), owner) &&
        @execution.captured_origin(rows) is @execution.SuppliedInput(index) &&
        index == input.source_input {
        if matched || supplied_inputs[input.consumer][input.input] is Some(_) {
          return Err(ForeignCapture)
        }
        supplied_inputs[input.consumer][input.input] = Some(rows)
        matched = true
      }
    }
    if !matched {
      return Err(ForeignCapture)
    }
  }
  let read_inputs : Array[Array[@execution.SuppliedRelationRead?]] = Array::makei(
    count,
    task => Array::make(input_counts[task], None),
  )
  for (task, port, read) in supplied_reads {
    if task < first_task ||
      task >= count ||
      port < 0 ||
      port >= input_counts[task] ||
      supplied_inputs[task][port] is Some(_) ||
      read_inputs[task][port] is Some(_) {
      return Err(ForeignCapture)
    }
    let mut selected : LocalInputSlot? = None
    for slot in graph.supplied_slots_iter() {
      if slot.consumer == task && slot.input == port {
        selected = Some(slot)
        break
      }
    }
    guard selected is Some(slot) &&
      @execution.supplied_relation_read_matches_input(
        read,
        graph.owners_at(task).unwrap(),
        slot.source_input,
      ) else {
      return Err(ForeignCapture)
    }
    if slot.operation_input is Some((step, operation_input)) &&
      !@execution.supplied_relation_read_matches_operation_input(
        read,
        graph.owners_at(task).unwrap(),
        step,
        operation_input,
      ) {
      return Err(ForeignCapture)
    }
    read_inputs[task][port] = Some(read)
  }
  for index in first_task..<count {
    let prepared = @lower.bound_preparation(graph.owners_at(index).unwrap())
    let pipeline = @lower.pipeline(prepared)
    if @pipeline.step_count(pipeline) == 0 {
      // An input-only Relation task uses the existing bounded copy provider.
      // Keep its exact checked port; other empty-task Carrier shapes are not
      // admitted by this execution profile.
      let target = @pipeline.Input(0)
      guard @pipeline.input_count(pipeline) == 1 &&
        graph.targets_at(index).unwrap() == Some(target) &&
        @lower.preparation_output_target(prepared) == Some(target) &&
        @lower.preparation_schema_at(prepared, target) is Some(_) else {
        return Err(UnsupportedGraph)
      }
    }
    // Accept owned tasks, not operation-name templates. Implementations reject
    // unsupported execution obligations before offering work.
    for requirement in graph.operations_iter_at(index).unwrap() {
      if requirement.disposition is ExecutionCheck(JoinOutputLimit(check)) {
        join_limits[index].push(
          (
            check.site.step,
            @step_bounds.join_limit_effective_maximum(check.limit),
          ),
        )
      }
      if requirement.disposition is ExecutionCheck(IntervalSearch(check)) {
        let step = check.site.step
        let upper = @step_bounds.interval_search_upper(check.product)
        let mut duplicate = false
        for (previous_step, previous_upper) in interval_search_limits[index] {
          if previous_step == step {
            if previous_upper != upper {
              return Err(UnsupportedGraph)
            }
            duplicate = true
          }
        }
        if !duplicate {
          interval_search_limits[index].push((step, upper))
        }
      }
      if requirement.disposition is ExecutionCheck(AsOfSearch(check)) {
        let step = check.site.step
        let upper = @step_bounds.asof_search_upper(check.product)
        let mut duplicate = false
        for (previous_step, previous_upper) in asof_search_limits[index] {
          if previous_step == step {
            if previous_upper != upper {
              return Err(UnsupportedGraph)
            }
            duplicate = true
          }
        }
        if !duplicate {
          asof_search_limits[index].push((step, upper))
        }
      }
      if requirement.disposition is ExecutionCheck(GroupExecution(check)) {
        let ceiling = match check.rule {
          EnforceArrayItems(limit) =>
            @connector.aggregate_output_ceiling(
              check.site.step,
              @context.group_array_limit_name(limit),
              @connector.array_items_output_unit(),
              @context.group_array_limit_maximum(limit),
            )
          EnforceStringBytes(limit) =>
            @connector.aggregate_output_ceiling(
              check.site.step,
              @context.group_string_limit_name(limit),
              @connector.string_bytes_output_unit(),
              @context.group_string_limit_maximum(limit),
            )
          _ => continue
        }
        guard ceiling is Ok(ceiling) else { return Err(UnsupportedGraph) }
        for previous in aggregate_limits[index] {
          if @connector.aggregate_output_ceiling_step(previous) ==
            @connector.aggregate_output_ceiling_step(ceiling) &&
            @connector.aggregate_output_ceiling_name(previous) ==
            @connector.aggregate_output_ceiling_name(ceiling) &&
            @connector.aggregate_output_ceiling_unit(previous) ==
            @connector.aggregate_output_ceiling_unit(ceiling) {
            return Err(UnsupportedGraph)
          }
        }
        aggregate_limits[index].push(ceiling)
      }
      if requirement.disposition is ExecutionCheck(NestItems(limit)) {
        let ceiling = @connector.aggregate_output_ceiling(
          requirement.site.step,
          @context.nest_item_limit_output_name(limit),
          @connector.array_items_output_unit(),
          @context.nest_item_limit_maximum(limit),
        )
        guard ceiling is Ok(ceiling) else { return Err(UnsupportedGraph) }
        for previous in aggregate_limits[index] {
          if @connector.aggregate_output_ceiling_step(previous) ==
            @connector.aggregate_output_ceiling_step(ceiling) &&
            @connector.aggregate_output_ceiling_name(previous) ==
            @connector.aggregate_output_ceiling_name(ceiling) &&
            @connector.aggregate_output_ceiling_unit(previous) ==
            @connector.aggregate_output_ceiling_unit(ceiling) {
            return Err(UnsupportedGraph)
          }
        }
        aggregate_limits[index].push(ceiling)
      }
      if requirement.disposition is ExecutionCheck(NestValues(check)) {
        let step = @context.nest_values_step(check)
        let name = @context.nest_values_output_name(check)
        let maximum = @context.nest_values_byte_ceiling(check)
        for
          unit in [
            @connector.nest_grouped_bytes_output_unit(),
            @connector.nest_attached_bytes_output_unit(),
          ] {
          let ceiling = @connector.aggregate_output_ceiling(
            step, name, unit, maximum,
          )
          guard ceiling is Ok(ceiling) else { return Err(UnsupportedGraph) }
          for previous in aggregate_limits[index] {
            if @connector.aggregate_output_ceiling_step(previous) == step &&
              @connector.aggregate_output_ceiling_name(previous) == name &&
              @connector.aggregate_output_ceiling_unit(previous) == unit {
              return Err(UnsupportedGraph)
            }
          }
          aggregate_limits[index].push(ceiling)
        }
      }
      if requirement.disposition is ExecutionCheck(AnalyticExecution(check)) {
        let ceiling = match check.rule {
          EnforceArrayItems(_, limit) =>
            @connector.aggregate_output_ceiling(
              check.site.step,
              @context.group_array_limit_name(limit),
              @connector.array_items_output_unit(),
              @context.group_array_limit_maximum(limit),
            )
          EnforceStringBytes(_, limit) =>
            @connector.aggregate_output_ceiling(
              check.site.step,
              @context.group_string_limit_name(limit),
              @connector.string_bytes_output_unit(),
              @context.group_string_limit_maximum(limit),
            )
          _ => continue
        }
        guard ceiling is Ok(ceiling) else { return Err(UnsupportedGraph) }
        for previous in aggregate_limits[index] {
          if @connector.aggregate_output_ceiling_step(previous) ==
            @connector.aggregate_output_ceiling_step(ceiling) &&
            @connector.aggregate_output_ceiling_name(previous) ==
            @connector.aggregate_output_ceiling_name(ceiling) &&
            @connector.aggregate_output_ceiling_unit(previous) ==
            @connector.aggregate_output_ceiling_unit(ceiling) {
            return Err(UnsupportedGraph)
          }
        }
        aggregate_limits[index].push(ceiling)
      }
      if requirement.disposition is ExecutionCheck(AnalyticEnvelope(check)) {
        let envelope = @connector.analytic_envelope(
          @context.analytic_envelope_step(check),
          @context.analytic_envelope_input_wire_bytes(check),
          @context.analytic_envelope_output_wire_bytes(check),
          @context.analytic_envelope_partition_wire_bytes(check),
          @context.analytic_envelope_frame_memberships(check),
          @context.analytic_envelope_output_rows(check),
        )
        guard envelope is Ok(envelope) else { return Err(UnsupportedGraph) }
        let mut duplicate = false
        for previous in analytic_envelopes[index] {
          if @connector.analytic_envelope_step(previous) ==
            @connector.analytic_envelope_step(envelope) {
            if @connector.analytic_envelope_input_wire_bytes(previous) !=
              @connector.analytic_envelope_input_wire_bytes(envelope) ||
              @connector.analytic_envelope_output_wire_bytes(previous) !=
              @connector.analytic_envelope_output_wire_bytes(envelope) ||
              @connector.analytic_envelope_partition_wire_bytes(previous) !=
              @connector.analytic_envelope_partition_wire_bytes(envelope) ||
              @connector.analytic_envelope_frame_memberships(previous) !=
              @connector.analytic_envelope_frame_memberships(envelope) ||
              @connector.analytic_envelope_output_rows(previous) !=
              @connector.analytic_envelope_output_rows(envelope) {
              return Err(UnsupportedGraph)
            }
            duplicate = true
          }
        }
        if !duplicate {
          analytic_envelopes[index].push(envelope)
        }
      }
    }
  }
  // Every physical producer exposes exactly its selected target. An ordinary
  // task still selects the final step; a segmented Carrier task retains its
  // original intermediate coordinate instead of relabeling it as final.
  for edge in graph.data_iter() {
    if edge.producer >= graph.captured_prefix_value() &&
      graph.targets_at(edge.producer).bind(value => value) != Some(edge.target) {
      return Err(UnsupportedGraph)
    }
  }
  let lifetimes = Array::makei(count, _ => TaskLifetime::{
    live: true,
    pins: 0,
  })
  let resources : Array[TaskRetention?] = Array::make(count, None)
  for task in 0..<graph.captured_prefix_value() {
    resources[task] = Some({
      holding: None,
      release_confirmed: fn() { true },
      cleanup_observation: CleanupReady,
      parents: [],
    })
  }
  let run : CapturedDAG = {
    graph,
    offer_owner: { graph, },
    original_sources: sources.copy(),
    imported_root_statistics,
    sources: Array::makei(count, task => {
      sources[task].map(captured => {
        let lifetime = lifetimes[task]
        @query.restrict_captured_source(captured, fn() {
          lifetime.live || lifetime.pins > 0
        })
      })
    }),
    ledger,
    outputs,
    done: Array::makei(count, task => {
      retained_task == Some(task) || retained_tasks.contains(task)
    }),
    lifetimes,
    effect_dependency_outputs: Array::make(count, false),
    resources,
    join_limits,
    interval_search_limits,
    asof_search_limits,
    aggregate_limits,
    analytic_envelopes,
    inputs: Array::makei(count, task => {
      Array::make(
        if task < graph.captured_prefix_value() {
          0
        } else {
          graph.input_counts_at(task).unwrap()
        },
        None,
      )
    }),
    supplied: supplied_inputs,
    supplied_reads: read_inputs,
    stopped: false,
    failure: None,
    running: None,
    executions: Array::make(count, None),
    resident_environments: [],
    generation: 0,
    search: None,
    revisions: 0,
    searched_generation: None,
    searched_resources: None,
    strategy: None,
    search_report: [],
    search_report_complete: false,
    revision_history: [],
    managed_publication_identity: false,
    managed_consumer_identity: false,
    managed_host_identity: false,
    managed_identity_policy_sealed: false,
    managed_selections: Array::make(count, None),
    activation_required: false,
    activation_grant: None,
  }
  if retained_task is Some(task) {
    // This is a borrowed completion. Its actual Model execution keeps its
    // allocation and output-use pin; this DAG neither charges it twice nor
    // acknowledges that owner's physical cleanup.
    resources[task] = Some({
      holding: None,
      release_confirmed: fn() { true },
      cleanup_observation: CleanupReady,
      parents: task_parents(run, task),
    })
  }
  for task in retained_tasks {
    resources[task] = Some({
      holding: None,
      release_confirmed: fn() { true },
      cleanup_observation: CleanupReady,
      parents: task_parents(run, task),
    })
  }
  for (task, port, read) in supplied_reads {
    let lifetime = lifetimes[task]
    run.supplied_reads[task][port] = Some(
      @execution.restrict_supplied_relation_read(read, fn() {
        lifetime.live && !run.done[task] && !run.stopped
      }),
    )
  }
  Ok(run)
}

///|
/// Commit the common Host's managed-candidate decision for the next task.
/// Candidate support/preparation stays side-effect free; only this boundary
/// fixes which registered realization may enter the existing task lifecycle.
pub fn select_captured_managed_registration(
  run : CapturedDAG,
  task : Int,
  registration : @connector.CapabilityRegistration,
) -> Result[Unit, RunIssue] {
  if run.stopped ||
    next_captured_task(run) != Some(task) ||
    run.running is Some(_) ||
    !@connector.capability_registration_available(registration) {
    return Err(NotReady)
  }
  match run.managed_selections.get(task) {
    None => Err(ForeignCandidate)
    Some(Some(selected)) =>
      if physical_equal(selected, registration) {
        Ok(())
      } else {
        Err(ForeignCandidate)
      }
    Some(None) => {
      run.managed_selections[task] = Some(registration)
      Ok(())
    }
  }
}

///|
/// Whether checked root Results require acquisition publication identity.
/// Managed Compute publication does not own that capability.
pub fn graph_requires_acquisition_result_publication(
  graph : CheckedDAG,
) -> Bool {
  graph
  .results_iter()
  .any(result => result.task < graph.captured_prefix_value())
}

///|
/// Install the Host-owned logical-identity policy before any managed request is
/// prepared. Program text and connector code cannot weaken this policy later.
pub fn configure_captured_managed_identity_policy(
  run : CapturedDAG,
  publish_checked_results : Bool,
  publication : Bool,
  consumer : Bool,
  host_policy : Bool,
) -> Bool {
  let mut started = false
  for index in captured_compute_first_task(run)..<run.done.length() {
    if run.done[index] {
      started = true
    }
  }
  if run.managed_identity_policy_sealed || run.running is Some(_) || started {
    return false
  }
  // This policy is for the Effect-free Result publication path. An Effectful
  // Run must close its Preview, apply and final Receipt separately.
  if publish_checked_results && graph_program_has_effects(run.graph) {
    return false
  }
  // Acquisition publication needs its own observation/receipt identity
  // capability. This managed Compute increment must reject that requirement
  // before comparing or starting any Compute candidate.
  let publication_required = publish_checked_results || publication
  if publication_required &&
    graph_requires_acquisition_result_publication(run.graph) {
    return false
  }
  run.managed_publication_identity = publication_required
  run.managed_consumer_identity = consumer
  run.managed_host_identity = host_policy
  run.managed_identity_policy_sealed = true
  true
}

///|
/// Derive the next task's obligations from checked graph destinations, known
/// consumers and the installed Host policy. Connectors receive this opaque
/// value and may reject it, but cannot replace it with process-local defaults.
pub fn captured_next_managed_obligations(
  run : CapturedDAG,
  max_entries : Int,
) -> Result[@execution.ManagedObligations, @execution.ManagedObligationIssue] {
  guard next_captured_task(run) is Some(task) &&
    run.graph.owners_at(task) is Some(owner) else {
    return Err(@execution.InvalidLimits)
  }
  run.managed_identity_policy_sealed = true
  let mut has_consumer = false
  for edge in run.graph.data_iter() {
    if edge.producer == task {
      has_consumer = true
      break
    }
  }
  // Check the exact retained identity inventory before allocating its arrays.
  if max_entries < 0 {
    return Err(@execution.InvalidLimits)
  }
  let mut result_count = 0
  for result in run.graph.results_iter() {
    if result.task == task {
      result_count += 1
    }
  }
  let task_identity = has_consumer ||
    result_count == 0 ||
    run.managed_host_identity
  let required = result_count.to_int64() *
    (if run.managed_publication_identity { 1L } else { 0L }) +
    (if task_identity { 1L } else { 0L })
  if required > max_entries.to_int64() {
    return Err(@execution.InvalidLimits)
  }
  let result_occurrences = run.graph
    .results_iter()
    .filter_map(result => {
      if result.task == task {
        Some(result.occurrence)
      } else {
        None
      }
    })
    .to_array()
  // A requested publication is resolved only through checked root Results,
  // even when the same producer also has graph consumers. Merely having no
  // consumer is never publication evidence.
  let publication_required = run.managed_publication_identity &&
    !result_occurrences.is_empty()
  let consumer_required = run.managed_consumer_identity && has_consumer
  let identities : Array[@execution.ManagedIdentityRequirement] = []
  if has_consumer || result_occurrences.is_empty() || run.managed_host_identity {
    identities.push({
      domain: @execution.OrderedRows,
      subject: @execution.TaskOutput,
      occurrence: None,
      need: if consumer_required {
        @execution.EstablishedBy(@execution.BeforeCidOperation)
      } else if run.managed_host_identity {
        @execution.EstablishedBy(@execution.BeforeDiscard)
      } else {
        @execution.UnestablishedRetained
      },
    })
  }
  if publication_required {
    for occurrence in result_occurrences {
      identities.push({
        domain: @execution.LogicalRelation,
        subject: @execution.NamedResult,
        occurrence: Some(occurrence),
        need: @execution.EstablishedBy(@execution.BeforePublication),
      })
    }
  }
  @execution.prepare_managed_obligations(
    owner,
    identities,
    if publication_required || run.managed_host_identity {
      @execution.LogicalContentAddressed
    } else {
      @execution.ManagedUse
    },
    if consumer_required || run.managed_host_identity {
      @execution.LogicalContentIdentity
    } else {
      @execution.MaterialBinding
    },
    max_entries,
  )
}

///|
pub fn captured_root_statistics(
  run : CapturedDAG,
) -> @query.CapturedSourceStatistics? {
  run.sources
  .get(0)
  .bind(source => source)
  .bind(source => @query.captured_source_statistics(source))
}

///|
/// Statistics of the independently admitted execution root. An imported
/// completed output is not a Source capture or acquisition observation.
pub struct CapturedExecutionRootStatistics {
  rows : Int
  canonical_wire_bytes : Int
}

///|
pub fn captured_execution_root_statistics(
  run : CapturedDAG,
) -> CapturedExecutionRootStatistics? {
  if run.stopped {
    return None
  }
  match run.imported_root_statistics {
    Some(statistics) => {
      guard materialized_task_output(run, 0) is Some(output) &&
        @execution.completed_output_available(output) else {
        return None
      }
      Some(statistics)
    }
    None =>
      captured_root_statistics(run).map(statistics => {
        rows: statistics.rows,
        canonical_wire_bytes: statistics.canonical_wire_bytes,
      })
  }
}

///|
pub fn captured_dag_graph(run : CapturedDAG) -> CheckedDAG {
  run.graph
}

///|
/// Exact final port of an admitted Compute task, including before execution.
/// Captured acquisition is accessed through its source, not this port accessor.
pub fn captured_task_target(run : CapturedDAG, task : Int) -> @pipeline.Target? {
  if task < 0 || task >= run.graph.owners_count() {
    return None
  }
  run.graph.targets_at(task).unwrap()
}

///|
pub fn captured_dag_strategy(run : CapturedDAG) -> StrategyRevision? {
  run.strategy
}

///|
fn task_done(run : CapturedDAG, index : Int) -> Bool {
  index < run.graph.captured_prefix_value() || run.done[index]
}

///|
/// Index of the first task requiring Compute; a captured acquisition is
/// already complete and is never submitted as Compute.
pub fn captured_compute_first_task(run : CapturedDAG) -> Int {
  run.graph.captured_prefix_value()
}

///|
/// Checked task completion survives release of its retained output port.
pub fn captured_task_completed(run : CapturedDAG, task : Int) -> Bool {
  task >= 0 && task < run.done.length() && task_done(run, task)
}

///|
pub fn next_captured_task(run : CapturedDAG) -> Int? {
  if run.stopped || run.running is Some(_) || resident_provision_pending(run) {
    return None
  }
  next_dependency_ready_task(
    run.graph,
    task => task_done(run, task),
    first_task=captured_compute_first_task(run),
  )
}

///|
/// Bind only a completed, exact predecessor output. The source's live condition
/// remains attached to pending reads; successful downstream output is independent.
pub fn captured_task_input(
  run : CapturedDAG,
  task : Int,
  max_entries : Int,
  max_name_bytes : Int,
  input_index? : Int = 0,
) -> Result[@execution.ProducerRead, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if next_captured_task(run) != Some(task) {
    return Err(NotReady)
  }
  if input_index < 0 || input_index >= run.inputs[task].length() {
    return Err(NotReady)
  }
  if run.inputs[task][input_index] is Some(read) {
    if !@execution.producer_read_available(read) {
      let issue = RunIssue::Read(@execution.ProducerUnavailable)
      fail_captured_task(run, task, issue)
      return Err(issue)
    }
    return Ok(read)
  }
  let mut selected : DataEdge? = None
  for edge in run.graph.data_iter() {
    if edge.consumer == task && edge.input == input_index {
      selected = Some(edge)
      break
    }
  }
  guard selected is Some(edge) else { return Err(NotReady) }
  let receiver = run.graph.owners_at(task).unwrap()
  let receiver_input = edge.source_input.unwrap_or(edge.input)
  let bound = if edge.producer < run.graph.captured_prefix_value() &&
    run.sources[edge.producer] is Some(source) {
    let binding = match (edge.operation_input, edge.source_input) {
      (Some((step, operation_input)), None) =>
        @query.bind_captured_source_operation(
          source, receiver, step, operation_input,
        )
      _ => @query.bind_captured_source(source, receiver, receiver_input)
    }
    match binding {
      Ok(bound) => bound
      Err(issue) => {
        fail_captured_task(run, task, Capture(issue))
        return Err(Capture(issue))
      }
    }
  } else {
    guard captured_task_output(run, edge.producer, edge.target) is Some(output) else {
      fail_captured_task(run, task, MissingOutput)
      return Err(MissingOutput)
    }
    let binding = match (edge.operation_input, edge.source_input) {
      (Some((step, operation_input)), None) =>
        @execution.bind_completed_operation_input(
          receiver,
          step,
          operation_input,
          run.graph.owners_at(edge.producer).unwrap(),
          output,
        )
      _ =>
        @execution.bind_completed_input(
          receiver,
          receiver_input,
          run.graph.owners_at(edge.producer).unwrap(),
          output,
        )
    }
    match binding {
      Ok(bound) => bound
      Err(issue) => {
        fail_captured_task(run, task, Binding(issue))
        return Err(Binding(issue))
      }
    }
  }
  match
    @execution.prepare_producer_read(
      receiver, bound, max_entries, max_name_bytes,
    ) {
    Ok(read) => {
      run.inputs[task][input_index] = Some(read)
      Ok(read)
    }
    Err(issue) => {
      fail_captured_task(run, task, Read(issue))
      Err(Read(issue))
    }
  }
}

///|
/// Bind one Host-supplied Local input without manufacturing a producer task.
/// The read remains live only while its receiving task is pending in this Run.
pub fn captured_supplied_task_input(
  run : CapturedDAG,
  task : Int,
  input_index? : Int = 0,
) -> Result[@execution.SuppliedRelationRead, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if next_captured_task(run) != Some(task) ||
    input_index < 0 ||
    input_index >= run.supplied[task].length() {
    return Err(NotReady)
  }
  if run.supplied_reads[task][input_index] is Some(read) {
    if !@execution.supplied_relation_read_available(read) {
      let issue = RunIssue::Read(@execution.ProducerUnavailable)
      fail_captured_task(run, task, issue)
      return Err(issue)
    }
    return Ok(read)
  }
  guard run.supplied[task][input_index] is Some(rows) else {
    return Err(NotReady)
  }
  let lifetime = run.lifetimes[task]
  let mut source_input = None
  for input in run.graph.supplied_slots_iter() {
    if input.consumer == task && input.input == input_index {
      source_input = Some(input.source_input)
      break
    }
  }
  guard source_input is Some(source_input) else {
    let failure = RunIssue::ForeignCandidate
    fail_captured_task(run, task, failure)
    return Err(failure)
  }
  match
    @execution.prepare_supplied_relation_read(
      run.graph.owners_at(task).unwrap(),
      source_input,
      rows,
      fn() { lifetime.live && !run.done[task] && !run.stopped },
    ) {
    Ok(read) => {
      run.supplied_reads[task][input_index] = Some(read)
      Ok(read)
    }
    Err(issue) => {
      let failure = RunIssue::Read(issue)
      fail_captured_task(run, task, failure)
      Err(failure)
    }
  }
}

///|
/// Prepare one typed managed input at the exact ready graph edge. The caller
/// must supply the concrete Host-owned output that matches the graph's opaque
/// completed occurrence. This creates a use-site binding only; dispatch still
/// requires Store pin, current authority and resource admission.
pub fn[T] captured_managed_task_input(
  run : CapturedDAG,
  task : Int,
  output : @execution.ManagedCompletedOutput[T],
  max_entries : Int,
  max_name_bytes : Int,
  input_index? : Int = 0,
) -> Result[@execution.ManagedProducerRead[T], RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if next_captured_task(run) != Some(task) ||
    input_index < 0 ||
    input_index >= run.inputs[task].length() {
    return Err(NotReady)
  }
  let mut selected : DataEdge? = None
  for edge in run.graph.data_iter() {
    if edge.consumer == task && edge.input == input_index {
      selected = Some(edge)
      break
    }
  }
  guard selected is Some(edge) &&
    edge.producer >= run.graph.captured_prefix_value() &&
    captured_managed_task_output_matches(
      run,
      edge.producer,
      edge.target,
      output,
    ) else {
    let issue = RunIssue::MissingOutput
    fail_captured_task(run, task, issue)
    return Err(issue)
  }
  let prepared = match edge.operation_input {
    Some((consumer_step, operation_input)) =>
      match
        @lower.node_input_target(
          @lower.node_at(
            @lower.bound_preparation(run.graph.owners_at(task).unwrap()),
            consumer_step,
          ).unwrap(),
          operation_input,
        ) {
        Some(@pipeline.Step(_)) =>
          @execution.prepare_managed_operation_read(
            run.graph.owners_at(task).unwrap(),
            consumer_step,
            operation_input,
            run.graph.owners_at(edge.producer).unwrap(),
            output,
            max_entries,
          )
        _ =>
          @execution.prepare_managed_producer_read(
            run.graph.owners_at(task).unwrap(),
            edge.source_input.unwrap_or(input_index),
            run.graph.owners_at(edge.producer).unwrap(),
            output,
            max_entries,
            max_name_bytes,
          )
      }
    None =>
      @execution.prepare_managed_producer_read(
        run.graph.owners_at(task).unwrap(),
        edge.source_input.unwrap_or(input_index),
        run.graph.owners_at(edge.producer).unwrap(),
        output,
        max_entries,
        max_name_bytes,
      )
  }
  match prepared {
    Ok(read) => Ok(read)
    Err(Binding(issue)) => {
      let failure = RunIssue::Binding(issue)
      fail_captured_task(run, task, failure)
      Err(failure)
    }
    Err(View(issue)) => {
      let failure = RunIssue::Read(issue)
      fail_captured_task(run, task, failure)
      Err(failure)
    }
  }
}

///|
/// Prepare one non-Relation Carrier input at the exact ready graph edge. The
/// typed Carrier runtime remains responsible for payload access; this common
/// layer verifies only the checked edge and the type-erased use-site proof.
pub fn captured_carrier_managed_task_input(
  run : CapturedDAG,
  task : Int,
  output : @execution.CarrierManagedCompletedOutput,
  carrier_read : @managed_carrier.ProducerReadReference,
  input_index? : Int = 0,
) -> Result[@execution.CarrierManagedProducerRead, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if next_captured_task(run) != Some(task) ||
    input_index < 0 ||
    input_index >= run.inputs[task].length() {
    return Err(NotReady)
  }
  let mut selected : DataEdge? = None
  for edge in run.graph.data_iter() {
    if edge.consumer == task && edge.input == input_index {
      selected = Some(edge)
      break
    }
  }
  guard selected is Some(edge) &&
    edge.producer >= run.graph.captured_prefix_value() &&
    captured_carrier_managed_task_output_matches(
      run,
      edge.producer,
      edge.target,
      output,
    ) else {
    let issue = RunIssue::MissingOutput
    fail_captured_task(run, task, issue)
    return Err(issue)
  }
  let prepared = match edge.operation_input {
    Some((consumer_step, operation_input)) =>
      @execution.prepare_carrier_managed_operation_read(
        run.graph.owners_at(task).unwrap(),
        consumer_step,
        operation_input,
        run.graph.owners_at(edge.producer).unwrap(),
        output,
        carrier_read,
      )
    None =>
      @execution.prepare_carrier_managed_producer_read(
        run.graph.owners_at(task).unwrap(),
        edge.source_input.unwrap_or(input_index),
        run.graph.owners_at(edge.producer).unwrap(),
        output,
        carrier_read,
      )
  }
  match prepared {
    Ok(read) => Ok(read)
    Err(_) => {
      let failure = RunIssue::ForeignCandidate
      fail_captured_task(run, task, failure)
      Err(failure)
    }
  }
}

///|
/// Exact producers of the next managed task in receiving input-port order.
/// Missing or incomplete topology returns an empty set. Producer zero denotes
/// the exact Acquisition output; concrete ordinary or managed completions are
/// still checked independently during preparation.
pub fn captured_next_managed_producers(run : CapturedDAG) -> Array[Int] {
  guard next_captured_task(run) is Some(task) && !run.inputs[task].is_empty() else {
    return []
  }
  let producers = Array::make(run.inputs[task].length(), -2)
  for edge in run.graph.data_iter() {
    if edge.consumer == task &&
      edge.input >= 0 &&
      edge.input < producers.length() &&
      edge.producer >= 0 {
      producers[edge.input] = edge.producer
    }
  }
  for input in run.graph.supplied_slots_iter() {
    if input.consumer == task &&
      input.input >= 0 &&
      input.input < producers.length() &&
      producers[input.input] == -2 {
      // -1 is the explicit Host-supplied Local input marker. It is not a task.
      producers[input.input] = -1
    }
  }
  if producers.any(producer => producer < -1) {
    []
  } else {
    producers
  }
}

///|
/// Original checked operation coordinate for one next-task physical input.
pub fn captured_next_managed_operation_input(
  run : CapturedDAG,
  input_index : Int,
) -> (Int, Int)? {
  guard next_captured_task(run) is Some(task) else { return None }
  for edge in run.graph.data_iter() {
    if edge.consumer == task && edge.input == input_index {
      return edge.operation_input
    }
  }
  for slot in run.graph.supplied_slots_iter() {
    if slot.consumer == task && slot.input == input_index {
      return slot.operation_input
    }
  }
  None
}

///|
/// Exact checked input-port count for the next managed task. Unlike the
/// producer list, zero distinguishes a legitimate source-free operation from
/// an incomplete topology for a task that requires inputs.
pub fn captured_next_managed_input_count(run : CapturedDAG) -> Int? {
  guard next_captured_task(run) is Some(task) else { return None }
  run.graph.input_counts_at(task)
}

///|
/// Compatibility accessor for callers that intentionally support unary tasks.
pub fn captured_next_managed_producer(run : CapturedDAG) -> Int? {
  let producers = captured_next_managed_producers(run)
  if producers.length() == 1 {
    Some(producers[0])
  } else {
    None
  }
}

///|
/// Completed internal producers whose last checked consumer has finished.
/// Sink results remain live for the caller. A Stage publication is the checked
/// port used by graph edges, not normally an external-retention obligation.
/// Checked Effect dependency Results remain owned until explicit release or
/// Run cleanup; finishing a Compute consumer does not finish that obligation.
/// This is exact graph liveness, not GC or permission to discard a sink.
pub fn captured_releasable_managed_producers(run : CapturedDAG) -> Array[Int] {
  let released = []
  for producer in 1..<run.done.length() {
    if !run.done[producer] ||
      !run.lifetimes[producer].live ||
      run.effect_dependency_outputs[producer] ||
      run.graph.results_iter().any(result => result.task == producer) ||
      (
        managed_task_output_reference(run, producer) is None &&
        carrier_managed_task_output_reference(run, producer) is None
      ) {
      continue
    }
    let mut has_consumer = false
    let mut needed = false
    for edge in run.graph.data_iter() {
      if edge.producer == producer {
        has_consumer = true
        if !run.done[edge.consumer] {
          needed = true
        }
      }
    }
    if has_consumer && !needed {
      released.push(producer)
    }
  }
  released
}

///|
/// No callback can inject arbitrary CompletedOutput as a task success.
/// The selected synchronous realization supplies execution, never a backend tag.
pub fn execute_captured_synchronous_task(
  run : CapturedDAG,
  task : Int,
  compute : @connector.SynchronousCompute,
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if next_captured_task(run) != Some(task) {
    return Err(NotReady)
  }
  if !consume_task_activation(run, task) {
    return Err(ActivationNotAuthorized)
  }
  let request = @connector.fixed_compute_candidate_request(
    @connector.synchronous_compute_candidate(compute),
  )
  if !strategy_candidate_matches(
      run,
      task,
      @connector.synchronous_compute_candidate(compute),
    ) {
    return Err(ForeignCandidate)
  }
  if !captured_request_inputs_match(run, task, request) {
    return Err(ForeignCandidate)
  }
  if !@connector.synchronous_compute_available(compute) {
    return Err(Compute(NotSelected))
  }
  for (step, required) in run.join_limits[task] {
    guard @connector.synchronous_compute_join_output_ceiling(compute, step)
      is Some(actual) &&
      actual <= required else {
      return Err(ForeignCandidate)
    }
  }
  if !aggregate_output_limits_satisfied(run.aggregate_limits[task], (
      step,
      name,
      unit,
    ) => {
      @connector.synchronous_compute_aggregate_output_ceiling(
        compute, step, name, unit,
      )
    }) {
    return Err(ForeignCandidate)
  }
  if !analytic_envelopes_satisfied(run.analytic_envelopes[task], step => {
      @connector.synchronous_compute_analytic_envelope(compute, step)
    }) {
    return Err(ForeignCandidate)
  }
  let capacity = @connector.synchronous_compute_capacity(compute)
  if strategy_task_envelope(run, task) is Some(selected) &&
    (
      capacity.retained_bytes > selected.retained_bytes ||
      capacity.execution_bytes > selected.execution_bytes
    ) {
    return Err(Physical(InvalidCharge))
  }
  let reservation = match
    @resources.reserve_attempt(
      run.ledger,
      0L,
      capacity.retained_bytes,
      capacity.execution_bytes,
      quantities=@resources.quantity_neutral_amounts(run.ledger),
    ) {
    Ok(reservation) => reservation
    Err(issue) => return Err(Physical(issue))
  }
  // Reserve the holding record before calculation too: a successful computation
  // must not discover afterward that its result cannot be retained.
  let holding = match
    @resources.retain_allocation(
      run.ledger,
      reservation,
      capacity.retained_bytes,
    ) {
    Ok(holding) => holding
    Err(issue) => {
      @resources.settle_reservation(run.ledger, reservation) |> ignore
      return Err(Physical(issue))
    }
  }
  let entry_issue : Ref[@resources.LedgerIssue?] = Ref(None)
  match
    @connector.execute_synchronous_compute(compute, enter=() => {
      match @resources.consume_reserved_attempt(run.ledger, reservation) {
        Ok(_) => true
        Err(issue) => {
          entry_issue.val = Some(issue)
          false
        }
      }
    }) {
    Ok(output) => {
      match
        commit_materialized_task_output(
          run,
          task,
          output,
          holding,
          MissingOutput,
          reservation,
          capacity.retained_bytes,
          0L,
        ) {
        Err(issue) => {
          @resources.release_allocation(run.ledger, holding) |> ignore
          @resources.settle_reservation(run.ledger, reservation) |> ignore
          fail_captured_task(run, task, issue)
          return Err(issue)
        }
        Ok(_) => ()
      }
      Ok(())
    }
    Err(issue) => {
      let failure : RunIssue = match entry_issue.val {
        Some(issue) => Physical(issue)
        None =>
          match issue {
            Compute(issue) => Compute(issue)
            MissingOutput => MissingOutput
          }
      }
      @resources.release_allocation(run.ledger, holding) |> ignore
      @resources.settle_reservation(run.ledger, reservation) |> ignore
      fail_captured_task(run, task, failure)
      Err(failure)
    }
  }
}

///|
/// Internal completed calculation only, not authority to publish a failed Program.
pub fn captured_task_output(
  run : CapturedDAG,
  task : Int,
  target : @pipeline.Target,
) -> @execution.CompletedOutput? {
  if captured_task_target(run, task) != Some(target) ||
    !run.lifetimes[task].live {
    return None
  }
  let output = materialized_task_output(run, task)
  let lifetime = run.lifetimes[task]
  output.map(output => {
    @execution.restrict_completed_output(output, fn() { lifetime.live })
  })
}

///|
/// Match the exact managed completed occurrence owned by this graph task.
/// This grants no read pin or use authority; the typed output is still checked
/// when preparing each downstream use-site.
pub fn[T] captured_managed_task_output_matches(
  run : CapturedDAG,
  task : Int,
  target : @pipeline.Target,
  output : @execution.ManagedCompletedOutput[T],
) -> Bool {
  if captured_task_target(run, task) != Some(target) ||
    !run.lifetimes[task].live {
    return false
  }
  managed_task_output_reference(run, task)
  .map(reference => {
    @execution.managed_completed_reference_matches(reference, output)
  })
  .unwrap_or(false)
}

///|
/// Match an exact non-Relation Carrier completion owned by a graph task. This
/// grants neither typed payload access nor authority to retain the output.
pub fn captured_carrier_managed_task_output_matches(
  run : CapturedDAG,
  task : Int,
  target : @pipeline.Target,
  output : @execution.CarrierManagedCompletedOutput,
) -> Bool {
  if captured_task_target(run, task) != Some(target) ||
    !run.lifetimes[task].live {
    return false
  }
  carrier_managed_task_output_reference(run, task)
  .map(reference => {
    @execution.carrier_managed_completed_reference_matches(reference, output)
  })
  .unwrap_or(false)
}

///|
/// Stops new work without revoking independent successful calculation results or
/// closing the caller-owned capture. In-flight asynchronous cleanup is separate.
pub fn stop_captured_dag(run : CapturedDAG) -> Unit {
  run.stopped = true
  run.activation_grant = None
  if run.running is Some((_, execution)) {
    // Revocation is not stop acknowledgement. The Host still owns cleanup.
    task_execution_cancel(execution)
  }
  for index in 0..<run.inputs.length() {
    clear_captured_inputs(run, index)
    // Each supplied Read is restricted by a closure over this same DAG.
    // Stop already revoked that gate and cancelled the original execution;
    // remove only our cached borrow instead of keeping the reciprocal root.
    // An active child retains its own admitted inputs until actual cleanup.
    // The Source owner still owns the original Read, bytes and physical ACK.
    for port in 0..<run.supplied_reads[index].length() {
      run.supplied_reads[index][port] = None
    }
  }
}

///|
fn fail_captured_task(run : CapturedDAG, task : Int, issue : RunIssue) -> Unit {
  if run.failure is None {
    run.failure = Some((task, issue))
  }
  stop_captured_dag(run)
}

///|
/// First primary failure is retained even when later cleanup requests stop again.
pub fn captured_dag_failure(run : CapturedDAG) -> (Int, RunIssue)? {
  run.failure
}

///|
/// One persistent Host ledger for the run, never replaced by a task choice.
pub fn captured_dag_ledger(run : CapturedDAG) -> @resources.Ledger {
  run.ledger
}

///|
/// Host-private execution progress, including changes to retained physical
/// copies. This is not a semantic identity or permission to reset search.
pub fn captured_dag_generation(run : CapturedDAG) -> Int {
  run.generation
}

///|
fn clear_captured_inputs(run : CapturedDAG, task : Int) -> Unit {
  for port in 0..<run.inputs[task].length() {
    run.inputs[task][port] = None
  }
}

///|
fn captured_request_inputs_match(
  run : CapturedDAG,
  task : Int,
  request : @connector.FixedComputeRequest,
) -> Bool {
  let ports = run.inputs[task]
  if @connector.fixed_compute_request_input_count(request) != ports.length() {
    return false
  }
  for port in 0..<ports.length() {
    guard @connector.fixed_compute_request_input(request, port)
      is Some(expected) else {
      return false
    }
    match expected {
      @execution.CompletedRelation(actual) => {
        guard ports[port] is Some(bound) &&
          run.supplied_reads[task][port] is None &&
          @execution.producer_read_same_binding(actual, bound) else {
          return false
        }
      }
      @execution.SuppliedRelation(actual) => {
        guard ports[port] is None &&
          run.supplied_reads[task][port] is Some(bound) &&
          @execution.supplied_relation_read_same_binding(actual, bound) else {
          return false
        }
      }
    }
  }
  true
}

///|
/// Completion records the exact bound ports that were selected at start. This
/// identity check is independent of backend attempt or transport types.
fn captured_output_inputs_match(
  run : CapturedDAG,
  task : Int,
  output : @execution.CompletedOutput,
) -> Bool {
  let mixed : Array[@execution.FixedRelationRead] = []
  let mut supplied = false
  for port in 0..<run.inputs[task].length() {
    if run.inputs[task][port] is Some(read) &&
      run.supplied_reads[task][port] is None {
      mixed.push(@execution.fixed_completed_relation_read(read))
    } else if run.inputs[task][port] is None &&
      run.supplied_reads[task][port] is Some(read) {
      supplied = true
      mixed.push(@execution.fixed_supplied_relation_read(read))
    } else {
      return false
    }
  }
  if supplied {
    return @execution.completed_output_matches_fixed_inputs(
      output,
      graph_task_selected_step(run.graph, task),
      mixed,
    )
  }
  let inputs = []
  for input in run.inputs[task] {
    guard input is Some(input) else { return false }
    inputs.push(input)
  }
  match graph_task_selected_step(run.graph, task) {
    Some(step) =>
      @execution.completed_output_matches_operation_inputs(output, step, inputs)
    None => @execution.completed_output_matches_inputs(output, inputs)
  }
}

///|
/// Verify an ordered mixture of managed Relation and Carrier use sites against
/// the exact producer occurrences retained by the common graph.
fn captured_mixed_managed_inputs_match(
  run : CapturedDAG,
  task : Int,
  inputs : Array[@execution.ManagedInputBinding],
) -> Bool {
  if task < captured_compute_first_task(run) ||
    task >= run.inputs.length() ||
    inputs.length() != run.inputs[task].length() {
    return false
  }
  for port, input in inputs {
    let mut selected : DataEdge? = None
    for edge in run.graph.data_iter() {
      if edge.consumer == task && edge.input == port {
        selected = Some(edge)
        break
      }
    }
    let mut operation = selected.bind(edge => edge.operation_input)
    if operation is None {
      for slot in run.graph.supplied_slots_iter() {
        if slot.consumer == task && slot.input == port {
          operation = slot.operation_input
          break
        }
      }
    }
    let position_matches = match operation {
      Some((step, operation_input)) =>
        @execution.managed_input_binding_matches_operation_input(
          input,
          run.graph.owners_at(task).unwrap(),
          step,
          operation_input,
        )
      None =>
        @execution.managed_input_binding_matches_input(
          input,
          run.graph.owners_at(task).unwrap(),
          port,
        )
    }
    if !position_matches {
      return false
    }
    let supplied_matches = run.supplied_reads[task][port]
      .map(read => {
        @execution.managed_input_binding_matches_supplied_read(input, read)
      })
      .unwrap_or(false)
    if selected is None {
      if !supplied_matches {
        return false
      }
      continue
    }
    let edge = selected.unwrap()
    guard edge.producer >= 0 else { return false }
    let ordinary_matches = run.inputs[task][port]
      .map(read => {
        @execution.managed_input_binding_matches_ordinary_read(input, read)
      })
      .unwrap_or(false)
    let relation_matches = managed_task_output_reference(run, edge.producer)
      .map(reference => {
        @execution.managed_input_binding_matches_relation_reference(
          input, reference,
        )
      })
      .unwrap_or(false)
    let carrier_matches = carrier_managed_task_output_reference(
        run,
        edge.producer,
      )
      .map(reference => {
        @execution.managed_input_binding_matches_carrier_reference(
          input, reference,
        )
      })
      .unwrap_or(false)
    let matches = (if ordinary_matches { 1 } else { 0 }) +
      (if relation_matches { 1 } else { 0 }) +
      (if carrier_matches { 1 } else { 0 }) +
      (if supplied_matches { 1 } else { 0 })
    if matches != 1 {
      return false
    }
  }
  true
}

///|
/// Read the already-owned application, never reconstruct a limit from a CID or
/// substitute the Host's execution settings for the selected checked contract.
/// The selected checked limit, not an estimate inferred from input row counts.
pub fn captured_task_join_output_limit(
  run : CapturedDAG,
  task : Int,
  step : Int,
) -> Int64? {
  run.join_limits
  .get(task)
  .bind(values => {
    for (position, claim) in values {
      if position == step {
        return Some(claim)
      }
    }
    None
  })
  .map(limit => limit)
}

///|
pub fn captured_task_join_output_count(run : CapturedDAG, task : Int) -> Int? {
  run.join_limits.get(task).map(items => items.length())
}

///|
pub fn captured_task_join_output_at(
  run : CapturedDAG,
  task : Int,
  index : Int,
) -> (Int, Int64)? {
  run.join_limits.get(task).bind(items => items.get(index)).map(pair => pair)
}

///|
/// Selected checked interval-search bounds, retained by exact occurrence.
pub fn captured_task_interval_search_count(
  run : CapturedDAG,
  task : Int,
) -> Int? {
  run.interval_search_limits.get(task).map(items => items.length())
}

///|
pub fn captured_task_interval_search_at(
  run : CapturedDAG,
  task : Int,
  index : Int,
) -> (Int, Int64)? {
  run.interval_search_limits
  .get(task)
  .bind(items => items.get(index))
  .map(pair => pair)
}

///|
/// Selected checked as-of-search bounds, retained by exact occurrence.
pub fn captured_task_asof_search_count(run : CapturedDAG, task : Int) -> Int? {
  run.asof_search_limits.get(task).map(items => items.length())
}

///|
pub fn captured_task_asof_search_at(
  run : CapturedDAG,
  task : Int,
  index : Int,
) -> (Int, Int64)? {
  run.asof_search_limits
  .get(task)
  .bind(items => items.get(index))
  .map(pair => pair)
}

///|
/// Selected checked collection limits, retained by exact aggregate occurrence.
pub fn captured_task_aggregate_output_count(
  run : CapturedDAG,
  task : Int,
) -> Int? {
  run.aggregate_limits.get(task).map(items => items.length())
}

///|
pub fn captured_task_aggregate_output_at(
  run : CapturedDAG,
  task : Int,
  index : Int,
) -> @connector.AggregateOutputCeiling? {
  run.aggregate_limits.get(task).bind(items => items.get(index))
}

///|
pub fn captured_task_aggregate_output_limit(
  run : CapturedDAG,
  task : Int,
  step : Int,
  aggregate : String,
  unit : @connector.AggregateOutputUnit,
) -> Int64? {
  guard run.aggregate_limits.get(task) is Some(items) else { return None }
  for value in items {
    if @connector.aggregate_output_ceiling_step(value) == step &&
      @connector.aggregate_output_ceiling_name(value) == aggregate &&
      @connector.aggregate_output_ceiling_unit(value) == unit {
      return Some(@connector.aggregate_output_ceiling_maximum(value))
    }
  }
  None
}

///|
pub fn captured_task_analytic_envelope_count(
  run : CapturedDAG,
  task : Int,
) -> Int? {
  run.analytic_envelopes.get(task).map(items => items.length())
}

///|
pub fn captured_task_analytic_envelope_at(
  run : CapturedDAG,
  task : Int,
  index : Int,
) -> @connector.AnalyticEnvelope? {
  run.analytic_envelopes.get(task).bind(items => items.get(index))
}

///|
/// Physical handoff checks the original opaque capture, not equal rows or CIDs.
pub fn captured_task_source_matches(
  run : CapturedDAG,
  task : Int,
  source : @query.CapturedInputSource,
) -> Bool {
  guard task >= 0 &&
    task < run.graph.captured_prefix_value() &&
    run.lifetimes[task].live &&
    run.original_sources[task] is Some(expected) &&
    physical_equal(expected, source) &&
    @query.captured_source_available(source) else {
    return false
  }
  // The original verifier may retire this DAG port while its independently
  // owned Source remains live. Recheck the same port after that callback.
  // Stopping new work alone does not retire an original captured output.
  run.lifetimes[task].live &&
  run.original_sources[task] is Some(current) &&
  physical_equal(current, source)
}

///|
/// Exact live capture of the admitted Run, not only an equal Run definition.
pub fn captured_effect_run_matches_checked(
  run : CapturedEffectRunDAG,
  checked : CheckedEffectRunDAG,
) -> Bool {
  !run.captured.stopped && physical_equal(run.checked, checked)
}

///|
/// Observe tracked task/result obligations after stop and port retirement.
/// Caller-owned Source captures, resident environments and unrelated shared
/// Ledger reservations remain separate physical Host responsibilities.
pub fn captured_task_retirement_pending(run : CapturedDAG) -> Bool {
  !run.stopped ||
  run.running is Some(_) ||
  run.executions.any(execution => execution is Some(_)) ||
  run.resources.any(resource => resource is Some(_)) ||
  run.lifetimes.any(lifetime => lifetime.pins != 0)
}

///|
// Shared nominal input binding for Pure and Effect. Matching DATA cannot
// replace the checked owner, live original read or exact Source input slot.
fn source_inputs_original_reads(
  graph : CheckedDAG,
  sources : Array[@query.CapturedInputSource],
) -> Result[
  (Array[(Int, Int, @execution.SuppliedRelationRead)], Array[(Int, Int)]),
  RunIssue,
] {
  if graph.captured_prefix_value() != 0 || graph.source_free_root_value() {
    return Err(ForeignCapture)
  }
  let reads = []
  let seen : Array[(Int, Int)] = []
  for source in sources {
    guard @query.captured_source_original_input_read(source) is Some(read) else {
      return Err(ForeignCapture)
    }
    let mut selected = None
    for slot in graph.supplied_slots_iter() {
      let owner = graph.owners_at(slot.consumer).unwrap()
      if @query.captured_source_matches(
          source,
          @checked.source_identity(graph.program_value()),
          owner,
        ) &&
        @execution.supplied_relation_read_matches_input(
          read,
          owner,
          slot.source_input,
        ) {
        if selected is Some(_) {
          return Err(ForeignCapture)
        }
        selected = Some(slot)
      }
    }
    guard selected is Some(slot) && !seen.contains((slot.consumer, slot.input)) else {
      return Err(ForeignCapture)
    }
    seen.push((slot.consumer, slot.input))
    reads.push((slot.consumer, slot.input, read))
  }
  Ok((reads, seen))
}

///|
/// Supply whole Source reads to the same checked Effect tasks. These input
/// captures never enter completed task slots and keep their RowRun custody.
pub fn open_source_inputs_effect_run_dag(
  checked : CheckedEffectRunDAG,
  graph : CheckedDAG,
  sources : Array[@query.CapturedInputSource],
  ledger : @resources.Ledger,
  keyed? : (Int, Int, @execution.SuppliedRelationRead)? = None,
  models? : Array[(Int, Int, @execution.CompletedOutput)] = [],
  source_results? : Array[
    (
      Int,
      @execution.GeneratedSequence,
      Array[(Int, Int, @execution.ProducerRead)],
      @execution.CompletedSegmentInputs,
    ),
  ] = [],
) -> Result[CapturedEffectRunDAG, RunIssue] {
  guard @graph.source_inputs_dag_matches_original(
    graph,
    checked.computation.graph_value(),
  ) else {
    return Err(ForeignCapture)
  }
  let (reads, seen) = match source_inputs_original_reads(graph, sources) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let graph = match keyed {
    None => graph
    Some((task, step, read)) => {
      guard @graph.graph_with_completed_keyed_model_input(
          graph, task, step, read,
        )
        is Some(selected) else {
        return Err(ForeignCapture)
      }
      let mut input = None
      for slot in selected.supplied_slots_iter() {
        if !seen.contains((slot.consumer, slot.input)) &&
          slot.consumer == task &&
          @execution.supplied_relation_read_matches_input(
            read,
            selected.owners_at(task).unwrap(),
            slot.source_input,
          ) {
          input = Some(slot.input)
        }
      }
      guard input is Some(input) else { return Err(ForeignCapture) }
      reads.push((task, input, read))
      selected
    }
  }
  if reads.length() != graph.supplied_slots_count() {
    return Err(ForeignCapture)
  }
  let completed_sources : Array[(Int, @execution.CompletedOutput)] = []
  for (task, sequence, inputs, proof) in source_results {
    guard task >= 0 &&
      task < graph_task_count(graph) &&
      !models.any(model => model.0 == task) &&
      !completed_sources.any(original => original.0 == task) &&
      graph.owners_at(task) is Some(owner) &&
      physical_equal(@execution.generated_sequence_owner(sequence), owner) &&
      !inputs.is_empty() &&
      inputs.all(input => {
        sources.any(source => {
          @query.captured_source_matches(
            source,
            @checked.source_identity(graph.program_value()),
            owner,
          ) &&
          @query.captured_source_matches_segment_input(source, input.2)
        })
      }) &&
      @execution.completed_segment_inputs_output(proof, sequence, inputs)
      is Some(output) else {
      return Err(ForeignCapture)
    }
    completed_sources.push((task, output))
  }
  let dependencies = match
    effect_dependency_ports(checked.computation, 4096, 65536, 64) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let captured = match
    open_checked_dag(
      graph,
      [],
      ledger,
      [],
      supplied_reads=reads,
      retained_models=models,
      retained_source_tasks=completed_sources,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for dependency in dependencies {
    captured.effect_dependency_outputs[dependency.task] = true
  }
  Ok({ checked, captured, })
}
