///|
/// The Host supplies already-persisted Coordinator bytes. The common owners
/// admit them and select readiness from the original checked dependency graph.
#export_name("clientValuesHostInspectTaskProgress")
pub fn client_values_host_inspect_task_progress(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  authority : String,
  wires : Array[String],
) -> Result[@host.ClientRemoteTaskProgress, Unit] {
  let saved : Array[@remote.DurableCoordinatorDispatchRecord] = []
  for wire in wires {
    match
      @remote.admit_durable_coordinator_dispatch_record(@utf8.encode(wire)) {
      Ok(value) => saved.push(value)
      Err(_) => return Err(())
    }
  }
  @host.inspect_client_remote_task_progress(
    prepared, compilation, admission, definition, authority, saved,
  ).map_err(_ => ())
}

///|
#export_name("clientValuesHostTaskProgressNext")
pub fn client_values_host_task_progress_next(
  value : @host.ClientRemoteTaskProgress,
) -> Int {
  @host.client_remote_task_progress_next_task(value).unwrap_or(-1)
}

///|
#export_name("clientValuesHostTaskProgressExecutionComplete")
pub fn client_values_host_task_progress_execution_complete(
  value : @host.ClientRemoteTaskProgress,
) -> Bool {
  @host.client_remote_task_progress_execution_complete(value)
}

///|
#export_name("clientValuesHostTaskProgressCleanupComplete")
pub fn client_values_host_task_progress_cleanup_complete(
  value : @host.ClientRemoteTaskProgress,
) -> Bool {
  @host.client_remote_task_progress_cleanup_complete(value)
}

///|
#export_name("clientValuesHostTaskProgressResultTasks")
pub fn client_values_host_task_progress_result_tasks(
  value : @host.ClientRemoteTaskProgress,
) -> Array[Int] {
  @host.client_remote_task_progress_result_tasks(value)
}

///|
#export_name("clientValuesHostTaskProgressFields")
pub fn client_values_host_task_progress_fields(
  value : @host.ClientRemoteTaskProgress,
) -> Array[Array[String]] {
  @host.client_remote_task_progress_fields(value)
}

///|
#export_name("clientValuesHostTaskProgressScopes")
pub fn client_values_host_task_progress_scopes(
  value : @host.ClientRemoteTaskProgress,
) -> Array[Array[String]] {
  @host.client_remote_task_progress_scopes(value)
}
