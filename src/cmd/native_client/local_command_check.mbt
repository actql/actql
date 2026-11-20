///|
// This caller reference retains the same original across parser/command errors.
// It is not a supplier or an initialization/admission receipt.
let command_preparation_invocation : Ref[LocalCommandPreparationOriginal?] = Ref(
  None,
)

///|
// Retire only through the same original's child-first cleanup. On failure the
// caller retains that exact invocation, including its primary and every pending
// receiver; process termination or an output write is not its acknowledgement.
fn local_finish_command_preparation() -> Result[
  Unit,
  LocalCommandPreparationIssue,
] {
  match command_preparation_invocation.val {
    None => Ok(())
    Some(original) =>
      match original.close_checked() {
        Err(issue) => {
          original.retain_primary(issue)
          Err(issue)
        }
        Ok(_) => {
          command_preparation_invocation.val = None
          Ok(())
        }
      }
  }
}

///|
// Project only the release boundary/error kind. Never stringify application
// messages, key/material payloads or opaque physical receivers for diagnostics.
fn command_preparation_cleanup_kind(
  issue : LocalCommandPreparationIssue,
) -> String {
  match issue {
    CommandInvalidProfile => "profile"
    CommandUnavailable => "original-unavailable"
    CommandBusinessCapacity => "business-capacity"
    CommandRequestPreparation(_) => "request-preparation"
    CommandNativeStorage(_) => "native-storage"
    CommandHost(_) => "host"
    CommandDomain(_) => "domain"
    CommandRead(_) => "read"
    CommandRetainedExecution(_) => "business-execution"
    CommandStoreOperation(_) => "business-operation"
    CommandSavedResolution(_) => "checkpoint-resolution"
    CommandBusinessChildren => "business-children"
    CommandSavedFileResource(_) => "saved-file-resource"
    CommandSavedFileEntry(_) => "saved-file-entry"
    CommandSavedFileResume(_) => "saved-file-resume"
    CommandSavedEffectPublication(_) => "saved-effect-publication"
    CommandSavedEffectOutput(_) => "saved-effect-output"
    CommandSavedEffectCompletion(_) => "saved-effect-completion"
    CommandBusinessSource(_) => "business-source"
    CommandBusinessModel(_) => "business-model"
    CommandBusinessModelGraph(_) => "business-model-graph"
    CommandBusinessQueryPlan(_) => "business-query-plan"
    CommandBusinessQueryRequirement(_) => "business-query-requirement"
    CommandBusinessQueryRow(_) => "business-query-row"
    CommandBusinessQueryCapture(_) => "business-query-capture"
    CommandBusinessSourceIdentity(_) => "business-source-identity"
    CommandBusinessEffectProposals(_) => "business-effect-proposals"
    CommandBusinessEffectAcceptance(_) => "business-effect-acceptance"
    CommandBusinessPublication => "business-publication"
    CommandBusinessStore(_) => "business-store"
    CommandRunObservationPending => "run-observation-pending"
    CommandRunObservationStore(_) => "run-observation-store"
    CommandBusinessResult(_) => "business-result"
    CommandBusinessFileOutput(_) => "business-file-output"
    CommandPair(value) =>
      match value {
        @initial_arena.Read(read) =>
          "pair-read-" + command_preparation_read_cleanup_kind(read)
        @initial_arena.Sqlite(_) => "pair-sqlite"
        @initial_arena.Domain(_) => "pair-domain"
      }
    CommandRuntime(_) => "runtime"
    CommandSqlite(_) => "sqlite"
    CommandComponent(_) => "crypto-component"
    CommandReadCrypto(_) => "read-crypto"
    CommandSignature(_) => "signature"
    CommandJournal(_) => "journal"
    CommandAdoption(_) => "adoption"
    CommandCapture(_) => "adoption-capture"
    CommandApplication(_) => "application"
    CommandProjectMock(_) => "project-mock"
    CommandFilesystem(_) => "filesystem"
    CommandFilesystemCleanup(_) => "filesystem-cleanup"
  }
}

///|
// Preserve the original failed cleanup family without exposing messages,
// payloads, paths or opaque receivers. Physical status is the original code,
// not an inferred acknowledgement or a replacement cleanup operation.
fn command_preparation_read_cleanup_kind(
  issue : @initial_arena.InstalledArenaOriginalReadIssue,
) -> String {
  match issue {
    Domain(@initial_bootstrap.Bootstrap(@initial_bootstrap.Physical(code))) =>
      "domain-physical(" + code.to_string() + ")"
    Domain(@initial_bootstrap.Bootstrap(_)) => "domain-bootstrap"
    Domain(@initial_bootstrap.Accounting(_)) => "domain-accounting"
    Child(_) => "child-ledger"
    Read(@initial_resources.CleanupPending) => "read-ledger-pending"
    Read(_) => "read-ledger"
    Buffer(_) => "workspace"
  }
}

///|
// Disclose only closed constructor labels from the already retained failure.
// This does not inspect a path, retry acquisition, or replace cleanup custody.
fn command_adoption_capture_cause(
  issue : @local_host.NativeLocalAdoptionCaptureIssue,
) -> String {
  match issue {
    AdoptionOriginal(Filesystem(cause)) => {
      let tag = match cause {
        UnsupportedTarget => "UnsupportedTarget"
        InvalidName => "InvalidName"
        InvalidLimit => "InvalidLimit"
        RootOpen(_) => "RootOpen"
        Lock(_) => "Lock"
        WriterCreate(_) => "WriterCreate"
        CapacityExceeded => "CapacityExceeded"
        WriterClosed => "WriterClosed"
        Write(_) => "Write"
        Conflict => "Conflict"
        GenerationMismatch => "GenerationMismatch"
        InvalidReadSize => "InvalidReadSize"
        IncompleteRead => "IncompleteRead"
        ReaderClosed => "ReaderClosed"
        Read(_) => "Read"
        Seal(_) => "Seal"
        Cleanup(_) => "Cleanup"
      }
      "AdoptionOriginal:Filesystem:" + tag
    }
    AdoptionOriginal(Crypto(cause)) => {
      let tag = match cause {
        UnsupportedTarget => "UnsupportedTarget"
        InvalidInput => "InvalidInput"
        LibraryLoad(_) => "LibraryLoad"
        InvalidPublicKey(_) => "InvalidPublicKey"
        InvalidPrivateKey(_) => "InvalidPrivateKey"
        UnsupportedKey(_) => "UnsupportedKey"
        Verification(_) => "Verification"
        Signing(_) => "Signing"
        CleanupPending => "CleanupPending"
        CloseUnconfirmed(_) => "CloseUnconfirmed"
      }
      "AdoptionOriginal:Crypto:" + tag
    }
    AdoptionOriginal(cause) =>
      "AdoptionOriginal:" +
      command_preparation_cleanup_cause(CommandAdoption(cause))
    other => command_preparation_cleanup_cause(CommandCapture(other))
  }
}

