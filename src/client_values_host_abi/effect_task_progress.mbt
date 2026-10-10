///|
#export_name("clientValuesHostInspectEffectTaskProgress")
pub fn client_values_host_inspect_effect_task_progress(
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  authority : String,
  wires : Array[String],
) -> Result[@host.ClientRemoteEffectTaskProgress, Unit] {
  let saved = []
  for wire in wires {
    match
      @remote.admit_durable_coordinator_dispatch_record(@utf8.encode(wire)) {
      Ok(value) => saved.push(value)
      Err(_) => return Err(())
    }
  }
  @host.inspect_client_remote_effect_task_progress(
    allowed, definition, authority, saved,
  ).map_err(_ => ())
}

///|
#export_name("clientValuesHostEffectTaskProgressNext")
pub fn client_values_host_effect_task_progress_next(
  value : @host.ClientRemoteEffectTaskProgress,
) -> Int {
  @host.client_remote_effect_task_progress_next_task(value).unwrap_or(-1)
}

///|
#export_name("clientValuesHostEffectTaskProgressComputationComplete")
pub fn client_values_host_effect_task_progress_computation_complete(
  value : @host.ClientRemoteEffectTaskProgress,
) -> Bool {
  @host.client_remote_effect_task_progress_computation_complete(value)
}

///|
#export_name("clientValuesHostEffectTaskProgressTaskCleanupComplete")
pub fn client_values_host_effect_task_progress_task_cleanup_complete(
  value : @host.ClientRemoteEffectTaskProgress,
) -> Bool {
  @host.client_remote_effect_task_progress_task_cleanup_complete(value)
}

///|
#export_name("clientValuesHostEffectTaskProgressResultTasks")
pub fn client_values_host_effect_task_progress_result_tasks(
  value : @host.ClientRemoteEffectTaskProgress,
) -> Array[Int] {
  @host.client_remote_effect_task_progress_result_tasks(value)
}

///|
#export_name("clientValuesHostEffectTaskProgressFields")
pub fn client_values_host_effect_task_progress_fields(
  value : @host.ClientRemoteEffectTaskProgress,
) -> Array[Array[String]] {
  @host.client_remote_effect_task_progress_fields(value)
}

///|
#export_name("clientValuesHostEffectTaskProgressScopes")
pub fn client_values_host_effect_task_progress_scopes(
  value : @host.ClientRemoteEffectTaskProgress,
) -> Array[Array[String]] {
  @host.client_remote_effect_task_progress_scopes(value)
}

///|
#export_name("clientValuesHostPrepareEffectTaskPhysicalStart")
pub fn client_values_host_prepare_effect_task_physical_start(
  progress : @host.ClientRemoteEffectTaskProgress,
  task_key : String,
  dispatch_cid : String,
  requested : @host.ClientRequestIdentity,
  retained : @host.ClientRequestIdentity,
  definition_cid : String,
  reserved : Bool,
  unstarted : Bool,
  authorized : Bool,
  cancelled : Bool,
  failed : Bool,
) -> Result[Bool, Unit] {
  @host.prepare_client_remote_effect_task_physical_start(
    progress, task_key, dispatch_cid, requested, retained, definition_cid, reserved,
    unstarted, authorized, cancelled, failed,
  ).map_err(_ => ())
}
