///|
// Issue only a Submission reference under the already acquired original Read.
// No business preparation, Run, execution supply or initialization is selected.
// The existing Epoch Owner retains its clock, current Account and lost-COMMIT
// semantics; a failure never retries issuance or falls through to raw loading.
fn local_new_submission_reference(
  settings : LocalHostSettings,
  capture : @local_host.NativeLocalJournalCapture,
  child : @argparse.Matches,
) -> String raise ClientStop {
  let scope = local_host_result(
    capture.authority_scope_cid_in_original_read(
      settings.principal,
      settings.connection,
    ),
  )
  let epoch = match
    capture.issue_epoch_in_original_read(
      settings.principal,
      settings.connection,
      scope,
      @env.now().to_double(),
    ) {
    Ok(value) => value
    Err(
      @local_host.Epoch(TransactionUnknown)
      | @local_host.InstallationReadTransactionFailure(_, TransactionUnknown)
    ) => stop("LocalSubmissionEpochUnknown")
    Err(@local_host.Epoch(Fenced)) => stop("LocalSubmissionEpochFenced")
    Err(@local_host.Epoch(AuthorizationDenied)) =>
      stop("LocalSubmissionAuthorizationDenied")
    Err(_) => stop("LocalSubmissionEpochUnavailable")
  }
  let reference = @local_host.prepare_native_client_submission_reference(
    epoch,
    required(child, "request-id"),
  ).unwrap_or_else(() => stop("InvalidSubmissionRef"))
  // Issuance may advance the durable clock. Preserve the original current
  // boundary before disclosing this reference; it is never an execution grant.
  guard capture.authority_scope_cid_in_original_read(
      settings.principal,
      settings.connection,
    )
    is Ok(current) &&
    current == scope &&
    capture.authorize_in_original_read({
      principal: settings.principal,
      connection: settings.connection,
      resource: "run",
      operation: "submit",
    })
    is Ok(Allow(_)) else {
    stop("LocalSubmissionAuthorizationDenied")
  }
  @local_host.native_client_submission_reference_wire(reference)
}

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
  local_run_nonce_text(bytes)
}