///|
fn[T] command_preparation_result(
  result : Result[T, LocalCommandPreparationIssue],
  stage? : String? = None,
) -> T raise ClientStop {
  match result {
    Ok(value) => value
    // read_command retains the original public ClientStop across its physical
    // return. Preserve that application failure after the return completes;
    // it must not become an unrelated preparation/supplier error.
    Err(CommandApplication(message)) =>
      stop(local_command_recovery_failure(message))
    Err(issue) => {
      // Closed caller-owned labels and the existing error-family projection
      // identify the failed boundary without exposing paths, keys or messages.
      // Select the closed original constructor before the same existing
      // joins. Never inspect its payload or replace the cleanup receiver.
      let kind = match issue {
        CommandRead(Domain(original)) =>
          command_read_domain_cause(original, read_kind=true)
        CommandRead(Child(_)) => "read:Child"
        CommandRead(Read(_)) => "read:Read"
        CommandRead(Buffer(_)) => "read:Buffer"
        _ => command_preparation_cleanup_kind(issue)
      }
      let message = match stage {
        None => "LocalCommandPreparationUnavailable"
        Some(name) => "LocalCommandPreparationUnavailable:" + name + ":" + kind
      }
      let disclosed = match issue {
        CommandCapture(original) =>
          message + ":" + command_adoption_capture_cause(original)
        CommandFilesystem(original) =>
          local_bounded_file_diagnostic_message(message, original)
        _ => message
      }
      stop(local_command_recovery_failure(disclosed))
    }
  }
}

///|
// Selection only: the downstream original/current/Account admissions remain
// mandatory. A private submission or an absent business original cannot select
// the public Run's operational route.
fn local_command_preparation_operation_selected(
  matches : @argparse.Matches,
  operation : String,
  business_selected : Bool,
) -> Bool raise ClientStop {
  operation == "check" ||
  operation == "explain" ||
  operation == "adopt" ||
  (
    matches.subcommand is Some((selected, _)) &&
    selected == operation &&
    (
      selected == "new-submission" ||
      selected == "lookup-submission" ||
      selected == "lookup-request" ||
      selected == "cancel" ||
      selected == "lookup-cancellation"
    )
  ) ||
  (
    matches.subcommand is Some((selected, child)) &&
    selected == operation &&
    local_quick_query_requested(selected, child) &&
    business_selected
  ) ||
  local_checkpoint_action_selected(matches, operation) ||
  (
    operation == "status" &&
    matches.subcommand is Some(("status", child)) &&
    (optional(child, "run") is Some(_) || optional(child, "run-id") is Some(_)) &&
    optional(child, "ref-file") is None &&
    optional(child, "submission-ref-file") is None
  ) ||
  (
    operation == "result" &&
    matches.subcommand is Some(("result", child)) &&
    optional(child, "run") is Some(_) &&
    business_selected &&
    optional(child, "ref-file") is None &&
    optional(child, "submission-ref-file") is None
  ) ||
  (
    operation == local_run_original_operation() &&
    matches.subcommand is Some(("run", _)) &&
    business_selected
  )
}

///|
// The selected package and all of its original asset observations use the
// Runtime's own full scopes. Only then enter the same consuming Read for the
// retained Product/Host selection; do not nest Runtime acquisition inside it.
fn LocalCommandPreparationOriginal::execute_product_command(
  self : LocalCommandPreparationOriginal,
  matches : @argparse.Matches,
  operation : String,
) -> String raise ClientStop {
  if !local_command_preparation_operation_selected(
      matches,
      operation,
      self.business is Some(_),
    ) {
    stop("LocalCommandPreparationOperationUnavailable")
  }
  if !(matches.sources.get("config-root") is Some(@argparse.Default)) {
    stop("ExplicitLocalRootRequiresConfiguration")
  }
  guard self.runtime is Some(physical) else {
    stop("LocalCommandPreparationUnavailable")
  }
  // Project discovery was already inside this Read. Suspend only this scope
  // while the Runtime performs its own original-current brackets.
  command_preparation_result(self.leave(), stage=Some("runtime-return"))
  let runtime = local_packaged_runtime_from_physical(physical)
  command_preparation_result(self.enter(), stage=Some("runtime-reenter"))
  // Required HOME/path decoding and selection now allocate in the same
  // consuming Read; an explicit directory never obtains the HOME workspace.
  let location = local_product_original_location(optional(matches, "state-dir"))
  let configuration_root = if location.parent_path == "/" {
    "/" + location.directory_name
  } else {
    location.parent_path + "/" + location.directory_name
  }
  let (_, selected_child) = matches.subcommand.unwrap()
  let quick_query = local_quick_query_requested(operation, selected_child)
  let originals = if operation == "adopt" || quick_query {
    let parent = command_preparation_result(
      self.select_product_parent(location.parent_path),
      stage=Some("product-parent"),
    )
    let ownership = parent
      .bootstrap_parent_ownership()
      .unwrap_or_else(() => stop("LocalProductHomeUntrusted"))
    let intent = parent
      .inspect_generation("product-initialization.json")
      .unwrap_or_else(() => stop("LocalProductCustodyUnavailable"))
    if intent is Some(_) {
      None // Restore the original selection; never regenerate expiry or keys.
    } else {
      if parent
        .inspect_directory(location.directory_name)
        .unwrap_or_else(() => stop("LocalProductCustodyUnavailable"))
        is Some(_) {
        stop("LocalProductCustodyLost")
      }
      let mock = match self.project {
        Some(project) if operation == "adopt" &&
          project.mock_declarations is Some(mock) =>
          Some(
            mock
            .account_subjects()
            .unwrap_or_else(() => stop("LocalProjectBindingsUnavailable")),
          )
        _ => None
      }
      let mock = mock.map(subjects => {
        // The fixed target literal still has the pinned Array wrapper/backing:
        //2H,(1+N)R,2W. Add new subjects1H8R, Some1H1R1W and the existing
        // private assembler's selected-control alias1R, before any allocation.
        let slots = if subjects.update_target is Some(_) { 1L } else { 0L }
        let array = @shape.reference_array_retained_extent(1L, slots).unwrap_or_else(() => {
            stop("LocalMockAccountConstructionUnavailable")
          },
        )
        let controls : @authorization.AccountConfigurationConstructionUnits = {
          record_headers: array.record_headers + 2L,
          reference_slots: array.reference_slots + 10L,
          scalar_words: array.scalar_words + 1L,
          owned_utf16_units: 0L,
          owned_wire_bytes: 0L,
        }
        if !self.prepare_account_construction({
            retained: controls,
            execution: controls,
          }) {
          stop("LocalMockAccountConstructionUnavailable")
        }
        let targets = match subjects.update_target {
          Some(target) => [target]
          None => []
        }
        let selected = @authorization.local_mock_control_connection_prepared(
            subjects.control_connection,
            None,
            None,
            subjects.sources,
            targets,
            request => self.prepare_account_construction(request),
          )
          .unwrap_or_else(() => stop("LocalMockAccountConstructionUnavailable"))
          .unwrap_or_else(() => stop("LocalProjectBindingsUnavailable"))
        { ..subjects, control_connection: selected, }
      })
      let host_configuration = if mock is Some(subjects) &&
        subjects.update_target is Some(_) {
        Some(self.select_operator_host(matches, true))
      } else {
        None
      }
      let mock = mock.map(subjects => {
        if host_configuration is Some(_) {
          {
            ..subjects,
            signing_key_resource: Some("key/initial-host-attestation"),
          }
        } else {
          subjects
        }
      })
      let selected = @run_host.client_native_local_finite_product_originals(
        configuration_root,
        runtime.sqlite,
        runtime.crypto,
        local_utc_now(),
        runtime.assets,
        runtime.manifest,
        query_contracts=runtime.physical
          .query_contract_assets()
          .unwrap_or_else(() => stop("PackagedLocalRuntimeChanged")),
        mock~,
        host_configuration~,
      ).unwrap_or_else(() => stop("LocalProductDefaultsNotAdmitted"))
      let selected = local_product_model_policy_originals(
        selected,
        Some(@local_values.client_local_resource_policy()),
      )
      if !(parent.bootstrap_parent_ownership() is Ok(current) &&
        current == ownership) {
        stop("LocalProductHomeUntrusted")
      }
      Some(selected)
    }
  } else {
    None
  }
  command_preparation_result(
    self.stage_product(location.parent_path, location.directory_name, originals),
    stage=Some("product-stage"),
  )
  // Selection is remembered only after the original excluded Product capture
  // staged these initial bodies. The Native Session still proves first-key
  // eligibility independently; restored/missing adopted state cannot rekey.
  self.initial_product_selected = originals is Some(_)
  let original_runtime = text_file(configuration_root, "runtime.json", 65536L)
  local_product_require_same_runtime_wire(
    original_runtime,
    @run_host.client_native_local_runtime_original(runtime.manifest),
  )
  let configuration = local_host_configuration_text_file(
    configuration_root, "config.json",
  )
  let settings = local_host_settings(configuration)
  if settings.sqlite_library != runtime.sqlite ||
    settings.signature_library != runtime.crypto ||
    !settings.installation_files.contains("runtime.json") {
    stop("PackagedLocalRuntimeChanged")
  }
  // The same Product capture has already staged or restored these originals
  // under its retained Lock. Internal runtime/settings reads do not start a
  // second Product operation; the adoption Owner still binds their exact
  // selection and observes current Account state before protected work.
  if optional(matches, "input-root") is None {
    matches.values["input-root"] = [
      @env.current_dir().unwrap_or_else(() => {
        stop("LocalDocumentRootUnavailable")
      }),
    ]
  }
  matches.values["config-root"] = [configuration_root]
  matches.values["config-file"] = ["config.json"]
  let (_, child) = matches.subcommand.unwrap()
  execute_native_local_adoption(
    matches,
    operation,
    child,
    packaged_runtime=Some(physical),
    preparation=Some(self),
    preparation_runtime=Some(runtime),
    configuration_original=Some((configuration, settings)),
  )
}

