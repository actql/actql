///|
// Public presentation reads the same authenticated original. A publication
// reply, start claim or index is never converted into completed Run state.
// Legacy intake retains its exact response and performs no additional lookup.
fn local_public_run_state_reply(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  reference : @local_host.NativeClientSubmissionReference,
  public_run : Bool,
  legacy_reply : String,
  capture? : @local_host.NativeLocalJournalCapture? = None,
) -> String raise ClientStop {
  if !public_run {
    return legacy_reply
  }
  local_public_run_state_selection(host, settings, crypto, reference, capture~)
  .state()
  .wire()
}

///|
// Retain the actual selected original along with its State for same-call
// receipt/Result observation. This is not another Run lookup or issuer.
fn local_public_run_state_selection(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  reference : @local_host.NativeClientSubmissionReference,
  capture? : @local_host.NativeLocalJournalCapture? = None,
) -> @local_host.NativeClientSavedRunStateSelection raise ClientStop {
  let result = match capture {
    Some(original) =>
      local_host_result(
        original.lookup_submitted_run_state_by_id_in_original_read(
          settings.principal,
          settings.connection,
          @local_host.native_client_submission_request_id(reference),
          @env.now().to_double(),
        ),
      )
    None =>
      host.lookup_submitted_run_state_by_id(
        crypto,
        settings.principal,
        settings.connection,
        @local_host.native_client_submission_request_id(reference),
        @env.now().to_double(),
      )
  }
  let selected = match result {
    Ok(value) => value
    Err(issue) => stop(local_saved_state_issue(issue))
  }
  if @local_host.native_client_submission_reference_wire(selected.reference()) !=
    @local_host.native_client_submission_reference_wire(reference) {
    stop("LocalOriginalRunReferenceMismatch")
  }
  // No callback follows the existing terminal current fence. The observed
  // revision is the saved State owner's value, never SQL/control metadata.
  selected
}
