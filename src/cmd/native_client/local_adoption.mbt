///|
priv struct LocalHostSettings {
  account_file : String
  account_id : String
  principal : String
  connection : String
  state_parent : String
  state_name : String
  managed_root : String
  sqlite_library : String
  signature_library : String
  ttl_ms : Double
  record_limit : Int
  snapshot_bytes : Int64
  installation_files : Array[String]
  source_file : String?
  run_file : String?
  read_file : String?
  run_policy_profile_file : String?
  reviewer_file : String?
  initial_host_signing : (String, String, String)?
}

///|
fn local_settings_text(
  object : @decode.ObjectView,
  key : String,
) -> String raise ClientStop {
  guard @decode.lookup(object, key) is Some(value) &&
    @decode.text(value) is Ok(text) &&
    !text.is_empty() &&
    text.length() <= 4096 else {
    stop("InvalidLocalHostConfiguration")
  }
  text
}

///|
// Finite physical settings are selected by the operator, never by a Program.
// Limits are explicit; no existing Owner budget is silently increased.
fn local_host_settings(text : String) -> LocalHostSettings raise ClientStop {
  // Count the bounded typed decode, not consumers of these immutable fields.
  native_timing_count(27)
  let cursor = local_input_cursor(text)
  let root = @decode.closed_object(cursor, [
    "version", "native", "state_dir", "account_config",
  ]).unwrap_or_else(() => stop("InvalidLocalHostConfiguration"))
  guard local_settings_text(root, "version") == "actql-config/0.1" &&
    @decode.lookup(root, "native") is Some(native) else {
    stop("InvalidLocalHostConfiguration")
  }
  let native = @decode.closed_object(native, ["check_environment", "local"]).unwrap_or_else(() => {
      stop("InvalidLocalHostConfiguration")
    },
  )
  guard @decode.lookup(native, "local") is Some(fields) else {
    stop("LocalHostConfigurationRequired")
  }
  let fields = @decode.closed_object(fields, [
    "account_id", "principal", "connection", "state_parent", "state_name", "managed_root",
    "sqlite_library", "signature_library", "submission_ttl_ms", "journal_record_limit",
    "journal_snapshot_bytes", "installation_files", "source_file", "run_file", "read_file",
    "reviewer_file", "run_policy_profile_file", "initial_host_signing",
  ]).unwrap_or_else(() => stop("InvalidLocalHostConfiguration"))
  let number = fn(key : String) -> Int64 raise ClientStop {
    guard @decode.lookup(fields, key) is Some(value) &&
      @decode.safe_integer(value) is Ok(value) else {
      stop("InvalidLocalHostConfiguration")
    }
    value
  }
  let ttl = number("submission_ttl_ms")
  let records = number("journal_record_limit")
  let snapshot = number("journal_snapshot_bytes")
  if ttl < 1L ||
    ttl > 86400000L ||
    records < 1L ||
    records > 1024L ||
    snapshot < 1L ||
    snapshot > 536870912L {
    stop("InvalidLocalHostLimits")
  }
  let installation_files : Array[String] = []
  if @decode.lookup(fields, "installation_files") is Some(files) {
    guard @decode.elements(files) is Ok(files) && files.length() <= 8 else {
      stop("InvalidLocalInstallationSelection")
    }
    for file in files {
      guard @decode.text(file) is Ok(name) &&
        !name.is_empty() &&
        name.length() <= 128 &&
        !installation_files.contains(name) else {
        stop("InvalidLocalInstallationSelection")
      }
      installation_files.push(name)
    }
  }
  let initial_host_signing = match
    @decode.lookup(fields, "initial_host_signing") {
    None => None
    Some(value) => {
      let selected = @decode.closed_object(value, [
        "principal", "connection", "resource",
      ]).unwrap_or_else(() => stop("InvalidInitialHostSigningSelection"))
      let principal = local_settings_text(selected, "principal")
      let connection = local_settings_text(selected, "connection")
      let resource = local_settings_text(selected, "resource")
      for text in [principal, connection, resource] {
        if text.length() > 256 || text.contains("\u{0}") {
          stop("InvalidInitialHostSigningSelection")
        }
      }
      Some((principal, connection, resource))
    }
  }
  let settings : LocalHostSettings = {
    account_file: local_settings_text(root, "account_config"),
    account_id: local_settings_text(fields, "account_id"),
    principal: local_settings_text(fields, "principal"),
    connection: local_settings_text(fields, "connection"),
    state_parent: local_settings_text(fields, "state_parent"),
    state_name: local_settings_text(fields, "state_name"),
    managed_root: local_settings_text(fields, "managed_root"),
    sqlite_library: local_settings_text(fields, "sqlite_library"),
    signature_library: local_settings_text(fields, "signature_library"),
    ttl_ms: ttl.to_double(),
    record_limit: records.to_int(),
    snapshot_bytes: snapshot,
    installation_files,
    initial_host_signing,
    run_policy_profile_file: match
      @decode.lookup(fields, "run_policy_profile_file") {
      None => None
      Some(_) => Some(local_settings_text(fields, "run_policy_profile_file"))
    },
    reviewer_file: match @decode.lookup(fields, "reviewer_file") {
      None => None
      Some(_) => Some(local_settings_text(fields, "reviewer_file"))
    },
    read_file: match @decode.lookup(fields, "read_file") {
      None => None
      Some(_) => Some(local_settings_text(fields, "read_file"))
    },
    run_file: match @decode.lookup(fields, "run_file") {
      None => None
      Some(_) => Some(local_settings_text(fields, "run_file"))
    },
    source_file: match @decode.lookup(fields, "source_file") {
      None => None
      Some(_) => Some(local_settings_text(fields, "source_file"))
    },
  }
  if settings.principal.length() > 512 || settings.connection.length() > 512 {
    stop("InvalidLocalHostConfiguration")
  }
  if settings.reviewer_file is Some(file) &&
    !settings.installation_files.contains(file) {
    stop("LocalReviewerOriginalNotSelected")
  }
  if settings.run_policy_profile_file is Some(file) &&
    !settings.installation_files.contains(file) {
    stop("LocalRunPolicyProfileNotSelected")
  }
  if @decode.lookup(root, "state_dir") is Some(value) {
    guard @decode.text(value) is Ok(path) &&
      path == settings.state_parent + "/" + settings.state_name else {
      stop("ConflictingLocalHostState")
    }
  }
  settings
}