///|
// Explicit operator DATA selects no executable or Library. Reuse the SAME
// packaged Runtime and command carrier before opening its configuration Root;
// the adoption Owner still captures every original/current generation.
fn LocalCommandPreparationOriginal::execute_operator_command(
  self : LocalCommandPreparationOriginal,
  matches : @argparse.Matches,
  operation : String,
  child : @argparse.Matches,
) -> String raise ClientStop {
  guard matches.sources.get("config-file") is Some(@argparse.Argv) &&
    self.runtime is Some(physical) else {
    stop("ExplicitLocalConfigurationRequiresOriginalSupplier")
  }
  command_preparation_result(self.leave(), stage=Some("runtime-return"))
  let runtime = local_packaged_runtime_from_physical(physical)
  command_preparation_result(self.enter(), stage=Some("runtime-reenter"))
  execute_native_local_adoption(
    matches,
    operation,
    child,
    packaged_runtime=Some(physical),
    preparation=Some(self),
    preparation_runtime=Some(runtime),
  )
}

///|
// Continue the existing selected configuration comparisons. The same actual
// adoption capture owns every partial Root/Lock and the original child Journal;
// this path never loads a second SQLite Library or a stock Crypto fallback.
fn LocalCommandPreparationOriginal::execute_adopted_command(
  self : LocalCommandPreparationOriginal,
  operation : String,
  root : String,
  configuration : LocalCommandConfiguration,
  selected_files : Array[String],
  selected_additional : Array[(String, Bytes)],
  input_root : String,
  child : @argparse.Matches,
  public_run? : Bool = false,
  preparation_runtime? : LocalPackagedRuntime? = None,
) -> String raise ClientStop {
  let settings = configuration.settings
  let name = configuration.configuration_name
  let environment_name = configuration.environment_name
  // This selected status route returns State only on success. Its failures
  // are command diagnostics, never a legacy Run/Unknown response container.
  if operation == "status" {
    command_preparation_diagnostic.val = RunObservationFailed
  }
  let session = command_preparation_result(
    self.prepare_adoption(
      {
        parent_path: settings.state_parent,
        state_name: settings.state_name,
        source_path: root,
        source_name: settings.account_file,
        account_id: settings.account_id,
        configuration_files: selected_files,
        managed_root_path: Some(settings.managed_root),
      },
      operation == "adopt" ||
      (
        local_quick_query_requested(operation, child) &&
        self.initial_product_selected
      ),
    ),
    stage=Some("adoption-open"),
  )
  let expected = [
    (name, configuration.configuration_body),
    (environment_name, configuration.environment_body),
  ]
  for item in selected_additional {
    expected.push(item)
  }
  for (file, body) in expected {
    guard session.selected_configuration(file) is Ok(selected) &&
      selected == body else {
      stop("LocalConfigurationChanged")
    }
  }
  // Trusted literal quick queries may initialize a genuinely absent default
  // Host through the same original Session. This selects physical setup only,
  // not Reviewer registration, Effect approval or missing-state repair.
  // Explicit first Product adoption uses that same initial-signing entrance;
  // the original Session still checks eligibility before issuing material.
  let initialize_signing = (
      operation == "adopt" &&
      (
        child.flags.get("initialize-signing").unwrap_or(false) ||
        self.initial_product_selected
      )
    ) ||
    (
      local_quick_query_requested(operation, child) &&
      self.initial_product_selected
    )
  command_preparation_result(
    self.prepare_adopted_journal(initialize_signing, {
      initialize_signing,
      ttl_ms: settings.ttl_ms,
      max_records: settings.record_limit,
      max_snapshot_bytes: settings.snapshot_bytes,
      initial_host_signing: settings.initial_host_signing,
    }),
    stage=Some("journal-open"),
  )
  |> ignore
  if operation == "status" ||
    operation == "cancel" ||
    operation == "approve" ||
    operation == "reject" ||
    (public_run && !child.flags.get("json").unwrap_or(false)) {
    command_preparation_result(
      self.prepare_run_observation_operation(
        journal=operation == "approve" || operation == "reject",
      ),
    )
  }
  let crypto = self.inner_library.unwrap()
  command_preparation_result(
    self.read_command(fn(host, capture) {
      try {
        // Join the already decoded DATA to this original captured selection
        // once. Trusted internal consumers reuse it; Account/current admission
        // and the actual Read/Runtime lifetime remain with their existing owners.
        guard capture.selected_configuration_in_original_read(name)
          is Ok(selected_configuration) &&
          selected_configuration == configuration.configuration_body &&
          capture.selected_configuration_in_original_read(environment_name)
          is Ok(selected_environment) &&
          selected_environment == configuration.environment_body else {
          stop("LocalConfigurationChanged")
        }
        let body = if operation == "check" {
          // Bind only the original declaration/Runtime metadata. This does not
          // read Source payloads, invoke a Model or prepare/apply an Effect.
          // Its existing file implementation also supplies the lookup profile
          // that drive.contents needs during ordinary static checking.
          self.bind_project_mock_runtime(
            self.runtime.unwrap_or_else(() => {
              stop("LocalBusinessOriginalUnavailable")
            }),
            capture,
            settings.principal,
          )
          let context = local_check_context(
            host,
            crypto,
            name,
            capture=Some(capture),
            configuration=Some(configuration),
          )
          let input = self.prepare_static_request(capture, input_root, child)
          let wire = context.project_request(self, capture, input, false)
          command_check_invalid_exit.val = local_check_invalid_exit(wire)
          local_check_reply(
            wire,
            child.flags.get("json").unwrap_or(false),
            input.document,
          )
        } else if operation == "new-submission" {
          local_new_submission_reference(settings, capture, child)
        } else if operation == "lookup-submission" {
          local_submission_lookup(
            host,
            settings,
            crypto,
            input_root,
            child,
            capture=Some(capture),
          )
        } else if operation == "lookup-request" {
          local_request_lookup(
            host,
            settings,
            crypto,
            child,
            capture=Some(capture),
          )
        } else if operation == "lookup-cancellation" {
          local_cancellation_lookup(
            host,
            settings,
            crypto,
            input_root,
            child,
            capture=Some(capture),
          )
        } else if operation == "cancel" {
          let physical = self.host.unwrap_or_else(() => {
            stop("LocalRunObservationOriginalUnavailable")
          })
          let pair = self.pair.unwrap_or_else(() => {
            stop("LocalRunObservationOriginalUnavailable")
          })
          let sqlite = physical
            .borrow_local_host_sqlite(pair)
            .unwrap_or_else(() => stop("LocalRunObservationOriginalUnavailable"))
          local_cancellation_operation(
            host,
            settings,
            crypto,
            sqlite,
            input_root,
            child,
            self.cancellation_recovery,
            capture=Some(capture),
            prepared=Some((self, configuration)),
          )
        } else if operation == "explain" {
          if optional(child, "run") is Some(_) {
            local_saved_run_explain(
              host,
              settings,
              crypto,
              child,
              capture=Some(capture),
            )
          } else {
            let context = local_check_context(
              host,
              crypto,
              name,
              capture=Some(capture),
              configuration=Some(configuration),
            )
            let input = self.prepare_static_request(capture, input_root, child)
            context.project_request(
              self,
              capture,
              input,
              true,
              installed_contracts=preparation_runtime.map(runtime => {
                runtime.installed_contracts
              }),
            )
          }
        } else if operation == "approve" || operation == "reject" {
          local_checkpoint_answer_by_id(
            host,
            settings,
            crypto,
            operation,
            child,
            capture=Some(capture),
            prepared=Some((self, configuration)),
          )
        } else if operation == "status" {
          let runtime = preparation_runtime.unwrap_or_else(() => {
            stop("LocalRunObservationOriginalUnavailable")
          })
          local_saved_run_status_command(
            host,
            settings,
            crypto,
            input_root,
            child,
            capture=Some(capture),
            human_display=Some(wire => {
              self.display_saved_waiting_run(capture, configuration, wire)
            }),
            original_reader=Some(id => {
              self.refresh_run_observation_state(
                host, capture, configuration, runtime, id,
              )
            }),
          )
        } else if local_quick_query_requested(operation, child) {
          let runtime = preparation_runtime.unwrap_or_else(() => {
            stop("LocalBusinessOriginalUnavailable")
          })
          self.execute_original_quick_query(
            host, capture, configuration, runtime, input_root, operation, child,
          )
        } else if operation == "result" {
          let runtime = preparation_runtime.unwrap_or_else(() => {
            stop("LocalBusinessOriginalUnavailable")
          })
          let physical = self.host.unwrap_or_else(() => {
            stop("LocalBusinessOriginalUnavailable")
          })
          let pair = self.pair.unwrap_or_else(() => {
            stop("LocalBusinessOriginalUnavailable")
          })
          let sqlite = physical
            .borrow_local_host_sqlite(pair)
            .unwrap_or_else(() => stop("LocalBusinessOriginalUnavailable"))
          let selected = self.prepare_original_result(
            host,
            capture,
            settings,
            name,
            runtime,
            sqlite,
            child,
            configuration=Some(configuration),
          )
          local_public_result(
            host,
            settings,
            crypto,
            sqlite,
            child,
            prepared=Some(selected),
          )
        } else if public_run && operation == local_run_original_operation() {
          let preflight = local_explicit_submission_preflight(
            host, capture, settings, crypto, input_root, operation, child,
          )
          if preflight is RetainedSubmissionRun(reply) {
            let runtime = preparation_runtime.unwrap_or_else(() => {
              stop("LocalReadOriginalCustodyUnavailable")
            })
            return Ok(
              if child.flags.get("json").unwrap_or(false) {
                self.present_retained_run(
                  host, capture, configuration, runtime, crypto, child, reply,
                )
              } else {
                let wire = self.present_retained_run(
                  host, capture, configuration, runtime, crypto, child, reply,
                )
                self.display_saved_waiting_run(capture, configuration, wire)
              },
            )
          }
          let original_input = match preflight {
            ExplicitSubmissionInput(selection, intent) =>
              Some((selection, intent))
            _ => None
          }
          let runtime = preparation_runtime.unwrap_or_else(() => {
            stop("LocalBusinessOriginalUnavailable")
          })
          let selection = self.prepare_business_submission(
            host,
            capture,
            configuration,
            runtime,
            input_root,
            operation,
            child,
            original_input~,
          )
          let physical = self.host.unwrap_or_else(() => {
            stop("LocalBusinessOriginalUnavailable")
          })
          let pair = self.pair.unwrap_or_else(() => {
            stop("LocalBusinessOriginalUnavailable")
          })
          let sqlite = physical
            .borrow_local_host_sqlite(pair)
            .unwrap_or_else(() => stop("LocalBusinessOriginalUnavailable"))
          self.execute_original_run_presentation(
            host, capture, settings, crypto, sqlite, name, runtime, input_root, operation,
            child, selection,
          )
        } else if operation == "adopt" &&
          child.flags.get("migrate-journal").unwrap_or(false) {
          let migrated = local_host_result(
            capture.migrate_journal_append_metadata_in_original_read(
              settings.principal,
              settings.connection,
            ),
          )
          match migrated {
            Ok(_) => ()
            Err(issue) => stop(local_journal_migration_issue(issue))
          }
          let account = local_host_result(
            capture.configuration_in_original_read(),
          )
          local_adoption_metadata_reply(
            true,
            settings.account_id,
            account.configuration_cid(),
            host.adoption_cid(),
            child,
          )
        } else {
          let runtime = self.runtime.unwrap()
          let run_file = settings.run_file.unwrap_or_else(() => {
            stop("LocalRunInstallationRequired")
          })
          local_host_result(
            capture.bind_packaged_runtime_in_original_read(
              runtime,
              settings.principal,
              settings.connection,
              environment_name,
              run_file,
              "runtime.json",
            ),
          )
          let account = local_host_result(
            capture.configuration_in_original_read(),
          )
          if account.account_id() != settings.account_id {
            stop("LocalConfigurationChanged")
          }
          let body = local_adoption_metadata_reply(
            true,
            settings.account_id,
            account.configuration_cid(),
            host.adoption_cid(),
            child,
          )
          local_host_result(capture.check_current_in_original_read())
          body
        }
        Ok(
          if public_run && !child.flags.get("json").unwrap_or(false) {
            self.display_fresh_waiting_run(settings, body)
          } else {
            body
          },
        )
      } catch {
        ClientStop(message) => Err(message)
      }
    }),
  )
}

