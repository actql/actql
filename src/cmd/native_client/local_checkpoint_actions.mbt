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
  prepared? : (LocalCommandPreparationOriginal, LocalCommandConfiguration)? = None,
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
  match (capture, prepared) {
    (Some(original), Some((preparation, configuration))) =>
      preparation.restore_checkpoint_review(original, configuration, selected)
    _ => ()
  }
  // The original retained Effect approval scope, actual default signing-use
  // claim and Host attestation must be joined here by their existing Owners.
  // Selection does not permit exporting a private admission seam or treating
  // metadata/key material as a signing operation. Keep this explicit refusal
  // until the operational supplier is connected; never report approval/resume.
  stop("LocalCheckpointResolutionUnavailable")
}

///|
// The actual cold command retains its original reader BEFORE restoration. It
// opens only the already existing bound Store, never Program/Model inputs or
// a replacement Run. Signing/admission remain separate from this read step.
fn LocalCommandPreparationOriginal::restore_checkpoint_review(
  self : LocalCommandPreparationOriginal,
  capture : @local_host.NativeLocalJournalCapture,
  configuration : LocalCommandConfiguration,
  selected : @local_host.NativeLocalCheckpointSelection,
) -> Unit raise ClientStop {
  guard self.journal is Some(actual) &&
    physical_equal(actual, capture) &&
    self.run_observation is Some(observation) &&
    observation.saved_effect_review is None &&
    self.host is Some(host) &&
    self.pair is Some(pair) &&
    self.runtime is Some(runtime) &&
    self.business is None &&
    self.journal_read_open &&
    !self.closing &&
    !self.closed else {
    stop("LocalCheckpointReadUnavailable")
  }
  let settings = configuration.settings
  let run_file = settings.run_file.unwrap_or_else(() => {
    stop("LocalRunOriginalNotSelected")
  })
  local_host_result(
    capture.bind_packaged_runtime_in_original_read(
      runtime,
      settings.principal,
      settings.connection,
      configuration.environment_name,
      run_file,
      "runtime.json",
    ),
  )
  |> ignore
  let body = local_host_result(
    capture.selected_configuration_in_original_read(run_file),
  )
  let installation = configuration.run_installation(run_file, body)
  let managed = local_host_result(capture.managed_root_path_in_original_read()).unwrap_or_else(() => {
      stop("LocalManagedRootRequired")
    },
  )
  let sqlite = host
    .borrow_local_host_sqlite(pair)
    .unwrap_or_else(() => stop("LocalCheckpointReadUnavailable"))
  let store = self.open_run_observation_store(sqlite, managed, installation)
  let reader = local_host_result(
    capture.prepare_saved_effect_review(
      store,
      selected,
      settings.principal,
      settings.connection,
      installation.namespace_id,
    ),
  )
  observation.saved_effect_review = Some(reader)
  local_host_result(reader.restore_in_original_read(@env.now().to_double()))
  |> ignore
}
