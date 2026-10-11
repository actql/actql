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
    "journal_snapshot_bytes", "installation_files",
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
    guard @decode.elements(files) is Ok(files) && files.length() <= 6 else {
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
    if operation == "lookup-submission" {
      local_submission_lookup(host, settings, crypto, root, child)
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
) -> String raise ClientStop {
  guard host.authorize({
      principal: settings.principal,
      connection: settings.connection,
      resource: "run",
      operation: "submit",
    })
    is Ok(Allow(_)) else {
    stop("LocalSubmissionAuthorizationDenied")
  }
  let reference = @local_host.admit_native_client_submission_reference(
    text_file(input_root, required(child, "submission-ref-file"), 4096L),
  ).unwrap_or_else(() => stop("InvalidSubmissionRef"))
  let scope = local_host_result(
    host.authority_scope_cid(settings.principal, settings.connection, crypto),
  )
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
  // Recheck the same adopted account/configuration after the durable clock and
  // journal read. No saved reference is a substitute for current authority.
  guard host.authorize({
      principal: settings.principal,
      connection: settings.connection,
      resource: "run",
      operation: "submit",
    })
    is Ok(Allow(_)) else {
    stop("LocalSubmissionAuthorizationDenied")
  }
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
        None => fields.set("phase", Json::string("preparing"))
        Some(admission) => {
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
