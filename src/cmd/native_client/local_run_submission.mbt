///|
// Invocation correlation only, not a Run, authorization or retry decision.
// An explicit original remains the caller's recovery selection. The public
// fresh spelling allocates once and never enters that branch again on error.
priv struct LocalRunSubmission {
  reference : @local_host.NativeClientSubmissionReference
  attempt : String
  fresh : Bool
}

///|
fn local_run_random_nonce(
  crypto : @local_crypto.Library,
) -> String raise ClientStop {
  let bytes = crypto
    .random_bytes(32)
    .unwrap_or_else(() => stop("LocalSubmissionNonceUnavailable"))
  let out = StringBuilder()
  out.write_string("cli-")
  for byte in bytes {
    let hex = byte.to_hex()
    if hex.length() == 1 {
      out.write_char('0')
    }
    out.write_string(hex)
  }
  out.to_string()
}

///|
fn local_select_run_submission(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  scope : String,
  input_root : String,
  child : @argparse.Matches,
  public_run : Bool,
) -> LocalRunSubmission raise ClientStop {
  match
    (
      optional(child, "submission-ref-file"),
      optional(child, "operation-attempt-id"),
    ) {
    (Some(file), Some(attempt)) => {
      let reference = @local_host.admit_native_client_submission_reference(
        text_file(input_root, file, 4096L),
      ).unwrap_or_else(() => stop("InvalidSubmissionRef"))
      if !local_submission_nonce_matches(
          reference,
          optional(child, "request-id"),
        ) {
        stop("LocalSubmissionIdentityMismatch")
      }
      if attempt.is_empty() || attempt.length() > 128 {
        stop("InvalidOperationAttemptReference")
      }
      { reference, attempt, fresh: false, }
    }
    (None, None) if public_run => {
      // request-id retains its existing meaning: an assertion of the saved
      // original nonce. It is not a request to issue another epoch on retry.
      if optional(child, "request-id") is Some(_) {
        stop("OriginalSubmissionReferenceRequired")
      }
      if !local_submit_allowed(host, settings, crypto, scope) {
        stop("LocalSubmissionAuthorizationDenied")
      }
      let authority = local_host_result(host.epoch_authority())
      let epoch = match
        authority.issue_epoch(
          scope,
          local_submit_allowed(host, settings, crypto, scope),
          @env.now().to_double(),
        ) {
        Ok(value) => value
        Err(TransactionUnknown) => stop("LocalSubmissionEpochUnknown")
        Err(Fenced) => stop("LocalSubmissionEpochFenced")
        Err(AuthorizationDenied) => stop("LocalSubmissionAuthorizationDenied")
        Err(_) => stop("LocalSubmissionEpochUnavailable")
      }
      let reference = @local_host.prepare_native_client_submission_reference(
        epoch,
        local_run_random_nonce(crypto),
      ).unwrap_or_else(() => stop("InvalidSubmissionRef"))
      let attempt = local_run_random_nonce(crypto)
      if !local_submit_allowed(host, settings, crypto, scope) {
        stop("LocalSubmissionAuthorizationDenied")
      }
      { reference, attempt, fresh: true, }
    }
    _ => stop("OriginalSubmissionReferenceRequired")
  }
}

///|
// Preserve the original typed failure, including Unknown/cleanup pending.
// Public correlation lets a later authorized lookup reconcile this operation;
// it never declares a failure absent or grants permission to repeat a send.
fn local_run_submission_failure(
  selection : LocalRunSubmission,
  original : String,
) -> String {
  if !selection.fresh {
    return original
  }
  original +
  " originalSubmissionRequestId=" +
  @local_host.native_client_submission_request_id(selection.reference) +
  " originalOperationAttemptId=" +
  selection.attempt +
  " (reconcile with lookup-request; do not resend this operation)"
}
