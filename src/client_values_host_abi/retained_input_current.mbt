///|
pub struct ClientValuesHostRetainedInputQuery {
  plan : ClientValuesHostRetainedInputPlan
  query : @remote.RemotePollRetainedCurrent
  envelope : String
}

///|
#export_name("clientValuesHostPrepareRetainedInputCurrentQuery")
pub fn client_values_host_prepare_retained_input_current_query(
  plan : ClientValuesHostRetainedInputPlan,
  query_id : String,
) -> Result[
  ClientValuesHostRetainedInputQuery,
  @host.ClientRetainedTaskInputIssue,
] {
  match client_values_host_validate_retained_input_plan(plan) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let envelope = match
    @remote.remote_poll_retained_input_current_json(plan.plan, query_id) {
    Ok(value) => value
    Err(_) => return Err(@host.Encoding)
  }
  let query = match
    @remote.admit_remote_poll_retained_input_current_json(envelope) {
    Ok(value) => value
    Err(_) => return Err(@host.Encoding)
  }
  Ok({ plan, query, envelope, })
}

///|
#export_name("clientValuesHostRetainedInputCurrentEnvelope")
pub fn client_values_host_retained_input_current_envelope(
  query : ClientValuesHostRetainedInputQuery,
) -> Result[String, @host.ClientRetainedTaskInputIssue] {
  client_values_host_validate_retained_input_plan(query.plan).map(_ => {
    query.envelope
  })
}

///|
/// This is exact admission of a fresh authenticated response. Its bytes are
/// not a durable substitute for a subsequent query to current trusted Owners.
#export_name("clientValuesHostAdmitRetainedInputCurrentReply")
pub fn client_values_host_admit_retained_input_current_reply(
  query : ClientValuesHostRetainedInputQuery,
  body : String,
  cid : String,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[
  @remote.RemoteRetainedCurrentReply,
  @host.ClientRetainedTaskInputIssue,
] {
  match client_values_host_validate_retained_input_plan(query.plan) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let reply = match
    @remote.admit_remote_retained_input_current_reply_json(
      body,
      cid,
      query.query,
      max_chunks,
      max_manifest_bytes,
      max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(@host.ForeignTransfer)
  }
  client_values_host_validate_retained_input_plan(query.plan).map(_ => reply)
}

///|
#export_name("clientValuesHostRetainedInputCurrentReplyFacts")
pub fn client_values_host_retained_input_current_reply_facts(
  reply : @remote.RemoteRetainedCurrentReply,
) -> Result[Array[String], @host.ClientRetainedTaskInputIssue] {
  let receipt = @remote.remote_retained_input_current_reply_receipt(reply)
  let receipt_json = match @transfer.destination_receipt_json(receipt) {
    Ok(value) => value
    Err(_) => return Err(@host.Encoding)
  }
  Ok([
    @remote.remote_retained_input_current_reply_identity(reply),
    @remote.remote_retained_input_current_reply_json(reply),
    @remote.remote_retained_input_current_reply_transfer_record_json(reply),
    @transfer.destination_receipt_cid(receipt),
    receipt_json,
  ])
}
