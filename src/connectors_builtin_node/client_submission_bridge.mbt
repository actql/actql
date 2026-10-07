///|
/// Physical authentication is performed by the installed Host. This bridge
/// transfers the checked interval and exact submission identity to its journal.
#export_name("clientSubmissionEpoch")
pub fn client_submission_epoch(
  authority_scope_cid : String,
  epoch_nonce : String,
  not_before : Double,
  expires_at : Double,
) -> @publication_host.SubmissionEpoch? {
  match
    @publication_host.prepare_submission_epoch(
      authority_scope_cid, epoch_nonce, not_before, expires_at,
    ) {
    Ok(epoch) => Some(epoch)
    Err(_) => None
  }
}

///|
#export_name("clientSubmissionEpochWire")
pub fn client_submission_epoch_wire(
  epoch : @publication_host.SubmissionEpoch,
) -> String {
  @publication_host.submission_epoch_wire(epoch)
}

///|
#export_name("clientSubmissionEpochCid")
pub fn client_submission_epoch_cid(
  epoch : @publication_host.SubmissionEpoch,
) -> String {
  @publication_host.submission_epoch_cid(epoch)
}

///|
#export_name("clientSubmissionEpochValidity")
pub fn client_submission_epoch_validity(
  epoch : @publication_host.SubmissionEpoch,
  now : Double,
) -> String? {
  match @publication_host.submission_epoch_validity(epoch, now) {
    Ok(Admissible) => Some("admissible")
    Ok(NotYetValid) => Some("not_yet_valid")
    Ok(Expired) => Some("expired")
    Err(_) => None
  }
}

///|
#export_name("clientSubmissionRequestId")
pub fn client_submission_request_id(
  epoch : @publication_host.SubmissionEpoch,
  caller_nonce : String,
) -> String? {
  match @publication_host.submission_request_id(epoch, caller_nonce) {
    Ok(identity) => Some(identity)
    Err(_) => None
  }
}

///|
#export_name("clientSubmittedIntent")
pub fn client_submitted_intent(
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @publication_host.ClientSubmittedIntent? {
  match
    @publication_host.prepare_client_submitted_intent(
      wire, max_bytes, max_nodes, max_depth,
    ) {
    Ok(intent) => Some(intent)
    Err(_) => None
  }
}

///|
#export_name("clientSubmittedIntentWire")
pub fn client_submitted_intent_wire(
  value : @publication_host.ClientSubmittedIntent,
) -> String {
  @publication_host.client_submitted_intent_wire(value)
}

///|
#export_name("clientSubmittedIntentCid")
pub fn client_submitted_intent_cid(
  value : @publication_host.ClientSubmittedIntent,
) -> String {
  @publication_host.client_submitted_intent_cid(value)
}

///|
#export_name("clientSubmittedIntentTransition")
pub fn client_submitted_intent_transition(
  before : String,
  after : String,
) -> Bool {
  @publication_host.client_submitted_intent_transition(before, after)
}
