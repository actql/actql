///|
/// Metadata query construction; trusted Cloud Owners select the original member.
#export_name("coordinatorEffectCurrentQueryPrepare")
pub fn coordinator_effect_current_query_prepare(
  report : @remote.RemoteEffectCheckpointReport,
  effect_id : String,
  query_id : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@remote.RemoteEffectCurrentQuery, @remote.DispatchIssue] {
  @remote.prepare_remote_effect_current_query(report, effect_id, query_id, {
    max_wire_bytes,
    max_nodes,
    max_depth,
  })
}

///|
#export_name("coordinatorEffectCurrentQueryProjection")
pub fn coordinator_effect_current_query_projection(
  query : @remote.RemoteEffectCurrentQuery,
) -> Array[String] {
  let report = @remote.remote_effect_current_query_report(query)
  [
    @remote.remote_effect_current_query_json(query),
    @remote.remote_effect_current_query_identity(query),
    @remote.remote_effect_checkpoint_report_identity(report),
    @remote.dispatch_request_identity(
      @remote.remote_effect_checkpoint_report_dispatch(report),
    ),
    @remote.remote_effect_checkpoint_report_checkpoint(report).checkpoint_cid,
    @remote.remote_effect_current_query_effect_id(query),
    @remote.remote_effect_current_query_id(query),
  ]
}

///|
/// Admission is correlation only, not physical/current Site or Ledger proof.
#export_name("coordinatorEffectCurrentReplyAdmit")
pub fn coordinator_effect_current_reply_admit(
  query : @remote.RemoteEffectCurrentQuery,
  body : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@remote.RemoteEffectCurrentReply, @remote.DispatchIssue] {
  @remote.admit_remote_effect_current_reply_json(query, body, {
    max_wire_bytes,
    max_nodes,
    max_depth,
  })
}

///|
#export_name("coordinatorEffectCurrentReplyProjection")
pub fn coordinator_effect_current_reply_projection(
  reply : @remote.RemoteEffectCurrentReply,
) -> Array[String] {
  let (head, action, saved) = @remote.remote_effect_current_reply_facts(reply)
  [
    @remote.remote_effect_current_reply_json(reply),
    @remote.remote_effect_current_reply_identity(reply),
    head.unwrap_or(""),
    action.to_string(),
    saved.to_string(),
  ]
}

///|
/// Poll routing derives its dispatch from the original query Owner.
#export_name("coordinatorEffectCurrentPollJson")
pub fn coordinator_effect_current_poll_json(
  query : @remote.RemoteEffectCurrentQuery,
) -> Result[String, @remote.DispatchIssue] {
  @remote.remote_poll_effect_current_json(query)
}
