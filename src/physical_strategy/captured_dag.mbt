///|
/// Host-private serial execution state. Task success is not Program publication.
/// The supplied acquisition has already completed; this object only borrows it.
struct CapturedDAG {
  graph : CheckedDAG
  offer_owner : StrategyOfferOwner
  mut source : @planning.CapturedInputSource?
  ledger : @resources.Ledger
  completed : Array[@execution.CompletedOutput?]
  done : Array[Bool]
  lifetimes : Array[TaskLifetime]
  resources : Array[TaskRetention?]
  join_limits : Array[@witness.LimitClaim?]
  inputs : Array[Array[@execution.ProducerRead?]]
  mut running : (Int, TaskExecution)?
  executions : Array[TaskExecution?]
  mut resident_environment : ResidentEnvironment?
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
}

///|
pub(all) enum RunIssue {
  UnsupportedGraph
  ForeignCapture
  NotReady
  Stopped
  ForeignCandidate
  MissingOutput
  Capture(@planning.CapturedSourceIssue)
  Binding(@execution.ProducerBindingIssue)
  Read(@execution.ProducerReadIssue)
  Compute(@connector.FixedComputeIssue)
  Implementation(Error)
  Physical(@resources.LedgerIssue)
}

///|
/// Initial profile: one captured acquisition at unit zero and exactly one
/// checked data input per unary task, or up to two for inner join. No fresh
/// reads are synthesized. Bindings are indexed by checked receiving port.
pub fn open_captured_dag(
  graph : CheckedDAG,
  source : @planning.CapturedInputSource,
  ledger : @resources.Ledger,
) -> Result[CapturedDAG, RunIssue] {
  let count = graph.owners.length()
  if count == 0 {
    return Err(UnsupportedGraph)
  }
  if !@planning.captured_source_matches(
      source,
      @checked.source_identity(graph.program),
      graph.owners[0],
    ) {
    return Err(ForeignCapture)
  }
  let seen = Array::make(count, 0)
  let join_limits : Array[@witness.LimitClaim?] = Array::make(count, None)
  for edge in graph.data {
    if edge.consumer == 0 || edge.input < 0 || edge.input > 1 {
      return Err(UnsupportedGraph)
    }
    let bit = if edge.input == 0 { 1 } else { 2 }
    if (seen[edge.consumer] & bit) != 0 {
      return Err(UnsupportedGraph)
    }
    seen[edge.consumer] = seen[edge.consumer] | bit
  }
  for index in 1..<count {
    let pipeline = @lower.pipeline(
      @lower.bound_preparation(graph.owners[index]),
    )
    let input_count = @pipeline.input_count(pipeline)
    if input_count < 1 ||
      input_count > 2 ||
      seen[index] != (if input_count == 1 { 1 } else { 3 }) {
      return Err(UnsupportedGraph)
    }
    let steps = @pipeline.step_count(pipeline)
    if steps == 1 {
      let step = @pipeline.step_at(pipeline, 0).unwrap()
      if step.operation is @pipeline.Join(right~, checked~) {
        guard @join.kind(checked) == @join.Inner &&
          step.input is Some(@pipeline.Input(_)) &&
          right is @pipeline.Input(_) else {
          return Err(UnsupportedGraph)
        }
        guard checked_task_join_limit(graph, index) is Some(limit) else {
          return Err(UnsupportedGraph)
        }
        join_limits[index] = Some(limit)
        continue
      }
      guard step.operation is @pipeline.Unary(group) &&
        input_count == 1 &&
        @relation.operation(group) == @relation.Group &&
        step.input == Some(@pipeline.Input(0)) else {
        return Err(UnsupportedGraph)
      }
      // Exact aggregate support is checked by the selected realization's
      // compiler. The graph owns ports and dependencies, not a second compiler.
      continue
    }
    if steps != 2 || input_count != 1 {
      return Err(UnsupportedGraph)
    }
    let first = @pipeline.step_at(pipeline, 0).unwrap()
    let second = @pipeline.step_at(pipeline, 1).unwrap()
    guard first.operation is @pipeline.Unary(filter) &&
      second.operation is @pipeline.Unary(select) &&
      @relation.operation(filter) == @relation.Filter &&
      @relation.operation(select) == @relation.Select &&
      first.input == Some(@pipeline.Input(0)) &&
      second.input == Some(@pipeline.Step(0)) else {
      return Err(UnsupportedGraph)
    }
  }
  // This bounded execution profile exposes one final output per Compute.
  // Do not reinterpret an authored reference to an intermediate step as it.
  for edge in graph.data {
    if edge.producer != 0 {
      let pipeline = @lower.pipeline(
        @lower.bound_preparation(graph.owners[edge.producer]),
      )
      if edge.target != @pipeline.Step(@pipeline.step_count(pipeline) - 1) {
        return Err(UnsupportedGraph)
      }
    }
  }
  let lifetimes = Array::makei(count, _ => TaskLifetime::{ live: true, })
  let root_lifetime = lifetimes[0]
  let resources : Array[TaskRetention?] = Array::make(count, None)
  resources[0] = Some({ holding: None, parents: [], })
  Ok({
    graph,
    offer_owner: { graph, },
    source: Some(
      @planning.restrict_captured_source(source, fn() { root_lifetime.live }),
    ),
    ledger,
    completed: Array::make(count, None),
    done: Array::make(count, false),
    lifetimes,
    resources,
    join_limits,
    inputs: Array::makei(count, task => {
      Array::make(
        if task == 0 {
          0
        } else {
          @pipeline.input_count(
            @lower.pipeline(@lower.bound_preparation(graph.owners[task])),
          )
        },
        None,
      )
    }),
    stopped: false,
    failure: None,
    running: None,
    executions: Array::make(count, None),
    resident_environment: None,
    generation: 0,
    search: None,
    revisions: 0,
    searched_generation: None,
    searched_resources: None,
    strategy: None,
    search_report: [],
    search_report_complete: false,
    revision_history: [],
  })
}

