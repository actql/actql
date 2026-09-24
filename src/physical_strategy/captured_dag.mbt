///|
/// Host-private serial execution state. Task success is not Program publication.
/// The supplied acquisition has already completed; this object only borrows it.
struct CapturedDAG {
  graph : CheckedDAG
  offer_owner : StrategyOfferOwner
  mut source : @query.CapturedInputSource?
  ledger : @resources.Ledger
  outputs : Array[CommittedTaskOutput?]
  done : Array[Bool]
  lifetimes : Array[TaskLifetime]
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
  MissingOutput
  Capture(@query.CapturedSourceIssue)
  Binding(@execution.ProducerBindingIssue)
  Read(@execution.ProducerReadIssue)
  Compute(@connector.FixedComputeIssue)
  Implementation(Error)
  Physical(@resources.LedgerIssue)
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
fn ordered_data_inputs_complete(
  input_counts : Array[Int],
  data : Array[DataEdge],
  supplied_slots? : Array[LocalInputSlot] = [],
) -> Bool {
  if input_counts.is_empty() {
    return false
  }
  let seen : Array[Array[Bool]] = Array::makei(input_counts.length(), task => {
    let count = input_counts[task]
    if count < 0 {
      []
    } else {
      Array::make(count, false)
    }
  })
  for edge in data {
    if edge.consumer <= 0 || edge.consumer >= input_counts.length() {
      return false
    }
    let inputs = seen[edge.consumer]
    if edge.input < 0 || edge.input >= inputs.length() || inputs[edge.input] {
      return false
    }
    inputs[edge.input] = true
  }
  for input in supplied_slots {
    if input.consumer <= 0 || input.consumer >= input_counts.length() {
      return false
    }
    let inputs = seen[input.consumer]
    if input.input < 0 || input.input >= inputs.length() || inputs[input.input] {
      return false
    }
    inputs[input.input] = true
  }
  for task in 1..<input_counts.length() {
    if input_counts[task] < 0 {
      return false
    }
    for present in seen[task] {
      if !present {
        return false
      }
    }
  }
  true
}

///|
pub fn graph_ordered_inputs_complete(graph : CheckedDAG) -> Bool {
  ordered_data_inputs_complete(
    graph.input_counts,
    graph.data,
    supplied_slots=graph.supplied_slots,
  )
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
) -> Result[CapturedDAG, RunIssue] {
  if graph_program_has_effects(graph) {
    return Err(UnsupportedGraph)
  }
  open_captured_dag_owned(graph, source, ledger, supplied)
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
  let captured = match
    open_captured_dag_owned(checked.computation.graph, source, ledger, supplied) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ checked, captured, })
}

///|
pub fn captured_effect_run_dag(value : CapturedEffectRunDAG) -> CapturedDAG {
  value.captured
}

///|
pub fn captured_effect_run_owner(
  value : CapturedEffectRunDAG,
) -> @checked.EffectProgramRunCandidate {
  value.checked.run
}

///|
/// Retain the checked source occurrence through capture without implying a
/// live read pin. Physical output availability is checked at each use-site.
pub fn captured_effect_run_source_count(value : CapturedEffectRunDAG) -> Int {
  value.checked.computation.sources.length()
}

///|
pub fn captured_effect_run_source_at(
  value : CapturedEffectRunDAG,
  index : Int,
) -> CheckedEffectSourcePort? {
  value.checked.computation.sources.get(index).bind(source => source)
}

