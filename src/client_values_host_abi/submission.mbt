///|
/// Existing identity and intent Owners for portable Host consumers. Physical
/// authentication, durable custody and Run acceptance remain Host obligations.
#export_name("clientValuesHostSubmissionEpoch")
pub fn client_values_host_submission_epoch(
  authority_scope_cid : String,
  epoch_nonce : String,
  not_before : Double,
  expires_at : Double,
) -> @host.SubmissionEpoch? {
  match
    @host.prepare_submission_epoch(
      authority_scope_cid, epoch_nonce, not_before, expires_at,
    ) {
    Ok(epoch) => Some(epoch)
    Err(_) => None
  }
}

///|
#export_name("clientValuesHostSubmissionEpochWire")
pub fn client_values_host_submission_epoch_wire(
  epoch : @host.SubmissionEpoch,
) -> String {
  @host.submission_epoch_wire(epoch)
}

///|
#export_name("clientValuesHostSubmissionEpochCid")
pub fn client_values_host_submission_epoch_cid(
  epoch : @host.SubmissionEpoch,
) -> String {
  @host.submission_epoch_cid(epoch)
}

///|
#export_name("clientValuesHostSubmissionEpochValidity")
pub fn client_values_host_submission_epoch_validity(
  epoch : @host.SubmissionEpoch,
  now : Double,
) -> String? {
  match @host.submission_epoch_validity(epoch, now) {
    Ok(Admissible) => Some("admissible")
    Ok(NotYetValid) => Some("not_yet_valid")
    Ok(Expired) => Some("expired")
    Err(_) => None
  }
}

///|
#export_name("clientValuesHostSubmissionRequestId")
pub fn client_values_host_submission_request_id(
  epoch : @host.SubmissionEpoch,
  caller_nonce : String,
) -> String? {
  match @host.submission_request_id(epoch, caller_nonce) {
    Ok(identity) => Some(identity)
    Err(_) => None
  }
}

///|
#export_name("clientValuesHostSubmittedIntent")
pub fn client_values_host_submitted_intent(
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @host.ClientSubmittedIntent? {
  match
    @host.prepare_client_submitted_intent(wire, max_bytes, max_nodes, max_depth) {
    Ok(intent) => Some(intent)
    Err(_) => None
  }
}

///|
#export_name("clientValuesHostSubmittedIntentWire")
pub fn client_values_host_submitted_intent_wire(
  value : @host.ClientSubmittedIntent,
) -> String {
  @host.client_submitted_intent_wire(value)
}

///|
#export_name("clientValuesHostSubmittedIntentCid")
pub fn client_values_host_submitted_intent_cid(
  value : @host.ClientSubmittedIntent,
) -> String {
  @host.client_submitted_intent_cid(value)
}

///|
#export_name("clientValuesHostSubmittedIntentTransition")
pub fn client_values_host_submitted_intent_transition(
  before : String,
  after : String,
) -> Bool {
  @host.client_submitted_intent_transition(before, after)
}
