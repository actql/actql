///|
pub(all) enum ClientRemoteTaskStartIssue {
  ForeignTask
  ForeignDispatch
  Request(ClientRequestIdentityIssue)
  Start(ClientRunStartIssue)
}

///|
/// Prepare one start claim against the exact saved task intent and checked
/// dependencies. The trusted Host must persist the claim in its existing Run
/// CAS domain, with cancellation, before sending. A positive decision performs
/// no physical start, reservation, borrow or ownership transfer.
pub fn prepare_client_remote_task_physical_start(
  progress : ClientRemoteTaskProgress,
  task_key : String,
  dispatch_cid : String,
  requested : ClientRequestIdentity,
  retained : ClientRequestIdentity,
  retained_definition_cid : String,
  dispatch_reserved : Bool,
  physically_unstarted : Bool,
  current_authorization : Bool,
  cancellation_requested : Bool,
  pre_start_failure_confirmed : Bool,
) -> Result[Bool, ClientRemoteTaskStartIssue] {
  let original = match
    prepare_source_free_client_request_identity(
      progress.prepared,
      progress.authority,
      client_request_caller_id(retained),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Request(issue))
  }
  prepare_bound_client_remote_task_physical_start(
    progress, original, task_key, dispatch_cid, requested, retained, retained_definition_cid,
    dispatch_reserved, physically_unstarted, current_authorization, cancellation_requested,
    pre_start_failure_confirmed,
  )
}

///|
/// Only the family-specific entry can derive the original checked request.
/// The existing physical start Owner still decides the saved intent's claim.
fn prepare_bound_client_remote_task_physical_start(
  progress : ClientRemoteTaskProgress,
  original : ClientRequestIdentity,
  task_key : String,
  dispatch_cid : String,
  requested : ClientRequestIdentity,
  retained : ClientRequestIdentity,
  retained_definition_cid : String,
  dispatch_reserved : Bool,
  physically_unstarted : Bool,
  current_authorization : Bool,
  cancellation_requested : Bool,
  pre_start_failure_confirmed : Bool,
) -> Result[Bool, ClientRemoteTaskStartIssue] {
  match client_request_identity_relation(original, retained) {
    SameRequest => ()
    ChangedIntent => return Err(Start(ChangedIntent))
    DifferentRequest => return Err(Start(DifferentRequest))
  }
  let mut ordinal = None
  for task in 0..<progress.keys.length() {
    if progress.keys[task] == task_key {
      ordinal = Some(task)
    }
  }
  guard ordinal is Some(task) else { return Err(ForeignTask) }
  guard progress.requests[task] is Some(request) else { return Ok(false) }
  if @remote.dispatch_request_identity(request) != dispatch_cid {
    return Err(ForeignDispatch)
  }
  let allowed = match
    prepare_client_run_physical_start(
      requested,
      retained,
      progress.definition,
      retained_definition_cid,
      dispatch_reserved,
      physically_unstarted,
      current_authorization,
      cancellation_requested~,
      pre_start_failure_confirmed~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Start(issue))
  }
  // Historical Accepted, unknown or completed execution belongs to its
  // reconciliation owner even if a Host accidentally supplies "unstarted".
  Ok(
    allowed &&
    progress.dependency_ready_task == Some(task) &&
    progress.observations[task].bind(value => value.execution) is None,
  )
}