///|
fn local_host_issue(issue : @local_host.NativeLocalAdoptionIssue) -> String {
  match issue {
    SourceChanged => "LocalConfigurationChanged"
    CustodyLost => "LocalHostCustodyLost"
    AmbiguousInitialization | TransactionUnknown => "LocalAdoptionUnknown"
    ForeignAccount => "ForeignLocalAccount"
    Fenced => "LocalHostFenced"
    _ => "LocalHostAdoptionRefused"
  }
}

///|
fn[T] local_host_result(
  value : Result[T, @local_host.NativeLocalAdoptionIssue],
) -> T raise ClientStop {
  match value {
    Ok(value) => value
    Err(issue) => stop(local_host_issue(issue))
  }
}

///|
fn execute_native_local_adoption(
  matches : @argparse.Matches,
  operation : String,
  child : @argparse.Matches,
  packaged_runtime? : @local_host.NativeLocalPackagedRuntime? = None,
  initial_crypto? : InitialCryptoOriginal? = None,
  preparation? : LocalCommandPreparationOriginal? = None,
  preparation_runtime? : LocalPackagedRuntime? = None,
  configuration_original? : (String, LocalHostSettings)? = None,
) -> String raise ClientStop {
  native_timing_begin(12)
  defer native_timing_end(12)
  if preparation is None && command_preparation_invocation.val is Some(original) {
    return original.execute_operator_command(matches, operation, child)
  }
  if operation == "adopt" && child.flags.get("migrate-journal").unwrap_or(false) {
    command_preparation_diagnostic.val = JournalMaintenanceFailed
  }
  let root = required(matches, "config-root")
  let name = required(matches, "config-file")
  let input_root = local_document_root(matches, root)
  // Refuse an untrusted discovery root before loading configuration-selected
  // physical libraries. The adoption Owner rechecks all original generations.
  let selected_root = match preparation {
    Some(original) =>
      command_preparation_result(
        original.select_configuration_root(root),
        stage=Some("configuration-root"),
      )
    None =>
      @local_filesystem.open_private_root(root).unwrap_or_else(() => {
        stop("LocalConfigurationRootUntrusted")
      })
  }
  let root_ownership = selected_root
    .private_ownership()
    .unwrap_or_else(() => stop("LocalConfigurationRootUntrusted"))
  // The selected Product path already read and decoded this exact body. Its
  // original Session still compares the bytes before opening the Journal.
  let (configuration, settings) = match configuration_original {
    Some(original) => {
      guard preparation is Some(_) else {
        stop("LocalCommandPreparationUnavailable")
      }
      original
    }
    None => {
      let body = text_file(root, name, 65536L)
      (body, local_host_settings(body))
    }
  }
  if configuration_original is None && preparation_runtime is Some(runtime) {
    if settings.sqlite_library != runtime.sqlite ||
      settings.signature_library != runtime.crypto ||
      !settings.installation_files.contains("runtime.json") {
      stop("PackagedLocalRuntimeChanged")
    }
    local_product_require_same_runtime_wire(
      text_file(root, "runtime.json", 65536L),
      @run_host.client_native_local_runtime_original(runtime.manifest),
    )
  }
  let (environment_file, evidence_cid) = local_configuration(configuration)
  let environment = text_file(root, environment_file, 65536L)
  let check_environment = match preparation {
    Some(_) =>
      local_command_check_environment(
        operation, child, environment, evidence_cid,
      )
    None =>
      Some(
        local_admitted_check_environment(environment, evidence_cid).unwrap_or_else(() => {
            stop("InvalidLocalCheckEnvironment")
          },
        ),
      )
  }
  guard selected_root.private_ownership() is Ok(current) &&
    current == root_ownership else {
    stop("LocalConfigurationRootUntrusted")
  }
  // The operator selects installation originals separately from submitted
  // Program data. Their bytes and generations join the same adoption intent;
  // naming a file installs no Source, Policy, credential or execution grant.
  let selected_files = [name, environment_file]
  for file in settings.installation_files {
    if selected_files.contains(file) || file == settings.account_file {
      stop("InvalidLocalInstallationSelection")
    }
    selected_files.push(file)
  }
  let selected_source = match settings.source_file {
    None => None
    Some(file) => {
      if !settings.installation_files.contains(file) {
        stop("LocalSourceOriginalNotSelected")
      }
      let body = text_file(root, file, 65536L)
      ignore(local_source_installation(body))
      Some((file, @utf8.encode(body)))
    }
  }
  let (selected_run, run_original) = match settings.run_file {
    None => (None, None)
    Some(file) => {
      if !settings.installation_files.contains(file) {
        stop("LocalRunOriginalNotSelected")
      }
      let original = local_command_run_installation_original(
        file,
        text_file(root, file, 65536L),
      )
      (Some((file, original.body)), Some(original))
    }
  }
  let selected_read = match settings.read_file {
    None => None
    Some(file) => {
      if !settings.installation_files.contains(file) {
        stop("LocalReadPolicyOriginalNotSelected")
      }
      let body = text_file(root, file, 65536L)
      ignore(local_read_installation_or_stop(body))
      Some((file, @utf8.encode(body)))
    }
  }
  let selected_reviewer = local_selected_effect_reviewer_original(
    root, settings,
  )
  if preparation is Some(original) {
    if !local_command_preparation_operation_selected(
        matches,
        operation,
        original.business is Some(_),
      ) {
      stop("LocalCommandPreparationOperationUnavailable")
    }
    let additional : Array[(String, Bytes)] = []
    for
      selected in [
        selected_source, selected_run, selected_read, selected_reviewer,
      ] {
      if selected is Some(value) {
        additional.push(value)
      }
    }
    return original.execute_adopted_command(
      operation,
      root,
      {
        configuration_name: name,
        configuration_body: @utf8.encode(configuration),
        settings,
        environment_name: environment_file,
        environment_body: @utf8.encode(environment),
        environment: check_environment,
        run_original,
      },
      selected_files,
      additional,
      input_root,
      child,
      public_run=matches.subcommand is Some(("run", _)),
      preparation_runtime~,
    )
  }
  // The unselected compatibility entrance keeps its original complete
  // Environment admission, including commands that do not prepare a Program.
  let check_environment = check_environment.unwrap_or_else(() => {
    stop("InvalidLocalCheckEnvironment")
  })
  let (sqlite_path, crypto_path) = match packaged_runtime {
    None => (settings.sqlite_library, settings.signature_library)
    Some(runtime) =>
      runtime
      .library_paths()
      .unwrap_or_else(() => stop("PackagedLocalRuntimeChanged"))
  }
  let crypto = match initial_crypto {
    Some(original) => {
      guard packaged_runtime is Some(runtime) &&
        physical_equal(runtime, original.package_original) else {
        stop("ForeignInitialCryptoOriginal")
      }
      original
      .library(true)
      .unwrap_or_else(() => stop("InitialCryptoInnerLibraryUnavailable"))
    }
    None =>
      @local_crypto.load_library(crypto_path).unwrap_or_else(() => {
        stop("NativeLocalSignatureUnavailable")
      })
  }
  let sqlite = @local_sqlite.load_library(sqlite_path).unwrap_or_else(() => {
    stop("NativeLocalJournalUnavailable")
  })
  if packaged_runtime is Some(runtime) && runtime.check_current() is Err(_) {
    stop("PackagedLocalRuntimeChanged")
  }
  let session = local_host_result(
    @local_host.begin_native_local_host_adoption(
      settings.state_parent,
      settings.state_name,
      root,
      settings.account_file,
      settings.account_id,
      crypto,
      configuration_files=selected_files,
      managed_root_path=Some(settings.managed_root),
      existing_only=operation != "adopt",
    ),
  )
  // Close the parse-to-adoption race before any journal key or epoch is created.
  guard session.selected_configuration(name) is Ok(selected_config) &&
    selected_config == @utf8.encode(configuration) &&
    session.selected_configuration(environment_file) is Ok(selected_environment) &&
    selected_environment == @utf8.encode(environment) else {
    if !session.close() {
      stop("LocalConfigurationChangedCleanupPending")
    }
    stop("LocalConfigurationChanged")
  }
  if selected_source is Some((file, body)) {
    guard session.selected_configuration(file) is Ok(selected) &&
      selected == body else {
      if !session.close() {
        stop("LocalConfigurationChangedCleanupPending")
      }
      stop("LocalConfigurationChanged")
    }
  }
  if selected_run is Some((file, body)) {
    guard session.selected_configuration(file) is Ok(selected) &&
      selected == body else {
      if !session.close() {
        stop("LocalConfigurationChangedCleanupPending")
      }
      stop("LocalConfigurationChanged")
    }
  }
  if selected_read is Some((file, body)) {
    guard session.selected_configuration(file) is Ok(selected) &&
      selected == body else {
      if !session.close() {
        stop("LocalConfigurationChangedCleanupPending")
      }
      stop("LocalConfigurationChanged")
    }
  }
  if selected_reviewer is Some((file, body)) {
    guard session.selected_configuration(file) is Ok(selected) &&
      selected == body else {
      if !session.close() {
        stop("LocalConfigurationChangedCleanupPending")
      }
      stop("LocalConfigurationChanged")
    }
  }
  let host = match
    local_open_initial_signing_adoption(session, sqlite, crypto, {
      initialize_signing: operation == "adopt" &&
      child.flags.get("initialize-signing").unwrap_or(false),
      ttl_ms: settings.ttl_ms,
      max_records: settings.record_limit,
      max_snapshot_bytes: settings.snapshot_bytes,
      initial_host_signing: settings.initial_host_signing,
    }) {
    Ok(value) => value
    Err(DatabasePending(database, issue)) => {
      if database.close_checked() is Err(_) {
        stop("LocalHostOpenCleanupPending")
      }
      if !session.close() {
        stop("LocalHostOpenCleanupPending")
      }
      stop(local_host_issue(issue))
    }
    Err(issue) => {
      if !session.close() {
        stop("LocalHostOpenCleanupPending")
      }
      stop(local_host_issue(issue))
    }
  }
  // Produce the reply before closing, but never publish it before confirmed close.
  let cancellation_recovery : Ref[String?] = Ref(None)
  let reply = {
    errdefer (if host.close() is Err(_) {
      if cancellation_recovery.val is Some(reference) {
        stop(
          local_cancellation_unknown(reference) +
          " reason=LocalHostCleanupPending",
        )
      }
      stop("LocalHostCleanupPending")
    })
    try {
      // Static check uses the original Host/configuration and the outer product
      // physical fences; it does not bind a Run or demand an execution upgrade.
      if packaged_runtime is Some(runtime) && operation != "check" {
        let run_file = settings.run_file.unwrap_or_else(() => {
          stop("LocalRunInstallationRequired")
        })
        host
        .bind_packaged_runtime(
          runtime,
          settings.principal,
          settings.connection,
          environment_file,
          run_file,
          "runtime.json",
        )
        .unwrap_or_else(() => stop("PackagedLocalRuntimeChanged"))
        |> ignore
        if operation != "upgrade-policy" && operation != "lookup-policy-upgrade" {
          host
          .require_packaged_runtime_upgrade()
          .unwrap_or_else(() => stop("ExplicitLocalRuntimeUpgradeRequired"))
          |> ignore
        }
      }
      if operation == "check" {
        local_check_for_host(host, crypto, name, input_root, child)
      } else if local_quick_query_requested(operation, child) {
        local_quick_query(
          host, settings, crypto, sqlite, check_environment, input_root, operation,
          child,
        )
      } else if operation == "start" || operation == "aql" {
        local_submission_start(
          host,
          settings,
          crypto,
          sqlite,
          check_environment,
          input_root,
          operation,
          child,
          public_run=matches.subcommand is Some(("run", _)),
        )
      } else if operation == "upgrade-policy" ||
        operation == "lookup-policy-upgrade" {
        local_run_policy_upgrade_operation(
          host, settings, crypto, operation, child,
        )
      } else if operation == "lookup-submission" {
        local_submission_lookup(host, settings, crypto, input_root, child)
      } else if operation == "lookup-request" {
        local_request_lookup(host, settings, crypto, child)
      } else if operation == "approve" || operation == "reject" {
        local_checkpoint_answer_by_id(host, settings, crypto, operation, child)
      } else if operation == "checkpoint-state" {
        local_checkpoint_metadata_lookup(
          host, settings, crypto, input_root, child,
        )
      } else if operation == "status" {
        local_saved_run_status_command(
          host, settings, crypto, input_root, child,
        )
      } else if operation == "lookup-preparation-grant" {
        local_preparation_grant_lookup(
          host, settings, crypto, input_root, child,
        )
      } else if operation == "lookup-preparation-raw" {
        local_preparation_raw_lookup(
          host, settings, crypto, sqlite, input_root, child,
        )
      } else if operation == "lookup-cancellation" {
        local_cancellation_lookup(host, settings, crypto, input_root, child)
      } else if operation == "cancel" {
        local_cancellation_operation(
          host, settings, crypto, sqlite, input_root, child, cancellation_recovery,
        )
      } else if operation == "delivery-attempt" {
        local_delivery_attempt_lookup(
          host, settings, crypto, sqlite, input_root, child,
        )
      } else if operation == "result" {
        local_public_result(host, settings, crypto, sqlite, child)
      } else if operation == "read" {
        local_result_stream(host, settings, crypto, sqlite, input_root, child)
      } else if operation == "adopt" &&
        child.flags.get("migrate-journal").unwrap_or(false) {
        match
          host.migrate_journal_append_metadata(
            settings.principal,
            settings.connection,
            settings.snapshot_bytes,
          ) {
          Ok(_) => ()
          Err(issue) => stop(local_journal_migration_issue(issue))
        }
        local_adoption_metadata_reply(
          true,
          settings.account_id,
          local_host_result(host.configuration()).configuration_cid(),
          host.adoption_cid(),
          child,
        )
      } else if operation == "new-submission" {
        guard host.authorize({
            principal: settings.principal,
            connection: settings.connection,
            resource: "run",
            operation: "submit",
          })
          is Ok(Allow(_)) else {
          stop("LocalSubmissionAuthorizationDenied")
        }
        let scope = local_host_result(
          host.authority_scope_cid(
            settings.principal,
            settings.connection,
            crypto,
          ),
        )
        let epoch = local_host_result(host.epoch_authority())
          .issue_epoch(scope, true, @env.now().to_double())
          .unwrap_or_else(() => stop("LocalSubmissionEpochUnavailable"))
        @local_host.native_client_submission_reference_wire(
          @local_host.prepare_native_client_submission_reference(
            epoch,
            required(child, "request-id"),
          ).unwrap_or_else(() => stop("InvalidSubmissionRef")),
        )
      } else {
        local_adoption_metadata_reply(
          operation == "adopt",
          settings.account_id,
          local_host_result(host.configuration()).configuration_cid(),
          host.adoption_cid(),
          child,
        )
      }
    } catch {
      ClientStop(reason) => {
        if cancellation_recovery.val is Some(reference) {
          stop(local_cancellation_unknown(reference) + " reason=" + reason)
        }
        raise ClientStop(reason)
      }
    }
  }
  if host.close() is Err(_) {
    if cancellation_recovery.val is Some(reference) {
      stop(
        local_cancellation_unknown(reference) +
        " reason=LocalHostCleanupPending",
      )
    }
    stop("LocalHostCleanupPending")
  }
  reply
}

