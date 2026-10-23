///|
/// Computation-only observations retain the original Effect Run. This type
/// cannot be passed to the Pure unpublished Run/cancellation projection.
pub struct ClientRemoteEffectTaskProgress {
  allowed : ClientEffectAllowedRun
  progress : ClientRemoteTaskProgress
}

///|
pub(all) enum ClientRemoteEffectTaskProgressIssue {
  Binding(ClientEffectCompiledRunIssue)
  UnsupportedGraph
  Observation(ClientRemoteTaskProgressIssue)
}

///|
/// Restore exact Coordinator observations against the original checked Effect
/// graph and Run. Completion here concerns task computation/output evidence,
/// not Preview, Effect outcome, Run publication or physical resource release.
pub fn inspect_client_remote_effect_task_progress(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  authority : String,
  durable : Array[@remote.DurableCoordinatorDispatchRecord],
) -> Result[ClientRemoteEffectTaskProgress, ClientRemoteEffectTaskProgressIssue] {
  match
    bind_client_effect_compiled_run(
      allowed.compilation.owner,
      allowed,
      definition,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(issue))
  }
  if !allowed.compilation.compiled.infers.is_empty() {
    return Err(UnsupportedGraph)
  }
  let progress = match
    inspect_bound_client_remote_task_progress(
      allowed.compilation.compiled.owner,
      definition,
      authority,
      @publication.publication_contract_identity(definition),
      client_effect_compilation_result_names(allowed.compilation),
      allowed.compilation.compiled.standard_progress_keys,
      durable,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  Ok({ allowed, progress, })
}

///|
pub fn client_remote_effect_task_progress_next_task(
  value : ClientRemoteEffectTaskProgress,
) -> Int? {
  client_remote_task_progress_next_task(value.progress)
}

///|
pub fn client_remote_effect_task_progress_computation_complete(
  value : ClientRemoteEffectTaskProgress,
) -> Bool {
  client_remote_task_progress_execution_complete(value.progress)
}

///|
/// Only the task dispatch custody is observed. Checkpoint, Effect Ledger,
/// Transfer, borrower and rereadable Result obligations remain separate.
pub fn client_remote_effect_task_progress_task_cleanup_complete(
  value : ClientRemoteEffectTaskProgress,
) -> Bool {
  client_remote_task_progress_cleanup_complete(value.progress)
}

///|
pub fn client_remote_effect_task_progress_result_tasks(
  value : ClientRemoteEffectTaskProgress,
) -> Array[Int] {
  client_remote_task_progress_result_tasks(value.progress)
}

///|
pub fn client_remote_effect_task_progress_fields(
  value : ClientRemoteEffectTaskProgress,
) -> Array[Array[String]] {
  client_remote_task_progress_fields(value.progress)
}

///|
pub fn client_remote_effect_task_progress_scopes(
  value : ClientRemoteEffectTaskProgress,
) -> Array[Array[String]] {
  client_remote_task_progress_scopes(value.progress)
}

///|
/// Prepare the same saved physical claim, using the original Effect request
/// identity. The Host must persist it and recheck current input/Source custody
/// before sending. This decision grants no Effect approval or protected apply.
pub fn prepare_client_remote_effect_task_physical_start(
  value : ClientRemoteEffectTaskProgress,
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
    prepare_client_effect_request_identity(
      value.allowed.compilation.owner,
      value.progress.authority,
      client_request_caller_id(retained),
      source_free_caller_input_intent_cid(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Request(issue))
  }
  prepare_bound_client_remote_task_physical_start(
    value.progress,
    original,
    task_key,
    dispatch_cid,
    requested,
    retained,
    retained_definition_cid,
    dispatch_reserved,
    physically_unstarted,
    current_authorization,
    cancellation_requested,
    pre_start_failure_confirmed,
  )
}

///|
/// Original saved Host claim facts, not a dispatch or cancellation permit.
/// Every checked task is supplied once; the existing Coordinator Owner binds
/// any observed request to its exact original dispatch identity.
pub(all) struct ClientRemoteEffectTaskRunClaim {
  task_key : String
  dispatch_cid : String?
  dispatch_reserved : Bool
  physical_start_claimed : Bool
}

///|
/// A pre-Checkpoint unpublished candidate for the same original Effect Run.
/// Whole-Run cleanup and Effect publication are deliberately not observed.
pub struct ClientRemoteEffectTaskRunProjection {
  original : ClientRemoteEffectTaskProgress
  projection : ClientRemoteTaskRunProjection
}

///|
pub fn project_client_remote_effect_task_run(
  value : ClientRemoteEffectTaskProgress,
  observed_at : String,
  cancellation_requested : Bool,
  claims : Array[ClientRemoteEffectTaskRunClaim],
) -> Result[
  ClientRemoteEffectTaskRunProjection,
  ClientRemoteTaskRunProjectionIssue,
] {
  let progress = value.progress
  if claims.length() != progress.keys.length() {
    return Err(InvalidStartClaims)
  }
  let seen = Array::make(progress.keys.length(), false)
  let claimed_task_keys = []
  for claim in claims {
    let mut ordinal = None
    for task in 0..<progress.keys.length() {
      if progress.keys[task] == claim.task_key {
        ordinal = Some(task)
      }
    }
    guard ordinal is Some(task) else { return Err(InvalidStartClaims) }
    if seen[task] ||
      (claim.physical_start_claimed && !claim.dispatch_reserved) ||
      claim.dispatch_reserved != (claim.dispatch_cid is Some(_)) {
      return Err(InvalidStartClaims)
    }
    if claim.dispatch_cid is Some(cid) && !valid_client_request_cid(cid) {
      return Err(InvalidStartClaims)
    }
    seen[task] = true
    match progress.requests[task] {
      Some(request) =>
        if claim.dispatch_cid !=
          Some(@remote.dispatch_request_identity(request)) {
          return Err(InvalidStartClaims)
        }
      None => ()
    }
    if claim.physical_start_claimed ||
      (claim.dispatch_reserved && progress.requests[task] is None) {
      claimed_task_keys.push(claim.task_key)
    }
  }
  project_bound_client_remote_task_run(
    progress, observed_at, cancellation_requested, claimed_task_keys, true,
  ).map(projection => { original: value, projection, })
}

///|
pub fn client_remote_effect_task_run_projection_fields(
  value : ClientRemoteEffectTaskRunProjection,
) -> Array[String] {
  client_remote_task_run_projection_fields(value.projection)
}

///|
pub fn client_remote_effect_task_run_projection_work(
  value : ClientRemoteEffectTaskRunProjection,
) -> Array[String] {
  client_remote_task_run_projection_work(value.projection)
}
