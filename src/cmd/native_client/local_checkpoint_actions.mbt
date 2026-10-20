///|
// Exact public selection only. It neither grants resolution nor supplies a
// signing use, and it never aliases a Run ID or discovers a Checkpoint.
fn local_checkpoint_action_selected(
  matches : @argparse.Matches,
  operation : String,
) -> Bool raise ClientStop {
  guard (operation == "approve" || operation == "reject") &&
    matches.subcommand is Some((actual, child)) &&
    actual == operation else {
    return false
  }
  match optional(child, "checkpoint-id") {
    Some(id) => !id.is_empty() && id.length() <= 65536
    None => false
  }
}

///|
// The exact public selector reaches only the original Host-owned Checkpoint.
// No caller-supplied body, resolution ID, key, Boolean or signature is accepted.
fn local_checkpoint_answer_by_id(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  operation : String,
  child : @argparse.Matches,
  capture? : @local_host.NativeLocalJournalCapture? = None,
) -> String raise ClientStop {
  if operation != "approve" && operation != "reject" {
    stop("InvalidCheckpointAction")
  }
  let id = required(child, "checkpoint-id")
  let lookup = match capture {
    Some(original) => {
      guard original.original_host() is Some(actual) &&
        physical_equal(actual, host) else {
        stop("LocalCheckpointReadUnavailable")
      }
      local_host_result(
        original.lookup_original_checkpoint_by_id_in_original_read(
          settings.principal,
          settings.connection,
          id,
          @env.now().to_double(),
        ),
      )
    }
    None =>
      host.lookup_original_checkpoint_by_id(
        crypto,
        settings.principal,
        settings.connection,
        id,
        @env.now().to_double(),
      )
  }
  let selected = match lookup {
    Ok(Some(value)) => value
    Ok(None) => stop("LocalOriginalCheckpointUnavailable")
    Err(_) => stop("LocalCheckpointReadUnavailable")
  }
  if selected.checkpoint_id() != id {
    stop("LocalOriginalCheckpointUnavailable")
  }
  // The original retained Effect approval scope, actual default signing-use
  // claim and Host attestation must be joined here by their existing Owners.
  // Selection does not permit exporting a private admission seam or treating
  // metadata/key material as a signing operation. Keep this explicit refusal
  // until the operational supplier is connected; never report approval/resume.
  stop("LocalCheckpointResolutionUnavailable")
}