///|
pub fn captured_root_statistics(
  run : CapturedDAG,
) -> @planning.CapturedSourceStatistics? {
  run.source.bind(source => @planning.captured_source_statistics(source))
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
  let pipeline = @lower.pipeline(
    @lower.bound_preparation(run.graph.owners[task]),
  )
  Some(@pipeline.Step(@pipeline.step_count(pipeline) - 1))
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
  let bound = if edge.producer == 0 {
    guard run.source is Some(source) else {
      fail_captured_task(run, task, Capture(Unavailable))
      return Err(Capture(Unavailable))
    }
    match @planning.bind_captured_source(source, receiver, edge.input) {
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
        edge.input,
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
  if captured_task_join_output_limit(run, task) is Some(required) {
    guard @connector.synchronous_compute_join_output_ceiling(compute)
      is Some((0, actual)) &&
      actual <= required else {
      return Err(ForeignCandidate)
    }
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
        publish_task_completion(run, task, output, holding, MissingOutput, _ => {
          Ok(())
        }) {
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
  let output = run.completed.get(task).bind(value => value)
  let lifetime = run.lifetimes[task]
  output.map(output => {
    @execution.restrict_completed_output(output, fn() { lifetime.live })
  })
}

///|
/// Stops new work without revoking independent successful calculation results or
/// closing the caller-owned capture. In-flight asynchronous cleanup is separate.
pub fn stop_captured_dag(run : CapturedDAG) -> Unit {
  run.stopped = true
  if run.running is Some((_, execution)) {
    // Revocation is not stop acknowledgement. The Host still owns cleanup.
    (execution.hooks.unwrap().cancel)()
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
/// Read the already-owned application, never reconstruct a limit from a CID or
/// substitute the Host's execution settings for the selected checked contract.
/// The selected checked limit, not an estimate inferred from input row counts.
pub fn captured_task_join_output_limit(run : CapturedDAG, task : Int) -> Int64? {
  run.join_limits
  .get(task)
  .bind(value => value)
  .map(limit => @derivation.minimum_value(@witness.limit_minimum(limit)))
}

///|
fn checked_task_join_limit(
  graph : CheckedDAG,
  task : Int,
) -> @witness.LimitClaim? {
  let stages = @context.program_reference_stages(
    @context.program_sources_references(
      @context.program_identity_sources(@checked.source_identity(graph.program)),
    ),
  )
  guard @context.stage_context_at(stages, task) is Some(bound) else {
    return None
  }
  let closure = @context.checked_capacity(@context.parameter_context(bound))
  guard @capacity.application_closure_at(closure, 0) is Some(coverage) &&
    @capacity.consumer_coverage_joins(
      @capacity.application_coverage_consumers(coverage),
    )
    is Some(joins) &&
    @step_bounds.join_application_at(joins, 0) is Some(limit) &&
    physical_equal(
      @step_bounds.join_limit_pipeline(limit),
      @lower.pipeline(@lower.bound_preparation(graph.owners[task])),
    ) else {
    return None
  }
  Some(@step_bounds.join_limit_claim(limit))
}