///|
// Project discovery may advance only after the same missing-file receiver has
// acknowledged its cleanup. Retain it before returning to the existing caller;
// an unresolved Reader/Root prevents a second physical acquisition.
fn command_project_original_text(
  root : String,
  name : String,
) -> Result[String, @files.NativeBoundedTextFailure] raise ClientStop {
  guard command_preparation_invocation.val is Some(original) else {
    return @files.read_bounded_text_file_with_custody(root, name, 65536L)
  }
  if (!original.phase_open && !original.journal_read_open) ||
    original.closing ||
    original.closed ||
    original.primary is Some(_) {
    stop("LocalCommandPreparationUnavailable")
  }
  if original.read_failure is Some(previous) {
    match previous.retry_cleanup() {
      Err(_) => return Err(previous)
      Ok(_) => original.read_failure = None
    }
  }
  let result = @files.read_observed_text_file_in_current_read_context_with_custody(
    root,
    name,
    original.profile.diagnostic_ceiling,
    bytes => {
      match original.prepare_project_text_payload(bytes) {
        Ok(_) => true
        Err(issue) => {
          original.retain_primary(issue)
          false
        }
      }
    },
  )
  if result is Err(failure) {
    original.read_failure = Some(failure)
  }
  result
}

///|
// The bounded Reader's original transport/UTF8 envelope, also used by the
// existing Request intake: fixed controls, one Reader quantum and overlapping
// accumulation/copy buffers. These are representation quantities, not input
// ceilings, parser/Account admission or a physical allocation theorem.
fn local_project_text_payload_extent(bytes : Int64) -> (Int64, Int64)? {
  if bytes < 0L || bytes > 2147483518L {
    return None
  }
  guard @execution.checked_preparation_add_product(0L, bytes, 2L)
    is Some(text_peak) &&
    @execution.checked_preparation_add_product(65536L, bytes, 4L)
    is Some(wire_peak) &&
    @execution.preparation_representation_cost({
      record_headers: 8L,
      reference_slots: 16L,
      scalar_words: 16L,
      owned_utf16_units: bytes,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      record_headers: 8L,
      reference_slots: 16L,
      scalar_words: 16L,
      owned_utf16_units: text_peak,
      owned_wire_bytes: wire_peak,
    })
    is Some(execution) else {
    return None
  }
  Some((retained, execution))
}

