///|
pub type SubmissionEpoch = @request_scope.SubmissionEpoch

///|
pub type SubmissionIdentityIssue = @request_scope.SubmissionIdentityIssue

///|
pub type SubmissionEpochValidity = @request_scope.SubmissionEpochValidity

///|
pub fn prepare_submission_epoch(
  authority_scope_cid : String,
  epoch_nonce : String,
  not_before : Double,
  expires_at : Double,
) -> Result[SubmissionEpoch, SubmissionIdentityIssue] {
  @request_scope.prepare_submission_epoch(
    authority_scope_cid, epoch_nonce, not_before, expires_at,
  )
}

///|
pub fn submission_epoch_wire(epoch : SubmissionEpoch) -> String {
  @request_scope.submission_epoch_wire(epoch)
}

///|
pub fn submission_epoch_cid(epoch : SubmissionEpoch) -> String {
  @request_scope.submission_epoch_cid(epoch)
}

///|
pub fn submission_epoch_validity(
  epoch : SubmissionEpoch,
  now : Double,
) -> Result[SubmissionEpochValidity, SubmissionIdentityIssue] {
  @request_scope.submission_epoch_validity(epoch, now)
}

///|
pub fn submission_request_id(
  epoch : SubmissionEpoch,
  caller_nonce : String,
) -> Result[String, SubmissionIdentityIssue] {
  @request_scope.submission_request_id(epoch, caller_nonce)
}
