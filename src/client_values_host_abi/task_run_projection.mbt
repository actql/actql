///|
#export_name("clientValuesHostProjectRemoteTaskRun")
pub fn client_values_host_project_remote_task_run(
  progress : @host.ClientRemoteTaskProgress,
  observed_at : String,
  cancellation_requested : Bool,
  claimed_task_keys : Array[String],
) -> Result[@host.ClientRemoteTaskRunProjection, Unit] {
  @host.project_client_remote_task_run(
    progress, observed_at, cancellation_requested, claimed_task_keys,
  ).map_err(_ => ())
}

///|
#export_name("clientValuesHostRemoteTaskRunFields")
pub fn client_values_host_remote_task_run_fields(
  value : @host.ClientRemoteTaskRunProjection,
) -> Array[String] {
  @host.client_remote_task_run_projection_fields(value)
}

///|
#export_name("clientValuesHostRemoteTaskRunWork")
pub fn client_values_host_remote_task_run_work(
  value : @host.ClientRemoteTaskRunProjection,
) -> Array[String] {
  @host.client_remote_task_run_projection_work(value)
}