///|
// Project discovery precedes the business Request. Use only the SAME entered
// initial Read, retaining each new text frame before its Reader/buffers exist.
// The existing owner checks selected policy/currentness and obtains actual
// domain backing before growing the original reservation. No MAX is prepaid.
fn LocalCommandPreparationOriginal::prepare_project_text_payload(
  self : Self,
  bytes : Int64,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard local_project_text_payload_extent(bytes) is Some((r, e)) else {
    return Err(CommandUnavailable)
  }
  // Keep the actual escaping String in the same metadata prefix used by the
  // next parser/index/settings constructor. Finished Reader scratch is a max,
  // never a second retained frame or a sum of historical temporary peaks.
  self.prepare_host_metadata(r, e)
}

///|
// The same cancellation reference survives command/cleanup failure. It grants
// no resend, physical ACK or replacement operation.
fn local_command_recovery_failure(message : String) -> String {
  match command_preparation_invocation.val {
    Some(original) =>
      local_cancellation_recovery_failure(
        original.cancellation_recovery.val,
        message,
      )
    None => message
  }
}

///|
// Closed response projection only; the reference is retained by the actual
// command before its cancellation transaction, never inferred here.
fn local_cancellation_recovery_failure(
  reference : String?,
  message : String,
) -> String {
  match reference {
    Some(original) =>
      local_cancellation_unknown(original) + " reason=" + message
    None => message
  }
}

///|
// Keep only immutable public correlation DATA in the existing initial-control
// owner before the cancellation transaction. Its original Read and every
// Store/DB receiver remain with their existing actual cleanup owners.
fn LocalCommandPreparationOriginal::retain_cancellation_recovery(
  self : LocalCommandPreparationOriginal,
  capture : @local_host.NativeLocalJournalCapture,
  reference : String,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard self.journal is Some(actual) &&
    physical_equal(actual, capture) &&
    self.journal_read_open &&
    self.cancellation_recovery.val is None &&
    !self.closing &&
    !self.closed &&
    self.primary is None else {
    return Err(CommandUnavailable)
  }
  match capture.suspend_original_read_for_preparation() {
    Err(issue) => return Err(CommandAdoption(issue))
    Ok(_) => ()
  }
  // The SAME bounded wire is borrowed while that Read remains retained. Only
  // its exact UTF-16 DATA is copied in the actual initial control context.
  self.cancellation_recovery.val = Some(command_control_copy_text(reference))
  capture
  .resume_original_read_after_preparation()
  .map_err(issue => CommandAdoption(issue))
}

