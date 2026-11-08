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
    CommandRequestPreparation(_) => "request-preparation"
    CommandNativeStorage(_) => "native-storage"
    CommandHost(_) => "host"
    CommandDomain(_) => "domain"
    CommandRead(_) => "read"
    CommandRetainedExecution(_) => "business-execution"
    CommandStoreOperation(_) => "business-operation"
    CommandBusinessChildren => "business-children"
    CommandBusinessModel(_) => "business-model"
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
      let message = match stage {
        None => "LocalCommandPreparationUnavailable"
        Some(name) =>
          "LocalCommandPreparationUnavailable:" +
          name +
          ":" +
          command_preparation_cleanup_kind(issue)
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
      let selected = @run_host.client_native_local_finite_product_originals(
        configuration_root,
        runtime.sqlite,
        runtime.crypto,
        local_utc_now(),
        runtime.assets,
        runtime.manifest,
        mock=match self.project {
          Some(project) if operation == "adopt" &&
            project.mock_declarations is Some(mock) =>
            Some(
              mock
              .account_subjects()
              .unwrap_or_else(() => stop("LocalProjectBindingsUnavailable")),
            )
          _ => None
        },
      ).unwrap_or_else(() => stop("LocalProductDefaultsNotAdmitted"))
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
  let configuration = text_file(configuration_root, "config.json", 65536L)
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
  if operation == "status" || operation == "cancel" {
    command_preparation_result(self.prepare_run_observation_operation())
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
            context.project_request(self, capture, input, true)
          }
        } else if operation == "approve" || operation == "reject" {
          local_checkpoint_answer_by_id(
            host,
            settings,
            crypto,
            operation,
            child,
            capture=Some(capture),
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
              self.present_retained_run(
                host, capture, configuration, runtime, crypto, child, reply,
              ),
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
        Ok(body)
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
  let result = @files.read_bounded_text_file_in_current_read_context_with_custody(
    root,
    name,
    65536L,
    original.profile.diagnostic_ceiling,
  )
  if result is Err(failure) {
    original.read_failure = Some(failure)
  }
  result
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
