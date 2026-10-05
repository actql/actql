///|
/// Checked task observations restored from the trusted Coordinator's durable
/// records. This is a snapshot, not a scheduler, ledger, start claim or borrow.
pub struct ClientRemoteTaskProgress {
  definition : @publication.PublicationContract
  result_names : Array[String]
  completed : Array[Bool]
  keys : Array[String]
  requests : Array[@remote.DispatchRequest?]
  observations : Array[@remote.CoordinatorExecutionObservation?]
  next_task : Int?
  execution_complete : Bool
  cleanup_complete : Bool
  result_tasks : Array[Int]
}

///|
pub(all) enum ClientRemoteTaskProgressIssue {
  Run(ClientTaskRunBindingIssue)
  UnsupportedGraph
  Fragment(ClientTaskFragmentIssue)
  ForeignObservation
  DuplicateTask
  Protocol(@remote.DispatchIssue)
}

///|
/// Bind every observation to its original checked task and Run. Missing or
/// historical Accepted observations never authorize restarting that task.
/// The first ready task still needs current authority, exact retained-input
/// binding, physical custody and the existing exclusive start claim.
pub fn inspect_client_remote_task_progress(
  prepared : PreparedClientProgram,
  compilation : ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  authority : String,
  durable : Array[@remote.DurableCoordinatorDispatchRecord],
) -> Result[ClientRemoteTaskProgress, ClientRemoteTaskProgressIssue] {
  let binding = match
    bind_client_task_run(prepared, compilation, admission, definition) {
    Ok(value) => value
    Err(issue) => return Err(Run(issue))
  }
  let graph = prepared_client_graph(prepared)
  let count = @strategy.graph_task_count(graph)
  if count == 0 ||
    authority.is_empty() ||
    compilation.infer is Some(_) ||
    @strategy.graph_program_has_effects(graph) {
    return Err(UnsupportedGraph)
  }
  let keys : Array[String] = []
  for task in 0..<count {
    let fragment = match
      issue_prepared_client_task_fragment(
        prepared,
        task,
        client_standard_values_sequence_limits(),
        1000000,
        100000,
        100,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Fragment(issue))
    }
    keys.push(client_task_fragment_node_id(fragment))
  }
  let journal = match @remote.create_coordinator_dispatch_journal(authority) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let requests : Array[@remote.DispatchRequest?] = Array::make(count, None)
  let observations : Array[@remote.CoordinatorExecutionObservation?] = Array::make(
    count,
    None,
  )
  let completed = Array::make(count, false)
  let mut blocked = false
  for saved in durable {
    let request = @remote.durable_coordinator_dispatch_record_request(saved)
    let (run, key) = @remote.dispatch_request_task_scope(request)
    if run != client_task_run_binding_definition_cid(binding) {
      return Err(ForeignObservation)
    }
    let mut ordinal = None
    for task in 0..<count {
      if keys[task] == key {
        ordinal = Some(task)
      }
    }
    guard ordinal is Some(task) else { return Err(ForeignObservation) }
    if requests[task] is Some(_) {
      return Err(DuplicateTask)
    }
    let record = match
      @remote.restore_durable_coordinator_dispatch_record(journal, saved) {
      Ok(value) => value
      Err(issue) => return Err(Protocol(issue))
    }
    let observation = match
      @remote.coordinator_execution_observation(record, authority, run, key) {
      Ok(value) => value
      Err(issue) => return Err(Protocol(issue))
    }
    requests[task] = Some(request)
    observations[task] = Some(observation)
    completed[task] = observation.execution is Some(@remote.NativeSettled) &&
      @remote.durable_coordinator_dispatch_record_evidence(saved) is Some(_)
    if observation.execution
      is Some(
        @remote.ExecutionFailed
        | @remote.ExecutionCancelled
        | @remote.ExecutionUnknown
      ) {
      blocked = true
    }
  }
  let candidate = if blocked {
    None
  } else {
    @strategy.next_dependency_ready_task(graph, task => completed[task])
  }
  // Even an unobserved persisted intent belongs to the existing attempt.
  // Its next action is reconciliation, never a second start selection.
  let next_task = candidate.bind(task => {
    if requests[task] is None {
      Some(task)
    } else {
      None
    }
  })
  let mut execution_complete = true
  let mut cleanup_complete = true
  for task in 0..<count {
    execution_complete = execution_complete && completed[task]
    cleanup_complete = cleanup_complete &&
      observations[task]
      .map(observation => observation.cleanup_complete)
      .unwrap_or(false)
  }
  let result_tasks : Array[Int] = []
  for result in 0..<@strategy.graph_result_count(graph) {
    guard @strategy.graph_result_task(graph, result) is Some(task) else {
      return Err(UnsupportedGraph)
    }
    result_tasks.push(task)
  }
  Ok({
    definition,
    result_names: client_task_run_binding_result_names(binding),
    completed,
    keys,
    requests,
    observations,
    next_task,
    execution_complete,
    cleanup_complete,
    result_tasks,
  })
}

///|
pub fn client_remote_task_progress_next_task(
  value : ClientRemoteTaskProgress,
) -> Int? {
  value.next_task
}

///|
pub fn client_remote_task_progress_execution_complete(
  value : ClientRemoteTaskProgress,
) -> Bool {
  value.execution_complete
}

///|
pub fn client_remote_task_progress_cleanup_complete(
  value : ClientRemoteTaskProgress,
) -> Bool {
  value.cleanup_complete
}

///|
pub fn client_remote_task_progress_result_tasks(
  value : ClientRemoteTaskProgress,
) -> Array[Int] {
  value.result_tasks.copy()
}

///|
/// Inspect each checked slot without projecting one producer's settlement into
/// the public outcome of the entire Run. CleanupReleased and recovery cleanup
/// remain distinguishable, even though both can discharge physical custody.
pub fn client_remote_task_progress_fields(
  value : ClientRemoteTaskProgress,
) -> Array[Array[String]] {
  value.keys.mapi((task, key) => {
    let observed = value.observations[task]
    let execution = match observed.bind(value => value.execution) {
      None => "unobserved"
      Some(@remote.Accepted) => "accepted"
      Some(@remote.Provisioning) => "provisioning"
      Some(@remote.Running) => "running"
      Some(@remote.NativeSettled) => "settled"
      Some(@remote.ExecutionFailed) => "failed"
      Some(@remote.ExecutionCancelled) => "cancelled"
      Some(@remote.ExecutionUnknown) => "unknown"
    }
    let cleanup = match observed.bind(value => value.cleanup) {
      None => "unobserved"
      Some(@remote.CleanupActive) => "active"
      Some(@remote.CleanupReleasing) => "releasing"
      Some(@remote.CleanupReleased) => "released"
      Some(@remote.CleanupUnknown) => "unknown"
      Some(@remote.CleanupForceLost) => "force_lost"
      Some(@remote.CleanupRecoveredAfterLoss) => "recovered_after_loss"
    }
    let revision = observed
      .map(value => value.revision.to_string())
      .unwrap_or("-1")
    let dispatch = value.requests[task]
      .map(@remote.dispatch_request_identity)
      .unwrap_or("")
    [task.to_string(), key, execution, cleanup, revision, dispatch]
  })
}

///|
pub fn client_remote_task_progress_scopes(
  value : ClientRemoteTaskProgress,
) -> Array[Array[String]] {
  value.requests.map(request => {
    request.map(@remote.dispatch_request_execution_scope).unwrap_or([])
  })
}