///|
// Read only a retained typed refusal. Every returned label is complete/static:
// no error payload, Source/path, amount or opaque original is formatted. The
// generic legacy code/prefix remains when no precise closed cause is retained.
fn local_file_publication_failure_message(
  issue : @local_host.NativeClientSourceWorkIssue?,
) -> String {
  match issue {
    Some(Configuration) =>
      "LocalSourcePublicationEvidenceUnavailable:configuration"
    Some(OriginalRunNotCurrent) =>
      "LocalSourcePublicationEvidenceUnavailable:current"
    Some(NeedsOriginalReconciliation) =>
      "LocalSourcePublicationEvidenceUnavailable:reconciliation"
    Some(OriginalOperation(_)) =>
      "LocalSourcePublicationEvidenceUnavailable:operation"
    Some(Journal(_)) => "LocalSourcePublicationEvidenceUnavailable:journal"
    Some(RelationFile(_)) => "LocalSourcePublicationEvidenceUnavailable:capture"
    Some(CaptureIdentity(Unavailable)) =>
      "LocalSourcePublicationEvidenceUnavailable:identity-unavailable"
    Some(CaptureIdentity(DependencyBodyLimit)) =>
      "LocalSourcePublicationEvidenceUnavailable:identity-body-limit"
    Some(CaptureIdentity(_)) =>
      "LocalSourcePublicationEvidenceUnavailable:identity"
    Some(InputLogical(ForeignPrepared)) =>
      "LocalSourcePublicationEvidenceUnavailable:logical-foreign-prepared"
    Some(InputLogical(ForeignIdentity)) =>
      "LocalSourcePublicationEvidenceUnavailable:logical-foreign-identity"
    Some(InputLogical(ForeignRequirement)) =>
      "LocalSourcePublicationEvidenceUnavailable:logical-foreign-requirement"
    Some(InputLogical(_)) =>
      "LocalSourcePublicationEvidenceUnavailable:logical-evidence"
    Some(SourceEvidence(_)) =>
      "LocalSourcePublicationEvidenceUnavailable:source-evidence"
    Some(InstalledRun(Resource(Resource(RetentionLimit)))) =>
      "LocalSourcePublicationEvidenceUnavailable:body-retention"
    Some(InstalledRun(Resource(Resource(ExecutionLimit)))) =>
      "LocalSourcePublicationEvidenceUnavailable:body-execution"
    Some(InstalledRun(Resource(Resource(InvalidLimits)))) =>
      "LocalSourcePublicationEvidenceUnavailable:body-invalid-limits"
    Some(InstalledRun(Resource(Resource(ForeignOwner)))) =>
      "LocalSourcePublicationEvidenceUnavailable:body-foreign-owner"
    Some(InstalledRun(Resource(Resource(ClosedReservation)))) =>
      "LocalSourcePublicationEvidenceUnavailable:body-closed-reservation"
    Some(InstalledRun(Resource(Resource(InvalidCharge)))) =>
      "LocalSourcePublicationEvidenceUnavailable:body-invalid-charge"
    Some(InstalledRun(Resource(Resource(ChildFundingUnavailable)))) =>
      "LocalSourcePublicationEvidenceUnavailable:body-funding-unavailable"
    Some(InstalledRun(Resource(_))) =>
      "LocalSourcePublicationEvidenceUnavailable:body-original"
    Some(InstalledRun(_)) =>
      "LocalSourcePublicationEvidenceUnavailable:installed-run"
    Some(Preparation(ForeignOriginal)) =>
      "LocalSourcePublicationEvidenceUnavailable:preparation-foreign-original"
    Some(Preparation(WrongPhase)) =>
      "LocalSourcePublicationEvidenceUnavailable:preparation-wrong-phase"
    Some(
      Preparation(
        PublicationInvocation(RunEvidenceReferenceMismatch("task_run"))
      )
    ) => "LocalSourcePublicationEvidenceUnavailable:preparation-task-run"
    Some(
      Preparation(
        PublicationInvocation(RunEvidenceReferenceMismatch("source_coverage"))
      )
    ) => "LocalSourcePublicationEvidenceUnavailable:preparation-source-coverage"
    Some(
      Preparation(
        PublicationInvocation(RunEvidenceReferenceMismatch("source_task"))
      )
    ) => "LocalSourcePublicationEvidenceUnavailable:preparation-source-task"
    Some(
      Preparation(
        PublicationInvocation(RunEvidenceReferenceMismatch("source_policy"))
      )
    ) => "LocalSourcePublicationEvidenceUnavailable:preparation-source-policy"
    Some(
      Preparation(
        PublicationInvocation(RunEvidenceReferenceMismatch("source_evidence"))
      )
    ) => "LocalSourcePublicationEvidenceUnavailable:preparation-source-evidence"
    Some(
      Preparation(
        PublicationInvocation(
          RunEvidenceReferenceMismatch("publication_data_policy")
        )
      )
    ) =>
      "LocalSourcePublicationEvidenceUnavailable:preparation-publication-data-policy"
    Some(Preparation(PublicationInvocation(RunEvidenceReferenceMismatch(_)))) =>
      "LocalSourcePublicationEvidenceUnavailable:preparation-reference"
    Some(Preparation(PublicationInvocation(RunEvidenceInvalidLimits))) =>
      "LocalSourcePublicationEvidenceUnavailable:preparation-limits"
    Some(Preparation(PublicationInvocation(RunEvidenceInvalidWire))) =>
      "LocalSourcePublicationEvidenceUnavailable:preparation-wire"
    Some(Preparation(PublicationInvocation(_))) =>
      "LocalSourcePublicationEvidenceUnavailable:preparation-invocation"
    Some(Preparation(_)) =>
      "LocalSourcePublicationEvidenceUnavailable:preparation"
    _ => "LocalSourcePublicationEvidenceUnavailable"
  }
}

