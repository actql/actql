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
    "journal_snapshot_bytes",
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
  }
  if settings.principal.length() > 512 || settings.connection.length() > 512 {
    stop("InvalidLocalHostConfiguration")
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
) -> String raise ClientStop {
  let root = required(matches, "config-root")
  let name = required(matches, "config-file")
  // Refuse an untrusted discovery root before loading configuration-selected
  // physical libraries. The adoption Owner rechecks all original generations.
  let selected_root = @local_filesystem.open_private_root(root).unwrap_or_else(() => {
    stop("LocalConfigurationRootUntrusted")
  })
  let root_ownership = selected_root
    .private_ownership()
    .unwrap_or_else(() => stop("LocalConfigurationRootUntrusted"))
  let configuration = text_file(root, name, 65536L)
  let (environment_file, evidence_cid) = local_configuration(configuration)
  let settings = local_host_settings(configuration)
  let environment = text_file(root, environment_file, 65536L)
  guard @run_host.admit_client_check_environment(
      environment,
      evidence_cid,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    )
    is Some(_) else {
    stop("InvalidLocalCheckEnvironment")
  }
  guard selected_root.private_ownership() is Ok(current) &&
    current == root_ownership else {
    stop("LocalConfigurationRootUntrusted")
  }
  let crypto = @local_crypto.load_library(settings.signature_library).unwrap_or_else(() => {
      stop("NativeLocalSignatureUnavailable")
    },
  )
  let sqlite = @local_sqlite.load_library(settings.sqlite_library).unwrap_or_else(() => {
      stop("NativeLocalJournalUnavailable")
    },
  )
  let session = local_host_result(
    @local_host.begin_native_local_host_adoption(
      settings.state_parent,
      settings.state_name,
      root,
      settings.account_file,
      settings.account_id,
      crypto,
      configuration_files=[name, environment_file],
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
  let host = match
    session.open_journal(
      sqlite,
      crypto,
      settings.ttl_ms,
      settings.record_limit,
      settings.snapshot_bytes,
    ) {
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
  let reply = try {
    if operation == "new-submission" {
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
      let cid = local_host_result(host.configuration()).configuration_cid()
      let adopted = operation == "adopt"
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
              ("accountId", Json::string(settings.account_id)),
              ("accountConfigurationCid", Json::string(cid)),
              ("adoptionCid", Json::string(host.adoption_cid())),
            ]),
          ),
          4096,
        )
      } else {
        "Local Host " +
        (if adopted { "adopted" } else { "connected" }) +
        "; no Run has been admitted.\nAccount: " +
        settings.account_id +
        "\nAdoption: " +
        host.adoption_cid()
      }
    }
  } catch {
    issue => {
      if host.close() is Err(_) {
        stop("LocalHostCleanupPending")
      }
      raise issue
    }
  }
  if host.close() is Err(_) {
    stop("LocalHostCleanupPending")
  }
  reply
}