///|
fn local_journal_migration_issue(
  issue : @local_host.NativeClientRunJournalIssue,
) -> String {
  match issue {
    TransactionUnknown | Fenced => "LocalJournalMigrationUnknown"
    AuthorizationDenied => "LocalJournalMigrationAuthorizationDenied"
    _ => "LocalJournalMigrationUnavailable"
  }
}

///|
// Observe the original journal only. A missing record cannot authorize a new
// submission, preparation, acquisition or physical start. The epoch Owner
// authenticates the original token, including after its admission expiry.
fn local_submission_lookup(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  input_root : String,
  child : @argparse.Matches,
  capture? : @local_host.NativeLocalJournalCapture? = None,
) -> String raise ClientStop {
  local_submission_lookup_selected(
    host,
    settings,
    crypto,
    () => {
      @local_host.admit_native_client_submission_reference(
        text_file(input_root, required(child, "submission-ref-file"), 4096L),
      ).unwrap_or_else(() => stop("InvalidSubmissionRef"))
    },
    capture~,
  )
}

///|
fn local_request_lookup(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  child : @argparse.Matches,
  capture? : @local_host.NativeLocalJournalCapture? = None,
) -> String raise ClientStop {
  if capture is Some(original) {
    let scope = local_host_result(
      original.authority_scope_cid_in_original_read(
        settings.principal,
        settings.connection,
      ),
    )
    let observed = original
      .lookup_submitted_intent_by_request_id_in_original_read(
        settings.principal,
        settings.connection,
        scope,
        required(child, "request-id"),
        @env.now().to_double(),
      )
      .unwrap_or_else(() => stop("LocalRequestLookupUnavailable"))
      .unwrap_or_else(() => stop("LocalRequestHistoryUnavailable"))
    guard observed is @local_host.Submitted(record) else {
      stop("LocalRequestHistoryUnavailable")
    }
    // The same Owner already checked RunRead and Submit around its one clock
    // and selected row. Keep that admitted row; do not look it up a second time.
    return local_submission_lookup_reply(
      host,
      settings,
      crypto,
      @local_host.native_client_submitted_intent_reference(record),
      scope,
      observed,
      capture~,
    )
  }
  let scope = local_host_result(
    host.authority_scope_cid(settings.principal, settings.connection, crypto),
  )
  let reply = local_submission_lookup_selected(host, settings, crypto, () => {
    let reference = host
      .lookup_submission_reference_by_request_id(
        crypto,
        settings.principal,
        settings.connection,
        required(child, "request-id"),
        @env.now().to_double(),
      )
      .unwrap_or_else(() => stop("LocalRequestLookupUnavailable"))
    reference.unwrap_or_else(() => stop("LocalRequestHistoryUnavailable"))
  })
  // Independent compatibility entrance retains its original read boundary.
  if !local_run_operation_allowed(host, settings, crypto, scope, "read") {
    stop("LocalRequestReadAuthorizationDenied")
  }
  reply
}

