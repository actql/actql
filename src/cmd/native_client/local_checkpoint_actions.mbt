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
  // Only current implementation metadata is selected here. The Saved
  // Program/Model/Result is restored independently below, never recomputed.
  // The original Runtime/Read/authority supplies the actual installation.
  self.bind_project_mock_runtime(runtime, capture, settings.principal)
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
    observation.effect_resume is None &&
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
    let record = if operation == "approve" {
      match review.resolve_initial_resume_in_original_read("host.json") {
        Ok((record, continuation)) => {
          // This is the SAME acknowledged Resolution and retained Saved
          // original. Keep the continuation on the existing command before
          // any fallible subsequent claim, request projection or physical IO.
          observation.effect_resume = Some(continuation)
          record
        }
        Err(issue) => {
          self.retain_primary(CommandSavedResolution(issue))
          stop("LocalCheckpointResolutionUnavailable")
        }
      }
    } else {
      match review.resolve_initial_in_original_read(operation, "host.json") {
        Ok(value) => value
        Err(issue) => {
          self.retain_primary(CommandSavedResolution(issue))
          stop("LocalCheckpointResolutionUnavailable")
        }
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
    (Ok(wire), Ok(_)) => {
      if self.business is Some(business) &&
        business.profile.kind == SavedEffectApply {
        let continuation = observation.effect_resume.unwrap_or_else(() => {
          stop("LocalCheckpointOriginalUnavailable")
        })
        let original = continuation
          .application_original_in_original_read()
          .unwrap_or_else(() => stop("LocalCheckpointOriginalUnavailable"))
        if self.saved_effect_file_constructor_capacity(original)
          is Some(capacity) {
          command_preparation_result(
            self.prepare_saved_effect_capacity(capture, capacity),
          )
        }
        // The public --wait gate above remains closed until the same caller's
        // request/Account/IO/receipt/publication chain is complete. Even an
        // internal caller cannot report this constructor prefix as completion.
        stop("LocalCheckpointContinuationUnavailable")
      }
      wire
    }
    (Err(message), _) => stop(message)
    (Ok(_), Err(_)) => stop("LocalCheckpointReadReturnUnavailable")
  }
}

///|
// Select only the already declared current implementation of the exact Saved
// member. No Program text classifier, new Mapping, copied key, grant or IO.
// This is the file constructor prefix only. The actual application must add
// retained requests/ACKs/receipts and publication overlap before activation;
// it cannot expose this prefix as a complete Run or physical backing proof.
fn LocalCommandPreparationOriginal::saved_effect_file_constructor_capacity(
  self : Self,
  original : @local_host.NativeLocalSavedEffectApprovalOriginal,
) -> @execution.ExecutionCapacity? raise ClientStop {
  guard self.project is Some(project) &&
    project.mock_declarations is Some(mock) &&
    !mock.closing &&
    !mock.retired &&
    mock.model_failure is None &&
    mock.write_installations is Some(installations) else {
    stop("LocalOriginalEffectInstallationUnavailable")
  }
  let materials = original.run_materials()
  let preview = original.effect_preview()
  let headers = @checked.effect_program_static_headers(
    @run_host.prepared_client_effect_computation_candidate(materials.prepared),
  )
  let policy = @run_host.client_standard_effect_computation_limits()
  let mut demand : @execution.ExecutionCapacity? = None
  for member_index in 0..<@publication.effect_preview_member_count(preview) {
    guard @publication.effect_preview_member_effect_id(preview, member_index)
      is Some(effect_id) &&
      @syntax.effect_header_at(headers, member_index) is Some(header) &&
      @syntax.effect_header_id(header) == effect_id &&
      @publication.effect_preview_row_count(preview, member_index) is Some(rows) else {
      stop("LocalOriginalEffectInstallationUnavailable")
    }
    let descriptor = @run_host.client_effect_member_descriptor(
      materials.prepared,
      @syntax.effect_header_stage(header),
      effect_id,
      policy.effects.max_work,
    ).unwrap_or_else(() => stop("LocalOriginalEffectInstallationUnavailable"))
    guard descriptor.0 == member_index &&
      descriptor.2 == "update" &&
      @publication.effect_preview_member_source_binding_cid(
        preview, member_index,
      )
      is Some(binding_cid) &&
      @publication.effect_preview_member_resolved_contract(
        preview, member_index,
      )
      is Some(@publication.Mapping(reference, mapping_cid)) &&
      reference == descriptor.4 &&
      mapping_cid == descriptor.5 &&
      installations
      .iter()
      .find_first(value => {
        value.binding == binding_cid &&
        value.target == descriptor.3 &&
        value.write.mapping.mapping_ref == reference &&
        value.write.mapping.mapping_cid == mapping_cid
      })
      is Some(installation) &&
      installation._retained_source._retained_rows
      .iter()
      .find_first(value => {
        value.view.resource == installation.write.mapping.resource
      })
      is Some(row_binding) else {
      stop("LocalOriginalEffectInstallationUnavailable")
    }
    if rows == 0 {
      continue
    }
    let physical = @row_file.native_relation_file_target_io_capacity(
      row_binding.provider,
      installation.write.mapping.write_fields.length(),
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    demand = Some(
      match demand {
        None => physical
        Some(prior) =>
          native_mock_effect_capacity_envelope(prior, physical).unwrap_or_else(() => {
            stop("LocalOriginalEffectCapacityUnavailable")
          })
      },
    )
  }
  // Explicit no-file-call inventory, not a successful missing constructor.
  // Zero rows still require the later original Set/Run/publication chain.
  demand
}
