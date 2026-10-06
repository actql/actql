///|
/// Policy selected by the existing trusted Transfer/grant owners. The checked
/// producer supplies every edge and completion field; these values do not
/// authorize a handoff until the complete physical request is checked.
pub(all) struct ClientRetainedInputTransferPolicy {
  destination_grant_cid : String
  route_capability_cid : String
  source_grant_cid : String
  transfer_attempt : String
  transfer_expires_unix_ms : Int64
  transfer_max_bytes : Int64
}

///|
pub fn prepare_client_retained_input_intent(
  producer : ClientRetainedInputProducer,
  policy : ClientRetainedInputTransferPolicy,
) -> Result[@remote.RemoteRetainedInputIntent, ClientRetainedTaskInputIssue] {
  if !client_retained_input_producer_available(producer) {
    return Err(ProducerUnavailable)
  }
  let edge = client_retained_input_edge_projection(producer.edge)
  match
    @remote.prepare_remote_retained_input_intent(producer.request, {
      consumer_input_port: edge[7],
      consumer_logical_cid: edge[6],
      consumer_task_key: edge[5],
      destination_grant_cid: policy.destination_grant_cid,
      producer_evidence_cid: @remote.remote_execution_evidence_cid(
        producer.evidence,
      ),
      producer_logical_cid: edge[3],
      producer_output_port: edge[2],
      producer_schema_cid: client_retained_input_edge_schema_cid(producer.edge),
      producer_subject_cid: @remote.remote_managed_output_subject_cid(
        producer.subject,
      ),
      route_capability_cid: policy.route_capability_cid,
      source_grant_cid: policy.source_grant_cid,
      transfer_attempt: policy.transfer_attempt,
      transfer_expires_unix_ms: policy.transfer_expires_unix_ms,
      transfer_max_bytes: policy.transfer_max_bytes,
    }) {
    Ok(value) => Ok(value)
    Err(_) => Err(InvalidBinding)
  }
}

///|
/// Re-admit the saved intent against the current checked producer. Canonical
/// protocol equality alone cannot establish a checked edge or availability.
pub fn validate_client_retained_input_intent(
  producer : ClientRetainedInputProducer,
  intent : @remote.RemoteRetainedInputIntent,
) -> Result[Unit, ClientRetainedTaskInputIssue] {
  let selected = @remote.remote_retained_input_intent_projection(intent)
  let expected = match
    prepare_client_retained_input_intent(producer, {
      destination_grant_cid: selected.destination_grant_cid,
      route_capability_cid: selected.route_capability_cid,
      source_grant_cid: selected.source_grant_cid,
      transfer_attempt: selected.transfer_attempt,
      transfer_expires_unix_ms: selected.transfer_expires_unix_ms,
      transfer_max_bytes: selected.transfer_max_bytes,
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @remote.remote_retained_input_intent_identity(intent) !=
    @remote.remote_retained_input_intent_identity(expected) ||
    @remote.remote_retained_input_intent_json(intent) !=
    @remote.remote_retained_input_intent_json(expected) {
    return Err(InvalidBinding)
  }
  Ok(())
}