///|
// Encoding only. The selected caller obtains these bytes from its actual
// captured Library, rather than importing another Library into the Read.
fn local_run_nonce_text(bytes : Bytes) -> String {
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
  business? : LocalCommandBusinessPreparation? = None,
) -> LocalRunSubmission raise ClientStop {
  native_timing_begin(22)
  defer native_timing_end(22)
  if business is Some(original) && original.submission is Some(selected) {
    if selected.fresh ||
      optional(child, "operation-attempt-id") != Some(selected.attempt) ||
      !local_submission_nonce_matches(
        selected.reference,
        optional(child, "request-id"),
      ) {
      stop("LocalSubmissionIdentityMismatch")
    }
    return selected
  }
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
      let current = () => {
        match business {
          None => local_submit_allowed(host, settings, crypto, scope)
          Some(original) =>
            original.current(host, settings, original.environment)
        }
      }
      if !current() {
        stop("LocalSubmissionAuthorizationDenied")
      }
      let issued = match business {
        None => {
          let authority = local_host_result(host.epoch_authority())
          authority.issue_epoch(scope, current(), @env.now().to_double())
        }
        Some(original) => {
          if original.scope != scope || !current() {
            stop("LocalSubmissionAuthorizationDenied")
          }
          match
            original.capture.issue_epoch_in_original_read(
              settings.principal,
              settings.connection,
              scope,
              @env.now().to_double(),
            ) {
            Ok(epoch) => Ok(epoch)
            Err(@local_host.Epoch(issue)) => Err(issue)
            Err(
              @local_host.InstallationReadTransactionFailure(
                _,
                TransactionUnknown
              )
            ) => Err(TransactionUnknown)
            Err(_) => stop("LocalSubmissionEpochUnavailable")
          }
        }
      }
      let epoch = match issued {
        Ok(value) => value
        Err(TransactionUnknown) => stop("LocalSubmissionEpochUnknown")
        Err(Fenced) => stop("LocalSubmissionEpochFenced")
        Err(AuthorizationDenied) => stop("LocalSubmissionAuthorizationDenied")
        Err(_) => stop("LocalSubmissionEpochUnavailable")
      }
      let reference = @local_host.prepare_native_client_submission_reference(
        epoch,
        match business {
          None => local_run_random_nonce(crypto)
          Some(original) =>
            local_run_nonce_text(
              local_host_result(
                original.capture.submission_nonce_in_original_read(
                  settings.principal,
                  settings.connection,
                  scope,
                ),
              ),
            )
        },
      ).unwrap_or_else(() => stop("InvalidSubmissionRef"))
      let attempt = match business {
        None => local_run_random_nonce(crypto)
        Some(original) =>
          local_run_nonce_text(
            local_host_result(
              original.capture.submission_nonce_in_original_read(
                settings.principal,
                settings.connection,
                scope,
              ),
            ),
          )
      }
      if !current() {
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

///|
// Caller flow only. These cases grant no acceptance, new identity or attempt.
priv enum LocalRunSubmissionPreflight {
  FreshSubmissionInput
  ExplicitSubmissionInput(LocalRunSubmission, @run_host.ClientSubmittedIntent)
  RetainedSubmissionRun(@local_host.NativeClientSavedRunStateSelection)
}

///|
// Read the supplied original once before business preparation. An admitted
// Run returns its saved state without checking/compiling the current Program.
// A preparing intent retains its exact original input for the existing first
// completion/CAS path; unresolved history never proves nonacceptance.
fn local_explicit_submission_preflight(
  host : @local_host.NativeLocalHostConnection,
  capture : @local_host.NativeLocalJournalCapture,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  input_root : String,
  operation : String,
  child : @argparse.Matches,
) -> LocalRunSubmissionPreflight raise ClientStop {
  match
    (
      optional(child, "submission-ref-file"),
      optional(child, "operation-attempt-id"),
    ) {
    (None, None) => return FreshSubmissionInput
    (Some(_), Some(_)) => ()
    _ => stop("OriginalSubmissionReferenceRequired")
  }
  let scope = local_host_result(
    capture.authority_scope_cid_in_original_read(
      settings.principal,
      settings.connection,
    ),
  )
  if !local_run_operation_allowed(
      host,
      settings,
      crypto,
      scope,
      "submit",
      capture=Some(capture),
    ) {
    stop("LocalSubmissionAuthorizationDenied")
  }
  // Only the explicit branch is reachable. It reads the original bounded
  // file and attempt; it cannot enter fresh Epoch/nonce issuance.
  let selection = local_select_run_submission(
    host, settings, crypto, scope, input_root, child, true,
  )
  if selection.fresh {
    stop("OriginalSubmissionReferenceRequired")
  }
  let intent = @run_host.prepare_client_submitted_intent(
    local_intent_wire(input_root, operation, child),
    65536,
    8192,
    64,
  ).unwrap_or_else(() => stop("LocalSubmittedInputNotAdmitted"))
  let observed = local_host_result(
    capture.lookup_submitted_intent_in_original_read(
      settings.principal,
      settings.connection,
      scope,
      selection.reference,
      @env.now().to_double(),
    ),
  )
  match observed {
    UnresolvedSubmissionHistory => ExplicitSubmissionInput(selection, intent)
    Submitted(record) => {
      let original_intent = @local_host.native_client_submitted_intent(record)
      if @run_host.client_submitted_intent_wire(original_intent) !=
        @run_host.client_submitted_intent_wire(intent) {
        stop("LocalSubmissionIntentConflict")
      }
      if @local_host.native_client_submitted_preparation_problem(record)
        is Some(_) {
        stop("LocalSubmissionPreparationFailed")
      }
      match @local_host.native_client_submitted_run_admission(record) {
        None => ExplicitSubmissionInput(selection, original_intent)
        Some(_) =>
          RetainedSubmissionRun(
            local_public_run_state_selection(
              host,
              settings,
              crypto,
              selection.reference,
              capture=Some(capture),
            ),
          )
      }
    }
  }
}
