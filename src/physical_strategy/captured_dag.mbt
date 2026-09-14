///|
/// Host-private serial execution state. Task success is not Program publication.
/// The supplied acquisition has already completed; this object only borrows it.
struct CapturedDAG {
  graph : CheckedDAG
  offer_owner : StrategyOfferOwner
  mut source : @planning.CapturedInputSource?
  ledger : Ledger
  completed : Array[TaskCompletion?]
  done : Array[Bool]
  lifetimes : Array[TaskLifetime]
  resources : Array[TaskRetention?]
  inputs : Array[@execution.ProducerRead?]
  mut running : (Int, @planning.DuckDBComputeAttempt)?
  mut stopped : Bool
  mut failure : (Int, RunIssue)?
  mut generation : Int
  mut search : SearchLimits?
  mut revisions : Int
  mut searched_generation : Int?
  mut searched_resources : SearchResources?
  mut strategy : StrategyRevision?
  mut search_report : Array[StrategyAssessment]
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
  Compute(@planning.FixedComputeIssue)
  DuckDB(@planning.DuckDBComputeIssue)
  Physical(LedgerIssue)
}

///|
priv enum TaskCompletion {
  Local(@execution.CompletedSequence)
  DuckDB(@execution.CompletedOutput)
}

///|
/// Initial profile: one captured acquisition at unit zero and exactly one
/// checked data input for every remaining task. No fresh reads are synthesized.
pub fn open_captured_dag(
  graph : CheckedDAG,
  source : @planning.CapturedInputSource,
  ledger : Ledger,
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
  let seen = Array::make(count, false)
  for edge in graph.data {
    if edge.consumer == 0 || seen[edge.consumer] || edge.input != 0 {
      return Err(UnsupportedGraph)
    }
    seen[edge.consumer] = true
  }
  for index in 1..<count {
    let pipeline = @lower.pipeline(
      @lower.bound_preparation(graph.owners[index]),
    )
    if !seen[index] ||
      @pipeline.input_count(pipeline) != 1 ||
      @pipeline.step_count(pipeline) != 2 {
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
  let lifetimes = Array::makei(count, _ => TaskLifetime::{ live: true, })
  let root_lifetime = lifetimes[0]
  let resources : Array[TaskRetention?] = Array::make(count, None)
  resources[0] = Some({ holding: None, parent: None, })
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
    inputs: Array::make(count, None),
    stopped: false,
    failure: None,
    running: None,
    generation: 0,
    search: None,
    revisions: 0,
    searched_generation: None,
    searched_resources: None,
    strategy: None,
    search_report: [],
    revision_history: [],
  })
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
  if run.stopped || run.running is Some(_) {
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
) -> Result[@execution.ProducerRead, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if next_captured_task(run) != Some(task) {
    return Err(NotReady)
  }
  if run.inputs[task] is Some(read) {
    if !@execution.producer_read_available(read) {
      let issue = RunIssue::Read(@execution.ProducerUnavailable)
      fail_captured_task(run, task, issue)
      return Err(issue)
    }
    return Ok(read)
  }
  let mut selected : DataEdge? = None
  for edge in run.graph.data {
    if edge.consumer == task {
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
      run.inputs[task] = Some(read)
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
/// Choice, request and generated sequence are verified before existing execution.
pub fn execute_captured_local_task(
  run : CapturedDAG,
  task : Int,
  choice : @planning.FixedComputeChoice,
  prepared : @planning.PreparedCompute[@execution.GeneratedSequence],
  limits : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if next_captured_task(run) != Some(task) {
    return Err(NotReady)
  }
  let request = @planning.fixed_compute_candidate_request(
    @planning.prepared_compute_candidate(prepared),
  )
  if !strategy_candidate_matches(
      run,
      task,
      @planning.prepared_compute_candidate(prepared),
    ) {
    return Err(ForeignCandidate)
  }
  guard run.inputs[task] is Some(read) &&
    physical_equal(read, @planning.fixed_compute_request_input(request)) else {
    return Err(ForeignCandidate)
  }
  guard @planning.fixed_compute_choice_payload(choice, prepared)
    is Some(generated) else {
    return Err(Compute(NotSelected))
  }
  guard @execution.generated_sequence_capacity(generated, limits, measurement)
    is Some(capacity) else {
    return Err(Physical(InvalidLimits))
  }
  if strategy_task_envelope(run, task) is Some(selected) &&
    (
      capacity.retained_bytes > selected.retained_bytes ||
      capacity.execution_bytes > selected.execution_bytes
    ) {
    return Err(Physical(InvalidCharge))
  }
  let reservation = match
    reserve_attempt(
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
    retain_allocation(run.ledger, reservation, capacity.retained_bytes) {
    Ok(holding) => holding
    Err(issue) => {
      settle_reservation(run.ledger, reservation) |> ignore
      return Err(Physical(issue))
    }
  }
  match
    @planning.execute_local_fixed_compute(
      choice,
      prepared,
      limits,
      measurement~,
    ) {
    Ok(completed) => {
      run.completed[task] = Some(Local(completed))
      record_task_retention(run, task)
      run.resources[task].unwrap().holding = Some(holding)
      settle_reservation(run.ledger, reservation) |> ignore
      run.inputs[task] = None
      run.generation += 1
      Ok(())
    }
    Err(issue) => {
      release_allocation(run.ledger, holding) |> ignore
      settle_reservation(run.ledger, reservation) |> ignore
      fail_captured_task(run, task, Compute(issue))
      Err(Compute(issue))
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
  if task < 0 || task >= run.lifetimes.length() || !run.lifetimes[task].live {
    return None
  }
  let output = match run.completed.get(task).bind(value => value) {
    Some(Local(completed)) => @execution.completed_output(completed, target)
    Some(DuckDB(output)) =>
      if target == @pipeline.Step(1) {
        Some(output)
      } else {
        None
      }
    None => None
  }
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
  if run.running is Some((_, attempt)) {
    // Revocation is not DB-stop acknowledgement. The Host still owns cleanup.
    @planning.abort_duckdb_compute_attempt(attempt)
  }
  for index in 0..<run.inputs.length() {
    run.inputs[index] = None
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
pub fn captured_dag_ledger(run : CapturedDAG) -> Ledger {
  run.ledger
}