///|
// The failed Work already owns this exact typed primary and cleanup. Project
// only static closed constructor labels: no take, retry/current call, new
// wrapper, Source/path/amount formatting or permission is introduced.
fn local_file_open_failure_message(
  issue : @local_host.NativeClientSourceWorkIssue,
) -> String {
  match issue {
    Configuration => "LocalOriginalSourceWorkUnavailable:configuration"
    OriginalRunNotCurrent => "LocalOriginalSourceWorkUnavailable:current"
    NeedsOriginalReconciliation =>
      "LocalOriginalSourceWorkUnavailable:reconciliation"
    AuthorizationDenied => "LocalOriginalSourceWorkUnavailable:authorization"
    FileWorkSourceBinding => "LocalOriginalSourceWorkUnavailable:source-binding"
    FileWorkControlQuote => "LocalOriginalSourceWorkUnavailable:control-quote"
    FileWorkEntry(_) => "LocalOriginalSourceWorkUnavailable:entry"
    FileWorkPreparedCapacity(_) =>
      "LocalOriginalSourceWorkUnavailable:prepared-capacity"
    InstalledRead(ForeignOriginal) =>
      "LocalOriginalSourceWorkUnavailable:read-foreign-original"
    InstalledRead(AlreadyBound) =>
      "LocalOriginalSourceWorkUnavailable:read-already-bound"
    InstalledRead(AlreadyStarted) =>
      "LocalOriginalSourceWorkUnavailable:read-already-started"
    InstalledRead(Unbound) => "LocalOriginalSourceWorkUnavailable:read-unbound"
    InstalledRead(Retired) => "LocalOriginalSourceWorkUnavailable:read-retired"
    InstalledRead(CleanupPending) =>
      "LocalOriginalSourceWorkUnavailable:read-cleanup-pending"
    InstalledRead(_) => "LocalOriginalSourceWorkUnavailable:read"
    InstalledCapture(_) => "LocalOriginalSourceWorkUnavailable:capture-host"
    LocalExecution(InvalidLimits) =>
      "LocalOriginalSourceWorkUnavailable:compute-invalid-limits"
    LocalExecution(Fenced) =>
      "LocalOriginalSourceWorkUnavailable:compute-fenced"
    LocalExecution(UnsupportedGraph) =>
      "LocalOriginalSourceWorkUnavailable:compute-unsupported-graph"
    LocalExecution(MissingLocalModule) =>
      "LocalOriginalSourceWorkUnavailable:compute-missing-module"
    LocalExecution(Driver(original)) =>
      local_file_driver_failure_message(original)
    LocalExecution(Estimate(_)) =>
      "LocalOriginalSourceWorkUnavailable:compute-estimate"
    LocalExecution(FinalizationLimit) =>
      "LocalOriginalSourceWorkUnavailable:compute-finalization-limit"
    LocalExecution(MissingOutput) =>
      "LocalOriginalSourceWorkUnavailable:compute-missing-output"
    RelationFile(InvalidInput) =>
      "LocalOriginalSourceWorkUnavailable:source-invalid-input"
    RelationFile(Unavailable) =>
      "LocalOriginalSourceWorkUnavailable:source-unavailable"
    RelationFile(ForeignOriginal) =>
      "LocalOriginalSourceWorkUnavailable:source-foreign-original"
    RelationFile(Capacity) =>
      "LocalOriginalSourceWorkUnavailable:source-capacity"
    RelationFile(FileLimit) =>
      "LocalOriginalSourceWorkUnavailable:source-file-limit"
    RelationFile(Filesystem(_)) =>
      "LocalOriginalSourceWorkUnavailable:source-filesystem"
    RelationFile(Execution(_)) =>
      "LocalOriginalSourceWorkUnavailable:source-execution"
    RelationFile(Resource(RetentionLimit)) =>
      "LocalOriginalSourceWorkUnavailable:source-retention"
    RelationFile(Resource(ExecutionLimit)) =>
      "LocalOriginalSourceWorkUnavailable:source-execution-limit"
    RelationFile(Resource(InvalidLimits)) =>
      "LocalOriginalSourceWorkUnavailable:source-invalid-limits"
    RelationFile(Resource(_)) =>
      "LocalOriginalSourceWorkUnavailable:source-resource"
    RelationFile(Row(_)) => "LocalOriginalSourceWorkUnavailable:source-row"
    RelationFile(Document(_)) =>
      "LocalOriginalSourceWorkUnavailable:source-document"
    RelationFile(Mapping(_)) =>
      "LocalOriginalSourceWorkUnavailable:source-mapping"
    RelationFile(ManagedRead(_)) =>
      "LocalOriginalSourceWorkUnavailable:source-managed-read"
    RelationFile(_) => "LocalOriginalSourceWorkUnavailable:source"
    InstalledRun(Resource(Resource(RetentionLimit))) =>
      "LocalOriginalSourceWorkUnavailable:run-retention"
    InstalledRun(Resource(Resource(ExecutionLimit))) =>
      "LocalOriginalSourceWorkUnavailable:run-execution"
    InstalledRun(Resource(Resource(InvalidLimits))) =>
      "LocalOriginalSourceWorkUnavailable:run-invalid-limits"
    InstalledRun(Resource(Resource(ChildFundingUnavailable))) =>
      "LocalOriginalSourceWorkUnavailable:run-funding-unavailable"
    InstalledRun(Resource(_)) =>
      "LocalOriginalSourceWorkUnavailable:run-original"
    InstalledRun(_) => "LocalOriginalSourceWorkUnavailable:run"
    OriginalOperation(_) =>
      "LocalOriginalSourceWorkUnavailable:original-operation"
    Journal(_) => "LocalOriginalSourceWorkUnavailable:journal"
    CaptureIdentity(_) => "LocalOriginalSourceWorkUnavailable:capture-identity"
    InputLogical(_) => "LocalOriginalSourceWorkUnavailable:logical"
    Normalization(_) => "LocalOriginalSourceWorkUnavailable:normalization"
    _ => "LocalOriginalSourceWorkUnavailable"
  }
}