///|
fn open_captured_dag_owned(
  graph : CheckedDAG,
  source : @query.CapturedInputSource,
  ledger : @resources.Ledger,
  supplied : Array[@execution.CapturedRows],
) -> Result[CapturedDAG, RunIssue] {
  let count = graph.owners.length()
  if count == 0 {
    return Err(UnsupportedGraph)
  }
  if !@query.captured_source_matches(
      source,
      @checked.source_identity(graph.program),
      graph.owners[0],
    ) {
    return Err(ForeignCapture)
  }
  let input_counts = Array::makei(count, task => graph.input_counts[task])
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
  if !ordered_data_inputs_complete(
      input_counts,
      graph.data,
      supplied_slots=graph.supplied_slots,
    ) {
    return Err(UnsupportedGraph)
  }
  if supplied.length() != graph.supplied_slots.length() {
    return Err(UnsupportedGraph)
  }
  let supplied_inputs : Array[Array[@execution.CapturedRows?]] = Array::makei(
    count,
    task => Array::make(input_counts[task], None),
  )
  for rows in supplied {
    let mut matched = false
    for input in graph.supplied_slots {
      guard graph.owners.get(input.consumer) is Some(owner) else {
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
  for index in 1..<count {
    let pipeline = @lower.pipeline(
      @lower.bound_preparation(graph.owners[index]),
    )
    if @pipeline.step_count(pipeline) == 0 {
      return Err(UnsupportedGraph)
    }
    // Accept owned tasks, not operation-name templates. Implementations reject
    // unsupported execution obligations before offering work.
    for requirement in graph.operations[index] {
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
  for edge in graph.data {
    if edge.producer != 0 &&
      graph.targets.get(edge.producer).bind(value => value) != Some(edge.target) {
      return Err(UnsupportedGraph)
    }
  }
  let lifetimes = Array::makei(count, _ => TaskLifetime::{
    live: true,
    pins: 0,
  })
  let root_lifetime = lifetimes[0]
  let resources : Array[TaskRetention?] = Array::make(count, None)
  resources[0] = Some({
    holding: None,
    release_confirmed: fn() { true },
    parents: [],
  })
  Ok({
    graph,
    offer_owner: { graph, },
    source: Some(
      @query.restrict_captured_source(source, fn() { root_lifetime.live }),
    ),
    ledger,
    outputs: Array::make(count, None),
    done: Array::make(count, false),
    lifetimes,
    resources,
    join_limits,
    interval_search_limits,
    asof_search_limits,
    aggregate_limits,
    analytic_envelopes,
    inputs: Array::makei(count, task => {
      Array::make(if task == 0 { 0 } else { graph.input_counts[task] }, None)
    }),
    supplied: supplied_inputs,
    supplied_reads: Array::makei(count, task => {
      Array::make(input_counts[task], None)
    }),
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
  })
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
  for index in 1..<run.done.length() {
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
  if publication_required && run.graph.results.any(result => result.task == 0) {
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
    run.graph.owners.get(task) is Some(owner) else {
    return Err(@execution.InvalidLimits)
  }
  run.managed_identity_policy_sealed = true
  let mut has_consumer = false
  for edge in run.graph.data {
    if edge.producer == task {
      has_consumer = true
      break
    }
  }
  let result_occurrences = run.graph.results.filter_map(result => {
    if result.task == task {
      Some(result.occurrence)
    } else {
      None
    }
  })
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
  run.source.bind(source => @query.captured_source_statistics(source))
}

///|
pub fn captured_dag_graph(run : CapturedDAG) -> CheckedDAG {
  run.graph
}

///|
/// Exact final port of an admitted Compute task, including before execution.
/// Acquisition is accessed through its captured source, not this port accessor.
pub fn captured_task_target(run : CapturedDAG, task : Int) -> @pipeline.Target? {
  if task <= 0 || task >= run.graph.owners.length() {
    return None
  }
  run.graph.targets[task]
}

///|
pub fn captured_dag_strategy(run : CapturedDAG) -> StrategyRevision? {
  run.strategy
}

///|
fn task_done(run : CapturedDAG, index : Int) -> Bool {
  index == 0 || run.done[index]
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
  for index in 1..<run.graph.owners.length() {
    if task_done(run, index) {
      continue
    }
    let mut ready = true
    for edge in run.graph.data {
      if edge.consumer == index && !task_done(run, edge.producer) {
        ready = false
      }
    }
    for edge in run.graph.control {
      if edge.consumer == index && !task_done(run, edge.predecessor) {
        ready = false
      }
    }
    if ready {
      return Some(index)
    }
  }
  None
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
  for edge in run.graph.data {
    if edge.consumer == task && edge.input == input_index {
      selected = Some(edge)
      break
    }
  }
  let edge = selected.unwrap()
  let receiver = run.graph.owners[task]
  let receiver_input = edge.source_input.unwrap_or(edge.input)
  let bound = if edge.producer == 0 {
    guard run.source is Some(source) else {
      fail_captured_task(run, task, Capture(Unavailable))
      return Err(Capture(Unavailable))
    }
    match @query.bind_captured_source(source, receiver, receiver_input) {
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
    match
      @execution.bind_completed_input(
        receiver,
        receiver_input,
        run.graph.owners[edge.producer],
        output,
      ) {
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
  for input in run.graph.supplied_slots {
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
      run.graph.owners[task],
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
  for edge in run.graph.data {
    if edge.consumer == task && edge.input == input_index {
      selected = Some(edge)
      break
    }
  }
  guard selected is Some(edge) &&
    edge.producer > 0 &&
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
            @lower.bound_preparation(run.graph.owners[task]),
            consumer_step,
          ).unwrap(),
          operation_input,
        ) {
        Some(@pipeline.Step(_)) =>
          @execution.prepare_managed_operation_read(
            run.graph.owners[task],
            consumer_step,
            operation_input,
            run.graph.owners[edge.producer],
            output,
            max_entries,
          )
        _ =>
          @execution.prepare_managed_producer_read(
            run.graph.owners[task],
            edge.source_input.unwrap_or(input_index),
            run.graph.owners[edge.producer],
            output,
            max_entries,
            max_name_bytes,
          )
      }
    None =>
      @execution.prepare_managed_producer_read(
        run.graph.owners[task],
        edge.source_input.unwrap_or(input_index),
        run.graph.owners[edge.producer],
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
  for edge in run.graph.data {
    if edge.consumer == task && edge.input == input_index {
      selected = Some(edge)
      break
    }
  }
  guard selected is Some(edge) &&
    edge.producer > 0 &&
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
        run.graph.owners[task],
        consumer_step,
        operation_input,
        run.graph.owners[edge.producer],
        output,
        carrier_read,
      )
    None =>
      @execution.prepare_carrier_managed_producer_read(
        run.graph.owners[task],
        edge.source_input.unwrap_or(input_index),
        run.graph.owners[edge.producer],
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
  for edge in run.graph.data {
    if edge.consumer == task &&
      edge.input >= 0 &&
      edge.input < producers.length() &&
      edge.producer >= 0 {
      producers[edge.input] = edge.producer
    }
  }
  for input in run.graph.supplied_slots {
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
  for edge in run.graph.data {
    if edge.consumer == task && edge.input == input_index {
      return edge.operation_input
    }
  }
  for slot in run.graph.supplied_slots {
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
  run.graph.input_counts.get(task)
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
/// port used by graph edges, not a separate external-retention obligation.
/// This is exact graph liveness, not GC or permission to discard a sink.
pub fn captured_releasable_managed_producers(run : CapturedDAG) -> Array[Int] {
  let released = []
  for producer in 1..<run.done.length() {
    if !run.done[producer] ||
      !run.lifetimes[producer].live ||
      run.graph.results.any(result => result.task == producer) ||
      (
        managed_task_output_reference(run, producer) is None &&
        carrier_managed_task_output_reference(run, producer) is None
      ) {
      continue
    }
    let mut has_consumer = false
    let mut needed = false
    for edge in run.graph.data {
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
  match @connector.execute_synchronous_compute(compute) {
    Ok(output) => {
      match
        commit_materialized_task_output(
          run,
          task,
          output,
          holding,
          MissingOutput,
        ) {
        Err(issue) => {
          @resources.release_allocation(run.ledger, holding) |> ignore
          @resources.settle_reservation(run.ledger, reservation) |> ignore
          fail_captured_task(run, task, issue)
          return Err(issue)
        }
        Ok(_) => ()
      }
      @resources.settle_reservation(run.ledger, reservation) |> ignore
      Ok(())
    }
    Err(issue) => {
      let failure : RunIssue = match issue {
        Compute(issue) => Compute(issue)
        MissingOutput => MissingOutput
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
  if run.running is Some((_, execution)) {
    // Revocation is not stop acknowledgement. The Host still owns cleanup.
    task_execution_cancel(execution)
  }
  for index in 0..<run.inputs.length() {
    clear_captured_inputs(run, index)
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
    guard ports[port] is Some(actual) &&
      @connector.fixed_compute_request_input(request, port) is Some(expected) &&
      physical_equal(actual, expected) else {
      return false
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
  let inputs = []
  for input in run.inputs[task] {
    guard input is Some(input) else { return false }
    inputs.push(input)
  }
  @execution.completed_output_matches_inputs(output, inputs)
}

///|
/// Verify an ordered mixture of managed Relation and Carrier use sites against
/// the exact producer occurrences retained by the common graph.
fn captured_mixed_managed_inputs_match(
  run : CapturedDAG,
  task : Int,
  inputs : Array[@execution.ManagedInputBinding],
) -> Bool {
  if task <= 0 ||
    task >= run.inputs.length() ||
    inputs.length() != run.inputs[task].length() {
    return false
  }
  for port, input in inputs {
    let mut selected : DataEdge? = None
    for edge in run.graph.data {
      if edge.consumer == task && edge.input == port {
        selected = Some(edge)
        break
      }
    }
    let mut operation = selected.bind(edge => edge.operation_input)
    if operation is None {
      for slot in run.graph.supplied_slots {
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
          run.graph.owners[task],
          step,
          operation_input,
        )
      None =>
        @execution.managed_input_binding_matches_input(
          input,
          run.graph.owners[task],
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
fn[T] captured_managed_request_inputs_match(
  run : CapturedDAG,
  task : Int,
  request : @connector.ManagedFixedComputeRequest[T],
) -> Bool {
  captured_mixed_managed_inputs_match(
    run,
    task,
    @connector.managed_fixed_compute_request_bindings(request),
  )
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