///|
fn local_submission_lookup_selected(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  select_reference : () -> @local_host.NativeClientSubmissionReference raise ClientStop,
  capture? : @local_host.NativeLocalJournalCapture? = None,
) -> String raise ClientStop {
  let authorized = match capture {
    Some(original) =>
      original.authorize_in_original_read({
        principal: settings.principal,
        connection: settings.connection,
        resource: "run",
        operation: "submit",
      })
    None =>
      host.authorize({
        principal: settings.principal,
        connection: settings.connection,
        resource: "run",
        operation: "submit",
      })
  }
  guard authorized is Ok(Allow(_)) else {
    stop("LocalSubmissionAuthorizationDenied")
  }
  let reference = select_reference()
  let scope = local_host_result(
    match capture {
      Some(original) =>
        original.authority_scope_cid_in_original_read(
          settings.principal,
          settings.connection,
        )
      None =>
        host.authority_scope_cid(
          settings.principal,
          settings.connection,
          crypto,
        )
    },
  )
  let observed = match capture {
    Some(original) =>
      original
      .lookup_submitted_intent_in_original_read(
        settings.principal,
        settings.connection,
        scope,
        reference,
        @env.now().to_double(),
      )
      .unwrap_or_else(() => stop("LocalSubmissionLookupUnavailable"))
    None => {
      let journal = local_host_result(host.run_journal())
      let epoch = local_host_result(host.epoch_authority())
      let observed = journal
        .lookup_submitted_intent(
          epoch,
          reference,
          scope,
          true,
          @env.now().to_double(),
        )
        .unwrap_or_else(() => stop("LocalSubmissionLookupUnavailable"))
      guard host.authorize({
          principal: settings.principal,
          connection: settings.connection,
          resource: "run",
          operation: "submit",
        })
        is Ok(Allow(_)) else {
        stop("LocalSubmissionAuthorizationDenied")
      }
      observed
    }
  }
  local_submission_lookup_reply(
    host,
    settings,
    crypto,
    reference,
    scope,
    observed,
    capture~,
  )
}

