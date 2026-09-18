///|
/// Host-private serial execution state. Task success is not Program publication.
/// The supplied acquisition has already completed; this object only borrows it.
struct CapturedDAG {
  graph : CheckedDAG
  offer_owner : StrategyOfferOwner
  mut source : @query.CapturedInputSource?
  ledger : @resources.Ledger
  completed : Array[@execution.CompletedOutput?]
  managed_completed : Array[@execution.ManagedCompletionReference?]
  done : Array[Bool]
  lifetimes : Array[TaskLifetime]
  resources : Array[TaskRetention?]
  join_limits : Array[Array[(Int, @witness.LimitClaim)]]
  inputs : Array[Array[@execution.ProducerRead?]]
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
/// Initial profile: one captured acquisition at unit zero, one or two checked
/// data inputs per task and one final output. No fresh
/// reads are synthesized. Bindings are indexed by checked receiving port.
pub fn open_captured_dag(
  graph : CheckedDAG,
  source : @query.CapturedInputSource,
  ledger : @resources.Ledger,
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
  let seen = Array::make(count, 0)
  let join_limits : Array[Array[(Int, @witness.LimitClaim)]] = Array::makei(
    count,
    _ => [],
  )
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
    let expected_inputs = if input_count == 0 {
      0
    } else if input_count == 1 {
      1
    } else {
      3
    }
    if input_count > 2 || seen[index] != expected_inputs {
      return Err(UnsupportedGraph)
    }
    if @pipeline.step_count(pipeline) == 0 {
      return Err(UnsupportedGraph)
    }
    // Accept owned tasks, not operation-name templates. Implementations reject
    // unsupported execution obligations before offering work.
    for requirement in graph.operations[index] {
      if requirement.disposition is ExecutionCheck(JoinOutputLimit(check)) {
        join_limits[index].push(
          (check.site.step, @step_bounds.join_limit_claim(check.limit)),
        )
      }
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
    completed: Array::make(count, None),
    managed_completed: Array::make(count, None),
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
    match @query.bind_captured_source(source, receiver, edge.input) {
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
  match
    @execution.prepare_managed_producer_read(
      run.graph.owners[task],
      input_index,
      run.graph.owners[edge.producer],
      output,
      max_entries,
      max_name_bytes,
    ) {
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
/// Exact producers of the next managed task in receiving input-port order.
/// Missing, external, or incomplete topology returns an empty set; concrete
/// managed completions are still checked independently during preparation.
pub fn captured_next_managed_producers(run : CapturedDAG) -> Array[Int] {
  guard next_captured_task(run) is Some(task) && !run.inputs[task].is_empty() else {
    return []
  }
  let producers = Array::make(run.inputs[task].length(), -1)
  for edge in run.graph.data {
    if edge.consumer == task &&
      edge.input >= 0 &&
      edge.input < producers.length() &&
      edge.producer > 0 {
      producers[edge.input] = edge.producer
    }
  }
  if producers.any(producer => producer <= 0) {
    []
  } else {
    producers
  }
}

///|
/// Exact checked input-port count for the next managed task. Unlike the
/// producer list, zero distinguishes a legitimate source-free operation from
/// an incomplete topology for a task that requires inputs.
pub fn captured_next_managed_input_count(run : CapturedDAG) -> Int? {
  guard next_captured_task(run) is Some(task) &&
    run.graph.owners.get(task) is Some(owner) else {
    return None
  }
  Some(
    @pipeline.input_count(
      @lower.pipeline(@lower.bound_preparation(owner)),
    ),
  )
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
      run.managed_completed.get(producer).bind(value => value) is None {
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
  for (step, claim) in run.join_limits[task] {
    let required = @derivation.minimum_value(@witness.limit_minimum(claim))
    guard @connector.synchronous_compute_join_output_ceiling(compute, step)
      is Some(actual) &&
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
  run.managed_completed
  .get(task)
  .bind(value => value)
  .map(reference => {
    @execution.managed_completed_reference_matches(reference, output)
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
/// A managed downstream use must name the exact graph edge and exact managed
/// producer occurrence. Equal values, profile pins or physical bytes do not
/// make another output an input of this task.
fn[T] captured_managed_inputs_match(
  run : CapturedDAG,
  task : Int,
  inputs : Array[@execution.ManagedProducerRead[T]],
) -> Bool {
  if task <= 0 ||
    task >= run.inputs.length() ||
    inputs.length() != run.inputs[task].length() {
    return false
  }
  for port, input in inputs {
    if !physical_equal(
        @execution.managed_producer_read_receiver(input),
        run.graph.owners[task],
      ) ||
      @execution.managed_producer_read_input_index(input) != port {
      return false
    }
    let mut selected : DataEdge? = None
    for edge in run.graph.data {
      if edge.consumer == task && edge.input == port {
        selected = Some(edge)
        break
      }
    }
    guard selected is Some(edge) &&
      edge.producer > 0 &&
      run.managed_completed.get(edge.producer).bind(value => value)
      is Some(reference) &&
      @execution.managed_producer_read_matches_reference(input, reference) else {
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
  captured_managed_inputs_match(
    run,
    task,
    @connector.managed_fixed_compute_request_inputs(request),
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
  .map(limit => @derivation.minimum_value(@witness.limit_minimum(limit)))
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
  run.join_limits
  .get(task)
  .bind(items => items.get(index))
  .map(pair => {
    (pair.0, @derivation.minimum_value(@witness.limit_minimum(pair.1)))
  })
}
