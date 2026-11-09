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
  // Keep these original public selections explicit while their consuming
  // continuations are unfinished. A named signer never falls back to the
  // initialized machine key, and --wait cannot become a nonwaiting success.
  if optional(child, "signer") is Some(_) {
    stop("LocalConfiguredCheckpointSignerUnavailable")
  }
  if child.flags.get("wait").unwrap_or(false) {
    stop("LocalCheckpointContinuationUnavailable")
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
  guard capture is Some(original) &&
    prepared is Some((preparation, configuration)) else {
    stop("LocalCheckpointReadUnavailable")
  }
  preparation.restore_checkpoint_review(original, configuration, selected)
  preparation.resolve_checkpoint_review(original, configuration, operation)
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

///|
// One existing command, Request and captured Read. No Program/Model replay,
// new Root, supplied permission or standalone signing/Store owner is created.
fn LocalCommandPreparationOriginal::resolve_checkpoint_review(
  self : LocalCommandPreparationOriginal,
  capture : @local_host.NativeLocalJournalCapture,
  configuration : LocalCommandConfiguration,
  operation : String,
) -> String raise ClientStop {
  guard self.journal is Some(actual) &&
    physical_equal(actual, capture) &&
    self.run_observation is Some(observation) &&
    observation.saved_effect_review is Some(review) &&
    observation.journal_operation is Some(journal) &&
    self.journal_read_open &&
    !self.closing &&
    !self.closed else {
    stop("LocalCheckpointReadUnavailable")
  }
  let settings = configuration.settings
  let run_file = settings.run_file.unwrap_or_else(() => {
    stop("LocalRunOriginalNotSelected")
  })
  let body = local_host_result(
    capture.selected_configuration_in_original_read(run_file),
  )
  let installation = configuration.run_installation(run_file, body)
  let policy = @run_host.client_standard_effect_computation_limits()
  let compilation = policy.program.checking.compilation
  let sequence = @run_host.client_standard_values_sequence_limits()
  command_preparation_result(
    journal
    .begin_captured_journal_read()
    .map_err(issue => CommandStoreOperation(issue)),
  )
  let answer = try {
    match
      review.restore_approval_in_original_read(
        @env.now().to_double(),
        { text_time: false, veca: false, },
        {
          rela: true,
          sga: false,
          tea: false,
          calendar: false,
          text_rank: false,
        },
        native_request_manifests,
        {
          preparation: policy.program,
          sequence,
          max_sequence_steps: compilation.structure.steps,
          max_sequence_work: compilation.work,
          max_evidence_bytes: compilation.artifacts.bytes,
          max_evidence_nodes: compilation.artifacts.nodes,
          max_evidence_depth: compilation.artifacts.depth,
        },
        policy,
        {
          max_wire_bytes: native_mock_effect_record_bytes(installation),
          max_nodes: policy.effects.max_admission_nodes,
          max_depth: policy.effects.max_admission_depth,
        },
      ) {
      Ok(_) => ()
      Err(issue) => {
        self.retain_primary(CommandAdoption(issue))
        stop("LocalCheckpointOriginalUnavailable")
      }
    }
    let record = match
      review.resolve_initial_in_original_read(operation, "host.json") {
      Ok(value) => value
      Err(issue) => {
        self.retain_primary(CommandSavedResolution(issue))
        stop("LocalCheckpointResolutionUnavailable")
      }
    }
    let state = @local_host.native_client_run_checkpoint_state(record).unwrap_or_else(() => {
        stop("LocalCheckpointStateUnavailable")
      },
    )
    Ok(state.wire)
  } catch {
    ClientStop(message) => Err(message)
  }
  // Attempt this SAME original return on both paths. A missing return cannot
  // turn a completed Resolution into public success or lose pending cleanup.
  let returned = journal.finish_captured_journal_read()
  if returned is Err(issue) {
    self.retain_primary(CommandStoreOperation(issue))
  }
  match (answer, returned) {
    (Ok(wire), Ok(_)) => wire
    (Err(message), _) => stop(message)
    (Ok(_), Err(_)) => stop("LocalCheckpointReadReturnUnavailable")
  }
}
