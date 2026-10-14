///|
// Saved Owner observation only. A status query never prepares, starts, reads
// payload bytes, grants access or reconstructs missing legacy state.
fn local_saved_run_status(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  input_root : String,
  child : @argparse.Matches,
) -> String raise ClientStop {
  let scope = local_host_result(
    host.authority_scope_cid(settings.principal, settings.connection, crypto),
  )
  let current = () => {
    local_run_operation_allowed(host, settings, crypto, scope, "read")
  }
  let (reference, submission, state) = match optional(child, "run-id") {
    Some(id) => {
      if id.is_empty() ||
        optional(child, "ref-file") is Some(_) ||
        optional(child, "submission-ref-file") is Some(_) {
        stop("InvalidLocalStatusSelection")
      }
      let selected = match
        host.lookup_submitted_run_state_by_id(
          crypto,
          settings.principal,
          settings.connection,
          id,
          @env.now().to_double(),
        ) {
        Ok(value) => value
        Err(issue) => stop(local_saved_state_issue(issue))
      }
      (
        local_original_run_reference(selected.definition(), scope),
        selected.reference(),
        selected.state(),
      )
    }
    None => {
      let selected = local_original_run_selection(
        host, input_root, child, scope, current,
      )
      let state = match
        host.lookup_submitted_run_state(
          crypto,
          settings.principal,
          settings.connection,
          selected.submission,
          selected.request,
          @env.now().to_double(),
        ) {
        Ok(value) => value
        Err(issue) => stop(local_saved_state_issue(issue))
      }
      (selected.reference, selected.submission, state)
    }
  }
  let original = @json.parse(state.wire()) catch {
    _ => stop("LocalOriginalRunStateUnavailable")
  }
  let submission = @json.parse(
    @local_host.native_client_submission_reference_wire(submission),
  ) catch {
    _ => stop("InvalidSubmissionRef")
  }
  // This is CLI output, not a controlled-RunState issued from a SQL metadata
  // revision. Preserve the exact original state and actual Run control value.
  let reply = encode_request_json(
    Json::object(
      Map([
        ("kind", Json::string("local_saved_run_state")),
        ("mode", Json::string("local")),
        ("ref", reference),
        ("submissionRef", submission),
        ("state", original),
        ("controlRevision", Json::string(state.control_revision().to_string())),
      ]),
    ),
    65536,
  )
  if !current() {
    stop("LocalRunStateReadAuthorizationDenied")
  }
  if child.flags.get("json").unwrap_or(false) {
    reply
  } else {
    "Local saved Run state (Result availability is an independent observation):\n" +
    reply
  }
}

///|
fn local_saved_state_issue(
  issue : @local_host.NativeClientSavedRunStateIssue,
) -> String {
  match issue {
    Unavailable => "LocalOriginalRunStateUnavailable"
    Journal(@local_host.AuthorizationDenied) =>
      "LocalRunStateReadAuthorizationDenied"
    Journal(@local_host.TransactionUnknown) => "LocalRunStateLookupUnknown"
    Journal(@local_host.ForeignRun | @local_host.ChangedIntent) =>
      "LocalOriginalRunReferenceMismatch"
    Journal(_) => "LocalOriginalRunStateCustodyUnavailable"
  }
}