///|
// Projection of the same checked original. It creates no preparation or Run;
// a retained Run joins only its original Journal record, never current files.
fn local_submission_lookup_reply(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  reference : @local_host.NativeClientSubmissionReference,
  scope : String,
  observed : @local_host.NativeClientSubmittedIntentLookup,
  capture? : @local_host.NativeLocalJournalCapture? = None,
) -> String raise ClientStop {
  let reference_json = @json.parse(
    @local_host.native_client_submission_reference_wire(reference),
  ) catch {
    _ => stop("InvalidSubmissionRef")
  }
  let fields : Map[String, Json] = Map([
    ("kind", Json::string("local_submission_lookup")),
    ("submissionRef", reference_json),
    (
      "requestId",
      Json::string(@local_host.native_client_submission_request_id(reference)),
    ),
  ])
  match observed {
    UnresolvedSubmissionHistory =>
      fields.set("history", Json::string("unresolved"))
    Submitted(record) => {
      fields.set("history", Json::string("retained"))
      fields.set(
        "intentCid",
        Json::string(
          @run_host.client_submitted_intent_cid(
            @local_host.native_client_submitted_intent(record),
          ),
        ),
      )
      fields.set(
        "revision",
        Json::string(
          @local_host.native_client_submitted_intent_revision(record).to_string(),
        ),
      )
      match @local_host.native_client_submitted_run_admission(record) {
        None =>
          match
            @local_host.native_client_submitted_preparation_problem(record) {
            None => fields.set("phase", Json::string("preparing"))
            Some((code, classification)) => {
              fields.set("phase", Json::string("preparation_failed"))
              fields.set(
                "problem",
                Json::object(
                  Map::from_array([
                    ("code", Json::string(code)),
                    ("classification", Json::string(classification)),
                  ]),
                ),
              )
            }
          }
        Some(admission) => {
          // Resolve the original durable Run rather than rebuilding a reference
          // from current settings or treating admission revision as control.
          let run = match capture {
            Some(original) =>
              original
              .lookup_submitted_run_in_original_read(
                settings.principal,
                settings.connection,
                scope,
                admission,
              )
              .unwrap_or_else(() => stop("LocalOriginalRunUnavailable"))
            None => {
              let journal = local_host_result(host.run_journal())
              let (_, run) = local_resolve_admitted_run(
                journal,
                admission,
                scope,
                () => local_submit_allowed(host, settings, crypto, scope),
              )
              if !local_submit_allowed(host, settings, crypto, scope) {
                stop("LocalSubmissionAuthorizationDenied")
              }
              run
            }
          }
          let definition = @local_host.native_client_run_definition(run)
          fields.set("ref", local_original_run_reference(definition, scope))
          fields.set(
            "controlRevision",
            Json::string(
              @local_host.native_client_run_record_revision(run).to_string(),
            ),
          )
          fields.set("phase", Json::string("ready"))
          fields.set(
            "runDefinitionCid",
            Json::string(
              @local_host.native_client_submitted_run_definition_cid(admission),
            ),
          )
          fields.set(
            "admittedRevision",
            Json::string(
              @local_host.native_client_submitted_run_admission_revision(
                admission,
              ).to_string(),
            ),
          )
        }
      }
    }
  }
  encode_request_json(Json::object(fields), 4096)
}

