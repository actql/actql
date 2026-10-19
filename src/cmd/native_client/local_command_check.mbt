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
    CommandNativeStorage(_) => "native-storage"
    CommandBacking(code) => "backing(" + code.to_string() + ")"
    CommandHost(_) => "host"
    CommandDomain(_) => "domain"
    CommandRead(_) => "read"
    CommandRetainedExecution(_) => "business-execution"
    CommandStoreOperation(_) => "business-operation"
    CommandBusinessChildren => "business-children"
    CommandBusinessPublication => "business-publication"
    CommandBusinessStore(_) => "business-store"
    CommandPair(value) =>
      match value {
        @initial_arena.Read(_) => "pair-read"
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
    CommandFilesystem(_) => "filesystem"
    CommandFilesystemCleanup(_) => "filesystem-cleanup"
  }
}

///|
fn[T] command_preparation_result(
  result : Result[T, LocalCommandPreparationIssue],
) -> T raise ClientStop {
  match result {
    Ok(value) => value
    Err(_) => stop("LocalCommandPreparationUnavailable")
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
) -> Bool {
  operation == "check" ||
  operation == "explain" ||
  operation == "adopt" ||
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
  command_preparation_result(self.leave())
  let runtime = local_packaged_runtime_from_physical(physical)
  command_preparation_result(self.enter())
  // Required HOME/path decoding and selection now allocate in the same
  // consuming Read; an explicit directory never obtains the HOME workspace.
  let location = local_product_original_location(optional(matches, "state-dir"))
  let configuration_root = if location.parent_path == "/" {
    "/" + location.directory_name
  } else {
    location.parent_path + "/" + location.directory_name
  }
  let originals = if operation == "adopt" {
    let parent = command_preparation_result(
      self.select_product_parent(location.parent_path),
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
  )
  let original_runtime = text_file(configuration_root, "runtime.json", 65536L)
  local_product_require_same_runtime_wire(
    original_runtime,
    @run_host.client_native_local_runtime_original(runtime.manifest),
  )
  let settings = local_host_settings(
    text_file(configuration_root, "config.json", 65536L),
  )
  if settings.sqlite_library != runtime.sqlite ||
    settings.signature_library != runtime.crypto ||
    !settings.installation_files.contains("runtime.json") {
    stop("PackagedLocalRuntimeChanged")
  }
  command_preparation_result(
    self.stage_product(location.parent_path, location.directory_name, None),
  )
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
  )
}

///|
// Continue the existing selected configuration comparisons. The same actual
// adoption capture owns every partial Root/Lock and the original child Journal;
// this path never loads a second SQLite Library or a stock Crypto fallback.
fn LocalCommandPreparationOriginal::execute_adopted_command(
  self : LocalCommandPreparationOriginal,
  operation : String,
  settings : LocalHostSettings,
  root : String,
  name : String,
  configuration : String,
  environment_name : String,
  environment : String,
  selected_files : Array[String],
  selected_additional : Array[(String, Bytes)],
  input_root : String,
  child : @argparse.Matches,
  public_run? : Bool = false,
  preparation_runtime? : LocalPackagedRuntime? = None,
) -> String raise ClientStop {
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
      operation == "adopt",
    ),
  )
  let expected = [
    (name, @utf8.encode(configuration)),
    (environment_name, @utf8.encode(environment)),
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
  // Only the actual explicit initializer may request its existing first-key
  // branch. The Session independently decides eligibility and durable custody.
  let initialize_signing = operation == "adopt" &&
    child.flags.get("initialize-signing").unwrap_or(false)
  command_preparation_result(
    self.open_adopted_journal(initialize_signing, {
      initialize_signing,
      ttl_ms: settings.ttl_ms,
      max_records: settings.record_limit,
      max_snapshot_bytes: settings.snapshot_bytes,
    }),
  )
  |> ignore
  let crypto = self.inner_library.unwrap()
  command_preparation_result(
    self.read_command(fn(host, capture) {
      try {
        let body = if operation == "check" {
          local_check_for_host(
            host,
            crypto,
            name,
            input_root,
            child,
            capture=Some(capture),
          )
        } else if operation == "explain" {
          local_check_context(host, crypto, name, capture=Some(capture)).explain(
            input_root, child,
          )
        } else if operation == "status" {
          local_saved_run_status_command(
            host,
            settings,
            crypto,
            input_root,
            child,
            capture=Some(capture),
          )
        } else if public_run && operation == local_run_original_operation() {
          let runtime = preparation_runtime.unwrap_or_else(() => {
            stop("LocalBusinessOriginalUnavailable")
          })
          let selection = self.prepare_business_submission(
            host, capture, name, runtime, input_root, operation, child,
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
          local_submission_start(
            host,
            settings,
            crypto,
            sqlite,
            selection.environment,
            input_root,
            operation,
            child,
            public_run=true,
            business=Some(selection),
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
          local_host_result(
            capture.require_packaged_runtime_upgrade_in_original_read(),
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
