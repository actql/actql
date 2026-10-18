///|
#export_name("clientValuesHostProjectEffectTaskRun")
pub fn client_values_host_project_effect_task_run(
  progress : @host.ClientRemoteEffectTaskProgress,
  observed_at : String,
  cancellation_requested : Bool,
  task_keys : Array[String],
  dispatch_cids : Array[String],
  reserved : Array[Bool],
  physically_claimed : Array[Bool],
) -> Result[@host.ClientRemoteEffectTaskRunProjection, Unit] {
  if task_keys.length() != dispatch_cids.length() ||
    task_keys.length() != reserved.length() ||
    task_keys.length() != physically_claimed.length() {
    return Err(())
  }
  let claims : Array[@host.ClientRemoteEffectTaskRunClaim] = task_keys.mapi((
    index,
    task_key,
  ) => {
    task_key,
    dispatch_cid: if dispatch_cids[index].is_empty() {
      None
    } else {
      Some(dispatch_cids[index])
    },
    dispatch_reserved: reserved[index],
    physical_start_claimed: physically_claimed[index],
  })
  @host.project_client_remote_effect_task_run(
    progress, observed_at, cancellation_requested, claims,
  ).map_err(_ => ())
}

///|
#export_name("clientValuesHostEffectTaskRunFields")
pub fn client_values_host_effect_task_run_fields(
  value : @host.ClientRemoteEffectTaskRunProjection,
) -> Array[String] {
  @host.client_remote_effect_task_run_projection_fields(value)
}

///|
#export_name("clientValuesHostEffectTaskRunWork")
pub fn client_values_host_effect_task_run_work(
  value : @host.ClientRemoteEffectTaskRunProjection,
) -> Array[String] {
  @host.client_remote_effect_task_run_projection_work(value)
}
