///|
// A public spelling for the same original ID selection, not a RunRef issuer
// or an authorization. Normalize before project/file access as well as when
// the existing dispatcher is called directly. Repeating it is a no-op.
fn normalize_native_status_arguments(
  matches : @argparse.Matches,
) -> Unit raise ClientStop {
  guard matches.subcommand is Some(("status", child)) else { return }
  ignore(local_status_watch_options(child))
  guard optional(child, "run") is Some(id) else { return }
  for name in ["run-id", "ref-file", "submission-ref-file"] {
    if optional(child, name) is Some(_) {
      stop("ConflictingLocalStatusSelection")
    }
  }
  child.values["run-id"] = [id]
  ignore(child.values.remove("run"))
}

///|
// Saved Owner observation only. A status query never prepares, starts, reads
// payload bytes, grants access or reconstructs missing legacy state.
fn local_saved_run_status(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  input_root : String,
  child : @argparse.Matches,
  state_only? : Bool = false,
  human_display? : ((String) -> String raise ClientStop)? = None,
  capture? : @local_host.NativeLocalJournalCapture? = None,
  original_reader? : ((String) -> @local_host.NativeClientSavedRunStateSelection raise ClientStop)? = None,
) -> String raise ClientStop {
  let scope = local_host_result(
    match capture {
      None =>
        host.authority_scope_cid(
          settings.principal,
          settings.connection,
          crypto,
        )
      Some(original) =>
        original.authority_scope_cid_in_original_read(
          settings.principal,
          settings.connection,
        )
    },
  )
  let current = () => {
    local_run_operation_allowed(host, settings, crypto, scope, "read", capture~)
  }
  let (reference, submission, state) = match optional(child, "run-id") {
    Some(id) => {
      if id.is_empty() ||
        optional(child, "ref-file") is Some(_) ||
        optional(child, "submission-ref-file") is Some(_) {
        stop("InvalidLocalStatusSelection")
      }
      let lookup = if original_reader is Some(read) {
        Ok(read(id))
      } else {
        match capture {
          None =>
            host.lookup_submitted_run_state_by_id(
              crypto,
              settings.principal,
              settings.connection,
              id,
              @env.now().to_double(),
            )
          Some(original) =>
            local_host_result(
              original.lookup_submitted_run_state_by_id_in_original_read(
                settings.principal,
                settings.connection,
                id,
                @env.now().to_double(),
              ),
            )
        }
      }
      let selected = match lookup {
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
      if capture is Some(_) {
        stop("LocalOriginalStatusReferenceSupplierUnavailable")
      }
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
  // The public ID spelling returns the portable saved State directly. Do not
  // nest it in private metadata or spend another wire budget on a wrapper.
  if state_only || child.sources.get("run") is Some(@argparse.Argv) {
    if !current() {
      stop("LocalRunStateReadAuthorizationDenied")
    }
    return if state_only || child.flags.get("json").unwrap_or(false) {
      state.wire()
    } else {
      match human_display {
        Some(display) => display(state.wire())
        None =>
          local_run_state_display(state.wire()).unwrap_or_else(() => {
            stop("LocalRunStateDisplayUnavailable")
          })
      }
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