///|
// A common Run reference is projected only from the already-admitted original
// definition and currently verified authority. It grants no attach, dispatch,
// delivery or cancellation; each operation still uses its existing Owner.
fn local_original_run_reference(
  definition : @publication.PublicationContract,
  scope : String,
) -> Json raise ClientStop {
  // The definition already owns its admitted immutable fields. Projection
  // does not parse its wire again or obtain another current authorization.
  let run_namespace = @publication.publication_contract_run_definition_scope(
    definition,
  ).unwrap_or_else(() => stop("LocalOriginalRunUnavailable"))
  let reference = Json::object(
    Map([
      ("namespaceId", Json::string(run_namespace)),
      ("authorityScopeCid", Json::string(scope)),
      (
        "runDefinitionCid",
        Json::string(@publication.publication_contract_identity(definition)),
      ),
    ]),
  )
  if !wire_run_ref_shape(reference) {
    stop("LocalRunReferenceInvalid")
  }
  reference
}

///|
// Reply presentation only. The caller must obtain all fields through its same
// current adopted Host/capture; these strings cannot issue authority or a Run.
fn local_adoption_metadata_reply(
  adopted : Bool,
  account_id : String,
  configuration_cid : String,
  adoption_cid : String,
  child : @argparse.Matches,
) -> String raise ClientStop {
  if child.flags.get("json").unwrap_or(false) {
    encode_request_json(
      Json::object(
        Map([
          (
            "kind",
            Json::string(
              if adopted {
                "local_host_adopted"
              } else {
                "local_host_connected"
              },
            ),
          ),
          ("mode", Json::string("local")),
          ("accountId", Json::string(account_id)),
          ("accountConfigurationCid", Json::string(configuration_cid)),
          ("adoptionCid", Json::string(adoption_cid)),
        ]),
      ),
      4096,
    )
  } else {
    "Local Host " +
    (if adopted { "adopted" } else { "connected" }) +
    "; no Run has been admitted.\nAccount: " +
    account_id +
    "\nAdoption: " +
    adoption_cid
  }
}
