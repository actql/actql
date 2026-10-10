///|
/// Portable metadata admission only. The receiving Host must authenticate the
/// current Site and commit the original Run's waiting projection separately.
#export_name("coordinatorEffectCheckpointReportAdmit")
pub fn coordinator_effect_checkpoint_report_admit(
  body : String,
  request : @remote.DispatchRequest,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@remote.RemoteEffectCheckpointReport, @remote.DispatchIssue] {
  @remote.admit_remote_effect_checkpoint_report_json(body, request, {
    max_wire_bytes,
    max_nodes,
    max_depth,
  })
}

///|
#export_name("coordinatorEffectCheckpointReportProjection")
pub fn coordinator_effect_checkpoint_report_projection(
  report : @remote.RemoteEffectCheckpointReport,
) -> Array[String] {
  let artifact = @remote.remote_effect_checkpoint_report_checkpoint(report)
  [
    @remote.remote_effect_checkpoint_report_identity(report),
    @remote.dispatch_request_identity(
      @remote.remote_effect_checkpoint_report_dispatch(report),
    ),
    artifact.checkpoint_cid,
    artifact.wire,
  ]
}

///|
/// Call only after the receiving Run Owner has durably committed waiting.
#export_name("coordinatorEffectCheckpointAcceptedJson")
pub fn coordinator_effect_checkpoint_accepted_json(
  report : @remote.RemoteEffectCheckpointReport,
) -> Result[String, @remote.DispatchIssue] {
  @remote.remote_effect_checkpoint_reply_json(report, @remote.Accepted)
}

///|
#export_name("coordinatorEffectCheckpointRefusedJson")
pub fn coordinator_effect_checkpoint_refused_json(
  report : @remote.RemoteEffectCheckpointReport,
  reason : String,
) -> Result[String, @remote.DispatchIssue] {
  @remote.remote_effect_checkpoint_reply_json(report, @remote.Refused(reason))
}

///|
#export_name("coordinatorEffectCheckpointReplyAdmit")
pub fn coordinator_effect_checkpoint_reply_admit(
  report : @remote.RemoteEffectCheckpointReport,
  body : String,
) -> Result[Array[String], @remote.DispatchIssue] {
  match @remote.admit_remote_effect_checkpoint_reply_json(body, report) {
    Ok(@remote.Accepted) => Ok(["accepted", ""])
    Ok(@remote.Refused(reason)) => Ok(["refused", reason])
    Err(issue) => Err(issue)
  }
}
