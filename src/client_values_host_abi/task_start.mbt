///|
#export_name("clientValuesHostPrepareRemoteTaskPhysicalStart")
pub fn client_values_host_prepare_remote_task_physical_start(
  progress : @host.ClientRemoteTaskProgress,
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
  @host.prepare_client_remote_task_physical_start(
    progress, task_key, dispatch_cid, requested, retained, definition_cid, reserved,
    unstarted, authorized, cancelled, failed,
  ).map_err(_ => ())
}
