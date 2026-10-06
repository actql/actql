///|
/// An unpublished checked Run snapshot. No Run commit, start claim,
/// cancellation fence, physical stop or resource release is performed here.
pub struct ClientRemoteTaskRunProjection {
  progress : ClientRemoteTaskProgress
  state_wire : String
  execution : String
  work : Array[String]
  next_task : Int?
  publication_ready : Bool
}

///|
pub(all) enum ClientRemoteTaskRunProjectionIssue {
  InvalidStartClaims
  MissingRunId
  State(@publication.RunStateIssue)
}

///|
/// The trusted Host supplies only its saved start claims and cancellation
/// request. Task facts come from the admitted Coordinator observations;
/// missing replies and physical settlement without evidence do not publish.
pub fn project_client_remote_task_run(
  progress : ClientRemoteTaskProgress,
  observed_at : String,
  cancellation_requested : Bool,
  claimed_task_keys : Array[String],
) -> Result[ClientRemoteTaskRunProjection, ClientRemoteTaskRunProjectionIssue] {
  let claimed = Array::make(progress.keys.length(), false)
  if claimed_task_keys.length() > progress.keys.length() {
    return Err(InvalidStartClaims)
  }
  for key in claimed_task_keys {
    let mut found = false
    for task in 0..<progress.keys.length() {
      if progress.keys[task] == key {
        if claimed[task] {
          return Err(InvalidStartClaims)
        }
        claimed[task] = true
        found = true
      }
    }
    if !found {
      return Err(InvalidStartClaims)
    }
  }
  let mut failed = false
  let mut cancelled = false
  let mut unknown = false
  let mut observed = false
  let mut all_terminal = true
  for task in 0..<progress.keys.length() {
    let execution = progress.observations[task].bind(value => value.execution)
    failed = failed || execution is Some(@remote.ExecutionFailed)
    cancelled = cancelled || execution is Some(@remote.ExecutionCancelled)
    unknown = unknown ||
      execution is Some(@remote.ExecutionUnknown) ||
      (claimed[task] && execution is None)
    observed = observed || execution is Some(_)
    all_terminal = all_terminal &&
      progress.observations[task]
      .map(value => value.execution_terminal)
      .unwrap_or(false)
  }
  // A request or one task's cancellation is not the Run's completed
  // cancellation. Require all observed execution and cleanup obligations.
  // Missing task custody remains pending, never inferred from resource zero.
  // This immutable effect-free unpublished snapshot supplies facts to the
  // same eligibility owner used by live and restored Run execution. The Host
  // must recheck its publication fence/revision before committing anything.
  let cancellation_complete = confirm_client_run_cancellation({
      cancellation_requested,
      model_fence_required: false,
      model_fenced: false,
      unresolved_model_calls: false,
      unresolved_effects: false,
      reconciliation_required: unknown,
      publication_committed: false,
      physical_stop_confirmed: all_terminal,
      cleanup_confirmed: progress.cleanup_complete,
      revision_unchanged: true,
    }) &&
    (cancelled || progress.execution_complete)
  let terminal = if failed {
    Some(@publication.RunOutcomeStatus::Failed)
  } else if cancellation_complete {
    Some(@publication.RunOutcomeStatus::Cancelled)
  } else {
    None
  }
  let execution = if failed {
    "failed"
  } else if cancellation_complete {
    "cancelled"
  } else if unknown {
    "unknown"
  } else if progress.execution_complete {
    "settled"
  } else if observed {
    "running"
  } else {
    "unobserved"
  }
  let run_id = match @publication.run_definition_run_id(progress.definition) {
    Ok(value) => value
    Err(_) => return Err(MissingRunId)
  }
  let state_wire = match
    @publication.issue_effect_free_unpublished_run_state_wire(
      run_id,
      observed_at,
      progress.result_names,
      progress.requests.any(request => request is Some(_)) ||
      claimed_task_keys.length() > 0,
      false,
      100000,
      10000,
      64,
      observed_terminal_outcome=terminal,
      execution_unknown=unknown && terminal is None,
    ) {
    Ok(value) => value
    Err(issue) => return Err(State(issue))
  }
  let publication_ready = progress.execution_complete &&
    !failed &&
    !cancelled &&
    !cancellation_requested &&
    !unknown
  let work : Array[String] = []
  for task in 0..<progress.keys.length() {
    let observation = progress.observations[task]
    let execution = observation.bind(value => value.execution)
    let cleaned = observation
      .map(value => value.cleanup_complete)
      .unwrap_or(false)
    let terminal = observation
      .map(value => value.execution_terminal)
      .unwrap_or(false)
    let action = match execution {
      Some(@remote.ExecutionFailed | @remote.ExecutionCancelled) =>
        if cleaned {
          "none"
        } else {
          "cleanup"
        }
      _ if failed || cancellation_requested =>
        if terminal {
          if cleaned {
            "none"
          } else {
            "release"
          }
        } else if progress.requests[task] is Some(_) {
          "cancel"
        } else if claimed[task] {
          "reconcile"
        } else {
          "none"
        }
      Some(@remote.NativeSettled) =>
        if progress.completed[task] {
          if publication_ready && progress.result_tasks.contains(task) {
            "publication"
          } else {
            "none"
          }
        } else {
          "reconcile"
        }
      None if progress.requests[task] is None && !claimed[task] => "none"
      _ => "reconcile"
    }
    work.push(action)
  }
  Ok({
    progress,
    state_wire,
    execution,
    work,
    next_task: if failed || cancelled || unknown || cancellation_requested {
      None
    } else {
      progress.next_task
    },
    publication_ready,
  })
}

///|
pub fn client_remote_task_run_projection_fields(
  value : ClientRemoteTaskRunProjection,
) -> Array[String] {
  [
    value.state_wire,
    value.execution,
    value.next_task.map(task => task.to_string()).unwrap_or("-1"),
    if value.publication_ready {
      "1"
    } else {
      "0"
    },
  ]
}

///|
pub fn client_remote_task_run_projection_work(
  value : ClientRemoteTaskRunProjection,
) -> Array[String] {
  value.work.copy()
}
