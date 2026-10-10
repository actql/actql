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