///|
// Preserve the driver's existing typed branch while borrowing its original
// cause. Static full labels only: no quantities, operation indices, Error
// contents, Source identities or provider strings are copied or formatted.
fn local_file_driver_failure_message(
  issue : @local_driver.LocalDispatchIssue,
) -> String {
  match issue {
    Configuration(original) =>
      local_file_fixed_compute_failure_message(original)
    Preparation(Candidate(original)) =>
      local_file_fixed_compute_failure_message(original)
    Preparation(Execution(original)) =>
      local_file_fixed_compute_failure_message(original)
    Preparation(NotSelected) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-preparation-not-selected"
    Preparation(Capacity) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-preparation-capacity"
    Preparation(Materializing(_)) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-preparation-materializing"
    Dispatch(_) => "LocalOriginalSourceWorkUnavailable:compute-driver-dispatch"
    Execution(Compute(original)) =>
      local_file_fixed_compute_failure_message(original)
    Execution(Physical(original)) =>
      local_file_driver_capacity_failure_message(original)
    Execution(UnsupportedGraph) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-execution-unsupported-graph"
    Execution(ForeignCapture) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-execution-foreign-capture"
    Execution(NotReady) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-execution-not-ready"
    Execution(Stopped) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-execution-stopped"
    Execution(ForeignCandidate) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-execution-foreign-candidate"
    Execution(PreviewWorkLimit) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-execution-preview-work"
    Execution(MissingOutput) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-execution-missing-output"
    Execution(Capture(_)) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-execution-capture"
    Execution(Binding(_)) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-execution-binding"
    Execution(Read(_)) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-execution-read"
    Execution(Implementation(_)) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-execution-implementation-unclassified"
    Execution(ActivationNotAuthorized) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-execution-not-authorized"
    Search(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-search-unclassified"
    ManagedValues(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-managed-values-unclassified"
    ManagedCopy(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-managed-copy-unclassified"
    ManagedRetention(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-managed-retention-unclassified"
    ManagedCompletion(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-managed-completion-unclassified"
    IdentityExport(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-identity-export-unclassified"
    CarrierSnapshot(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-carrier-snapshot-unclassified"
    ControlWorkLimit(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-control-work"
    LogicalWorkLimit(_, _, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-logical-work"
    ExecutionCapacityRefusal(original, _, _, _) =>
      local_file_driver_capacity_failure_message(original)
  }
}

///|
// These same typed FixedCompute leaves can arrive through configuration,
// module preparation or Compute execution. Their outer primary stays retained;
// no wrapper or diagnostic parser is constructed to classify the leaf.
fn local_file_fixed_compute_failure_message(
  issue : @compute_sdk.FixedComputeIssue,
) -> String {
  match issue {
    UnsupportedInputShape =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-input-shape"
    InputUnavailable =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-input-unavailable"
    ForeignPreparation =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-foreign-preparation"
    ForeignRequest(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-foreign-request"
    ForeignCapability(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-foreign-capability"
    CapabilityClosed =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-capability-closed"
    ComputeUnsupported =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-unsupported-compute"
    NotSelected =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-not-selected"
    InvalidLimits =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-invalid-limits"
    CapacityContract =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-capacity-contract"
    CommonInputRows =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-input-rows"
    CommonFragmentUnsupported =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-unsupported-fragment"
    LogicalIdentityUnsupported =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-logical-identity"
    PlanningLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-planning-limit"
    NegativeQuantity =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-negative-quantity"
    ControlWorkLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-fixed-control-work"
    Execution(original) => local_file_sequence_failure_message(original)
    Cost(original) => local_file_cost_failure_message(original)
    Guard(original) => local_file_guard_failure_message(original)
  }
}

///|
fn local_file_driver_capacity_failure_message(
  issue : @initial_resources.LedgerIssue,
) -> String {
  match issue {
    RetentionLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-retention"
    ExecutionLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-execution"
    InvalidLimits =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-invalid-limits"
    PlanningLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-planning"
    AttemptLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-attempt"
    HoldingLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-holding"
    TransferLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-transfer"
    ForeignOwner =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-foreign-owner"
    ClosedReservation =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-closed-reservation"
    ClosedHolding =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-closed-holding"
    InvalidCharge =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-invalid-charge"
    IdentityOverflow =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-identity-overflow"
    TokenLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-token"
    CostLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-cost"
    DurationLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-duration"
    ResourceParked =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-parked"
    ChildFundingUnavailable =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-capacity-child-funding"
  }
}

///|
fn local_file_cost_failure_message(issue : @cost.CostIssue) -> String {
  match issue {
    InvalidLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-cost-invalid-limit"
    PlanningLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-cost-planning-limit"
    EmptyCoverage(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-cost-empty-coverage"
    InvalidSlot(_, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-cost-invalid-slot"
    DuplicateSlot(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-cost-duplicate-slot"
    NegativeDuration(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-cost-negative-duration"
    DurationOverflow =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-cost-duration-overflow"
    InvalidPreference =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-cost-invalid-preference"
  }
}

///|
fn local_file_guard_failure_message(
  issue : @execution.FixedInputGuardIssue,
) -> String {
  match issue {
    InvalidLimits =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-guard-invalid-limits"
    ForeignInput =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-guard-foreign-input"
    MeasurementWork =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-guard-measurement-work"
    Measurement(_, _, _, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-guard-measurement-unclassified"
    ValueBytes(_, _, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-guard-value-bytes"
    InvalidLayout =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-guard-invalid-layout"
    InputRows =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-guard-input-rows"
    OutputRows =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-guard-output-rows"
    MissingOutput =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-guard-missing-output"
    InputRepresentationRequired(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-guard-representation-required"
    Execution(original) => local_file_sequence_failure_message(original)
  }
}

///|
fn local_file_sequence_failure_message(
  issue : @execution.SequenceRunIssue,
) -> String {
  match issue {
    InvalidLimits =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-invalid-limits"
    InputOwnership =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-input-ownership"
    InputSet =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-input-set"
    InputExecutionEvidencePending(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-input-evidence-pending"
    InputRepresentationRequired(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-input-representation-required"
    InputLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-input-limit"
    InputKey(_, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-input-key-unclassified"
    InputScore(_, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-input-score-unclassified"
    Wiring(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-wiring-unclassified"
    Capture(_, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-capture-unclassified"
    Store(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-store-unclassified"
    OrderedContext(_, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-ordered-context-unclassified"
    FragmentContext(_, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-fragment-context-unclassified"
    MissingFragmentContext(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-fragment-context-missing"
    MixedExecutionConfiguration =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-mixed-configuration"
    UnsupportedRowComparison(_, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-sequence-row-comparison-unsupported"
    Rows(_, original) => local_file_row_failure_message(original)
  }
}

///|
fn local_file_row_failure_message(issue : @execution.RowIssue) -> String {
  match issue {
    OwnerMismatch =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-owner-mismatch"
    InputMismatch =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-input-mismatch"
    InvalidRows =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-invalid-rows"
    RowLimit => "LocalOriginalSourceWorkUnavailable:compute-driver-row-limit"
    InvalidRowLimits =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-invalid-limits"
    MissingOrderedResourceContext =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-ordered-context-missing"
    LogicalRows(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-logical-budget-unclassified"
    Evaluation(_, _, original) =>
      local_file_evaluation_kind_failure_message(original.kind)
    Comparison(original) | Aggregation(original) =>
      local_file_scalar_failure_message(original)
    DedupeTopTie(_, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-dedupe-top-tie"
    DedupeIdentityCollision =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-dedupe-collision"
    AssertionPredicate(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-assertion-predicate"
    AssertionNullKey(_, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-assertion-null-key"
    AssertionDuplicate(_, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-assertion-duplicate"
    JoinNullKey(_, _, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-join-null-key"
    JoinDuplicateKey(_, _, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-join-duplicate-key"
    AsOfTopTie(_, _, _) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-asof-top-tie"
    WindowTime(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-window-time"
    WindowArithmetic(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-window-arithmetic"
    AnalyticEnvelope(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-analytic-envelope-unclassified"
    NestItemLimitRequired =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-nest-limit-required"
    NestItemLimit(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-nest-item-limit"
    NestEnvelope(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-nest-envelope-unclassified"
    TemporalPrecisionUnavailable =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-row-temporal-precision"
  }
}

///|
// EvalIssue exposes this existing readonly kind; its expression stays private
// to the retained original. No diagnostic object or expression copy is needed.
fn local_file_evaluation_kind_failure_message(
  kind : @execution.EvalIssueKind,
) -> String {
  match kind {
    InvalidControlLimits =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-evaluation-invalid-control-limits"
    ControlLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-evaluation-control-limit"
    WorkspaceLimit =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-evaluation-workspace-limit"
    MissingValue =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-evaluation-missing-value"
    Scalar(original) => local_file_scalar_failure_message(original)
    LogicalEntry(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-evaluation-logical-entry-unclassified"
    LogicalValue(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-evaluation-logical-value-unclassified"
    QueryEvaluationTimeUnavailable =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-evaluation-query-time-unavailable"
    TextBounds(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-evaluation-text-bounds-unclassified"
    NumberConversion(_) =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-evaluation-number-conversion-unclassified"
    TimestampCanonicalRequired =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-evaluation-timestamp-canonical-required"
  }
}

///|
// Evaluation, comparison and aggregation retain their original outer primary;
// these three closed scalar leaves contain no diagnostic values or expressions.
fn local_file_scalar_failure_message(issue : @execution.ScalarIssue) -> String {
  match issue {
    InvalidOperand =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-scalar-invalid-operand"
    ArithmeticFailure =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-scalar-arithmetic-failure"
    ComparisonDomainNotImplemented =>
      "LocalOriginalSourceWorkUnavailable:compute-driver-scalar-comparison-domain-unimplemented"
  }
}
