// The outbound-only resident Site. `run` is the control process: it polls
// the configured Cloud, admits and accepts dispatches, starts one executor
// holder at a time through the Site executor slot, and reports observations.
// `execute` is that holder: it runs exactly one accepted attempt. Every
// decision is made by the common owners; this command only wires them.

///|
priv suberror CommandStop {
  CommandStop(String)
}

///|
fn[T] stop(message : String) -> T raise CommandStop {
  raise CommandStop(message)
}

///|
fn required(
  matches : @argparse.Matches,
  name : String,
) -> String raise CommandStop {
  match matches.values.get(name) {
    Some([value]) if !value.is_empty() => value
    _ => stop("missing or repeated option --" + name)
  }
}

///|
fn optional(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some([value]) if !value.is_empty() => Some(value)
    _ => None
  }
}

///|
fn required_int(
  matches : @argparse.Matches,
  name : String,
) -> Int raise CommandStop {
  let parsed : Int = @string.from_str(required(matches, name)) catch {
    _ => stop("invalid integer option --" + name)
  }
  parsed
}

///|
fn required_int64(
  matches : @argparse.Matches,
  name : String,
) -> Int64 raise CommandStop {
  let parsed : Int64 = @string.from_str(required(matches, name)) catch {
    _ => stop("invalid integer option --" + name)
  }
  parsed
}

///|
fn load_text(
  root : String,
  name : String,
  max_bytes : Int64,
) -> String raise CommandStop {
  match
    @bounded_files.read_bounded_text_file_with_custody(root, name, max_bytes) {
    Ok(value) => value
    Err(original) => {
      // Keep the failed original, never repeat the read. Only its checked
      // cleanup can precede unwinding this frame and its initial Read.
      while original.retry_cleanup() is Err(_) {
        resident_control_diagnostic_ffi(5)
        wait_resident_initial_cleanup()
      }
      stop("failed to read " + name)
    }
  }
}

///|
/// A local operator configures the physical Source. No Program, Run
/// materials or Cloud dispatch can supply a path, table or library here.
fn source_configuration(
  matches : @argparse.Matches,
  engine_root : String,
  max_file_bytes : Int64,
) -> @resident_host.ResidentSourceConfiguration? raise CommandStop {
  let names = [
    "source-ref", "source-contract-cid", "source-database", "source-schema", "source-table",
    "duckdb-library",
  ]
  if names.all(name => optional(matches, name) is None) {
    return None
  }
  // A partial physical mapping must fail closed before any database open.
  for name in names {
    required(matches, name) |> ignore
  }
  let library = match
    @duckdb.load_library(required(matches, "duckdb-library")) {
    Ok(value) => value
    Err(_) => stop("failed to load configured DuckDB library")
  }
  Some({
    retained_output_root: optional(matches, "retained-input-root"),
    source_ref: required(matches, "source-ref"),
    source_contract_cid: required(matches, "source-contract-cid"),
    library,
    database_path: required(matches, "source-database"),
    memory_bytes: required_int64(matches, "budget-execution-bytes"),
    database_schema: required(matches, "source-schema"),
    table: required(matches, "source-table"),
    query_contract_body: load_text(
      engine_root, "query-contract.json", max_file_bytes,
    ),
    evidence_contract_body: load_text(
      engine_root, "query-evidence-contract.json", max_file_bytes,
    ),
    two_receipt_contract_body: load_text(
      engine_root, "query-two-receipt-contract.json", max_file_bytes,
    ),
    fragment_contract_body: load_text(
      engine_root, "fragment.json", max_file_bytes,
    ),
    ledger: {
      planning_work: 100000,
      attempts: 1,
      holdings: 1,
      transfer_bytes: required_int64(matches, "max-output-bytes"),
      retained_bytes: required_int64(matches, "budget-retained-bytes"),
      execution_bytes: required_int64(matches, "budget-execution-bytes"),
    },
  })
}

///|
/// The normal path always reads the current system clock. The optional root
/// is an acceptance-test clock, owned by the local test (never dispatch data).
/// Missing/invalid clock bytes fail the existing lifetime check closed.
fn start_timestamp(matches : @argparse.Matches) -> String {
  match optional(matches, "test-clock-root") {
    Some(root) =>
      match @bounded_files.read_bounded_text_file(root, "clock.txt", 64L) {
        Ok(value) => value
        Err(_) => ""
      }
    None =>
      @resident.resident_utc_timestamp(@env.now().reinterpret_as_int64()).unwrap_or(
        "",
      )
  }
}

///|
/// One line of machine-readable progress on standard output.
fn report(kind : String, fields : Array[(String, String)]) -> Unit {
  let text = StringBuilder()
  text.write_string("{\"kind\":\"" + kind + "\"")
  for field in fields {
    text.write_string(",\"" + field.0 + "\":\"" + field.1 + "\"")
  }
  text.write_string("}")
  ignore(@slot.native_write_progress_line(text.to_string()))
}

///|
fn refusal_code(refusal : @resident.ResidentDispatchRefusal) -> String {
  match refusal {
    ForeignCoordinator => "foreign-coordinator"
    ForeignSite => "foreign-site"
    StaleGeneration => "stale-generation"
    ForeignRuntime => "foreign-runtime"
    ForeignConnector => "foreign-connector"
    ForeignGrant => "foreign-grant"
    ForeignIssuer => "foreign-issuer"
    UnsupportedBudget => "unsupported-budget"
    MaterialsMissing => "materials-missing"
    MaterialsRejected(_) => "materials-rejected"
    TaskMaterialsRejected(_) => "task-materials-rejected"
    ForeignSource => "foreign-source"
    UnsupportedTask => "unsupported-task"
    NotCurrent => "not-current"
    QueueFull => "queue-full"
  }
}

///|
/// Fixed diagnostic stages only: evidence names, Program text and nested
/// error payloads must not enter maintenance progress records.
fn saved_output_materials_stage(
  issue : @host.ClientTaskRunMaterialsIssue,
) -> String {
  match issue {
    Input(MaterialsMalformed) => "input-malformed"
    Input(MaterialsEnvironment) => "input-environment"
    Input(MaterialsParameters) => "input-parameters"
    Input(MaterialsProgram(_)) => "input-program"
    Input(MaterialsCompilation(_)) => "input-compilation"
    Input(MaterialsEvidence(_)) => "input-evidence"
    Input(MaterialsAdmission(_)) => "input-admission"
    Input(MaterialsDefinition(_)) => "input-definition"
    Input(MaterialsRunMismatch) => "input-run-mismatch"
    Input(MaterialsBinding(_)) => "input-binding"
    Compilation(_) => "compilation"
    Admission(_) => "admission"
    Definition(_) => "definition"
    RunMismatch => "run-mismatch"
    Binding(_) => "binding"
  }
}

///|
fn client_code(issue : @client.NativeRemoteClientIssue) -> String {
  match issue {
    NotAuthorized => "not-authorized"
    HttpStatus(401) | HttpStatus(403) => "authentication"
    HttpStatus(status) => "http-" + status.to_string()
    Http(@http.CredentialUnavailable) => "credential-unavailable"
    Http(_) => "transport"
    Protocol(_) => "protocol"
    Journal(_) => "journal"
    InvalidUtf8 => "invalid-utf8"
    OutputReportRefused(reason) => "output-report-" + reason
    EffectCheckpointRefused(reason) => "effect-checkpoint-" + reason
    OutcomeUnknownPersistence(_, _) => "outcome-unknown"
    Closed => "closed"
    UnsupportedTarget => "unsupported-target"
  }
}

///|
fn host_code(issue : @resident_host.ResidentHostIssue) -> String {
  match issue {
    Journal(_) => "journal"
    Client(client) => "client-" + client_code(client)
    Protocol(_) => "protocol"
    EnvelopeMissing => "envelope-missing"
    Refused(refusal) => "refused-" + refusal_code(refusal)
    Values(_) => "values"
    Source(issue) => source_code(issue)
    Runtime(@runtime.StartClaimLost(_)) => "start-claim-lost"
    Runtime(@runtime.StartCancelled) => "start-cancelled"
    Runtime(@runtime.ExecutorEntryUnrecorded) => "executor-entry-unrecorded"
    Runtime(issue) => "runtime-" + runtime_code(issue)
  }
}

///|
// Stable categories expose the failing boundary without physical paths,
// credentials, SQL or the configured Source document.
fn source_code(issue : @resident_host.ResidentSourceIssue) -> String {
  match issue {
    UnsupportedSource => "source-unsupported"
    ForeignInput => "source-foreign-input"
    Query(Sequences) => "source-query-sequences"
    Query(MissingStage) => "source-query-stage"
    Query(Requirement(_)) => "source-query-requirement"
    Acquisition(InvalidSource) => "source-acquisition-source"
    Acquisition(InvalidContracts) => "source-acquisition-contracts"
    Acquisition(Preparation) => "source-acquisition-preparation"
    Acquisition(Registration) => "source-acquisition-registration"
    Acquisition(Candidate) => "source-acquisition-candidate"
    Acquisition(Selection) => "source-acquisition-selection"
    Binding(_) => "source-physical-binding"
    Task(_) => "source-task-binding"
    Fragment(_) => "source-task-fragment"
    Inventory(_) => "source-result-inventory"
    Standard(_) => "source-standard-executor"
  }
}

///|
fn runtime_code(issue : @runtime.NativeRemoteRuntimeIssue) -> String {
  match issue {
    Journal(_) => "journal"
    Bundle(_) => "bundle"
    CleanupPending(_) => "cleanup-pending"
    Physical(_) => "physical"
    Protocol(_) => "protocol"
    Closed => "closed"
    _ => "other"
  }
}

///|
fn retained_transfer_code(
  issue : @resident_host.ResidentRetainedTransferIssue,
) -> String {
  match issue {
    Input(@host.ProducerUnavailable) => "producer-unavailable"
    Input(@host.ForeignTransfer) => "foreign-transfer"
    Input(@host.TransferNotCommitted) => "transfer-not-committed"
    Input(@host.StaleSiteGeneration) => "stale-site-generation"
    Input(@host.ForeignAuthority) => "foreign-authority"
    Input(@host.AuthorizationUnavailable) => "authorization-unavailable"
    Input(@host.TransferExpired) => "transfer-expired"
    Input(@host.InvalidBinding) => "invalid-binding"
    Input(@host.Encoding) => "encoding"
    Output(issue) => "output-" + runtime_code(issue)
    Destination(_) => "destination"
    Journal(_) => "transfer-journal"
    ForeignProducer => "foreign-producer"
    UnsupportedRoute => "unsupported-route"
    CapacityUnavailable => "capacity-unavailable"
    CleanupPending => "cleanup-pending"
  }
}

///|
/// The Site environment both processes build the same way from the same
/// options: runtime bundle Store, active runtime, Site and dispatch journal.
priv struct SiteEnvironment {
  bundles : @bundle.NativeRuntimeBundleStore
  // The exact immutable limit supplied to this Store, not a later CLI value.
  runtime_catalog_record_bytes : Int64
  active_runtime : @bundle.NativeActiveRuntimeBinding
  process_hold_id : String
  site : @site.ExecutionSite
  journal : @journal.Journal
  runtime_bundle_cid : String
  sqlite_library : @sqlite.Library
}

///|
/// Ordinary control operations do not open the runtime bundle Store. A
/// stopped-holder recovery opens it only while holding the exclusive slot.
/// The installed runtime and delegated Connector are Site configuration.
priv struct ControlEnvironment {
  sqlite_library : @sqlite.Library
  // This loader captures the SAME command carrier. It supplies a nominal
  // Library only; current Site/Run permission and cleanup remain independent.
  crypto_library : (String) -> Result[@signature.Library, String]
  journal_path : String
  max_record_bytes : Int64
  site_key : String
  site_generation : Int
  runtime_bundle_cid : String
  max_operations : Int
  max_transfers : Int
  max_bytes : Int64
}

///|
fn open_control_environment(
  matches : @argparse.Matches,
  entry : ResidentInitialControl,
) -> ControlEnvironment raise CommandStop {
  let sqlite_path = required(matches, "sqlite-library")
  let journal_path = required(matches, "journal")
  let max_record_bytes = required_int64(matches, "max-record-bytes")
  let site_key = required(matches, "site-key")
  let site_generation = required_int(matches, "site-generation")
  let runtime_bundle_cid = required(matches, "runtime-bundle-cid")
  let max_operations = required_int(matches, "max-operations")
  let max_transfers = required_int(matches, "max-transfers")
  let max_bytes = required_int64(matches, "max-bytes")
  let sqlite_library = match entry.load_sqlite(sqlite_path) {
    Ok(value) => value
    Err(_) => stop("SQLite library load failed")
  }
  {
    sqlite_library,
    crypto_library: path => entry.load_crypto(path),
    journal_path,
    max_record_bytes,
    site_key,
    site_generation,
    runtime_bundle_cid,
    max_operations,
    max_transfers,
    max_bytes,
  }
}

///|
/// Compare the issued process binding with the independently selected original
/// Site. This does not reselect runtime, read Store or prove authorization.
fn holder_site_active_runtime_current(
  site : @site.ExecutionSite,
  generation : Int,
  active : @bundle.NativeActiveRuntimeBinding,
) -> Bool {
  @site.site_binding_current(
    site,
    generation,
    @bundle.native_active_runtime_bundle_cid(active),
  )
}

///|
fn open_site_environment(
  matches : @argparse.Matches,
  process_hold_id : String,
  entry : ResidentInitialControl,
) -> Result[SiteEnvironment, SiteEnvironmentOpenCustody] raise CommandStop {
  let max_file_bytes = required_int64(matches, "max-file-bytes")
  let max_record_bytes = required_int64(matches, "max-record-bytes")
  let max_bytes = required_int64(matches, "max-bytes")
  let site_key = required(matches, "site-key")
  let site_generation = required_int(matches, "site-generation")
  let max_operations = required_int(matches, "max-operations")
  let max_transfers = required_int(matches, "max-transfers")
  let journal_path = required(matches, "journal")
  // The installer already selected this runtime. Preparing the same existing
  // Site before physical reads supplies neither current validation nor funds,
  // Account permission or a new authority derived from Store output.
  let runtime_bundle_cid = required(matches, "runtime-bundle-cid")
  let site = match
    @site.create_site(
      site_key, site_generation, runtime_bundle_cid, max_operations, max_transfers,
      max_bytes, max_bytes,
    ) {
    Some(value) => value
    None =>
      return Err(
        site_environment_open_custody("invalid execution Site", process_hold_id),
      )
  }
  let target = required(matches, "target-triple")
  let component_cid = required(matches, "component-cid")
  let loaded_component_cid = match
    @process_image.current_executable_cid(max_bytes, 1048576) {
    Ok(value) => value
    Err(issue) => {
      // This reader returns only its own fixed diagnostic or strerror text,
      // never the configured path, runtime document or credential material.
      let reason = match issue {
        InvalidLimit => "InvalidLimit"
        Open(message) => "Open(" + message + ")"
        Read(message) => "Read(" + message + ")"
        Close(message) => "Close(" + message + ")"
        CapacityExceeded => "CapacityExceeded"
        EmptyImage => "EmptyImage"
      }
      stop("resident Site executable identity failed: " + reason)
    }
  }
  if loaded_component_cid != component_cid {
    report("setup-failed", [("reason", "executable-identity-mismatch")])
    stop("resident Site executable identity mismatch")
  }
  let sqlite_library = match
    entry.load_sqlite(required(matches, "sqlite-library")) {
    Ok(value) => value
    Err(_) => stop("SQLite library load failed")
  }
  let signature_library = match
    entry.load_crypto(required(matches, "crypto-library")) {
    Ok(value) => value
    Err(_) => stop("signature library load failed")
  }
  let public_key = load_text(
    required(matches, "bundle-public-key-root"),
    required(matches, "bundle-public-key-file"),
    max_file_bytes,
  )
  let bundles = match
    @bundle.open_runtime_bundle_store_with_custody(
      sqlite_library,
      signature_library,
      required(matches, "runtime-root"),
      [
        {
          issuer_authority: required(matches, "bundle-issuer"),
          key_id: required(matches, "bundle-key-id"),
          public_key_pem: public_key,
        },
      ],
      target,
      max_bytes,
      64,
      1024,
      max_record_bytes,
    ) {
    Ok(value) => value
    Err(RefusedBeforeAcquisition(issue)) =>
      return Err(
        site_environment_open_custody(
          "runtime bundle Store open refused: " + bundle_issue_code(issue),
          process_hold_id,
        ),
      )
    Err(CleanupRequired(original)) =>
      return Err(
        site_environment_open_custody(
          "runtime bundle Store open failed: " +
          bundle_issue_code(original.issue()),
          process_hold_id,
          failed_bundle=Some(original),
        ),
      )
  }
  let active = match bundles.active() {
    Ok(Some(value)) => value
    _ =>
      return Err(
        site_environment_open_custody(
          "active runtime bundle is missing",
          process_hold_id,
          bundles=Some(bundles),
        ),
      )
  }
  // Reject a foreign active selection before claiming a process holding.
  // The Store has been read, so this is not an all-I/O-zero refusal.
  if !@site.site_binding_current(
      site,
      site_generation,
      active.runtime_bundle_cid,
    ) {
    return Err(
      site_environment_open_custody(
        "active runtime differs from the original Site selection",
        process_hold_id,
        bundles=Some(bundles),
      ),
    )
  }
  let active_runtime = match
    bundles.acquire_active_component_with_custody(
      loaded_component_cid, target, process_hold_id,
    ) {
    Ok(value) => value
    Err(RefusedBeforeHolding(_)) =>
      return Err(
        site_environment_open_custody(
          "active runtime component verification refused",
          process_hold_id,
          bundles=Some(bundles),
        ),
      )
    Err(HoldingUnconfirmed(_)) =>
      // Retain may have committed before its response was lost. Missing
      // holding is not a release ACK for this original attempt.
      return Err(
        site_environment_open_custody(
          "active runtime component verification failed",
          process_hold_id,
          bundles=Some(bundles),
          release_required=true,
        ),
      )
  }
  // Acquisition may have re-read a different active catalog generation. The
  // exact nominal binding must still belong to the original configured Site.
  if !holder_site_active_runtime_current(site, site_generation, active_runtime) {
    return Err(
      site_environment_open_custody(
        "installed runtime differs from the original Site selection",
        process_hold_id,
        bundles=Some(bundles),
        release_required=true,
      ),
    )
  }
  let control = match
    @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1") {
    Ok(value) => value
    Err(_) =>
      return Err(
        site_environment_open_custody(
          "invalid dispatch journal binding",
          process_hold_id,
          bundles=Some(bundles),
          release_required=true,
        ),
      )
  }
  let journal = match
    @journal.open_journal_with_custody(
      sqlite_library, journal_path, max_record_bytes, control,
    ) {
    Ok(value) => value
    Err(RefusedBeforeAcquisition(_)) =>
      return Err(
        site_environment_open_custody(
          "dispatch journal open refused",
          process_hold_id,
          bundles=Some(bundles),
          release_required=true,
        ),
      )
    Err(CleanupRequired(original)) =>
      return Err(
        site_environment_open_custody(
          "dispatch journal open failed",
          process_hold_id,
          bundles=Some(bundles),
          release_required=true,
          failed_journal=Some(original),
        ),
      )
  }
  Ok({
    bundles,
    runtime_catalog_record_bytes: max_record_bytes,
    active_runtime,
    process_hold_id,
    site,
    journal,
    runtime_bundle_cid: active.runtime_bundle_cid,
    sqlite_library,
  })
}

///|
/// A fresh view of the shared dispatch journal. The holder advances records
/// in its own process, so the control process reads the durable record anew
/// for every operation instead of keeping an in-memory copy.
fn fresh_journal(environment : ControlEnvironment) -> @journal.Journal? {
  let retained : Ref[ControlReplayJournalCustody?] = Ref(None)
  match open_control_replay_journal(environment, retained) {
    Some(original) => {
      // Transfer the SAME ready handle to the existing caller. It still owns
      // its checked close; dropping this temporary reference is not an ACK.
      retained.val = None
      Some(original)
    }
    None => {
      // A failed constructor can own a real database/root/reader. Keep its
      // actual existing partial until cleanup ACK, before returning refusal
      // or allowing the outer Library/Read/arena to retire.
      while !retry_control_replay_journal_cleanup(retained) {
        resident_control_diagnostic_ffi(5)
        wait_resident_initial_cleanup()
      }
      None
    }
  }
}

///|
fn bundle_issue_code(issue : @bundle.NativeRuntimeBundleStoreIssue) -> String {
  match issue {
    UnsupportedTarget => "unsupported-target"
    Closed => "closed"
    InvalidConfiguration => "invalid-configuration"
    AdmissionRejected => "admission-rejected"
    MissingBundle => "missing-bundle"
    ExistingBundle => "existing-bundle"
    BundleLimit => "bundle-limit"
    CapacityExceeded => "capacity-exceeded"
    HoldCollision => "hold-collision"
    StateCollision => "state-collision"
    UnsupportedCatalog => "unsupported-catalog"
    ComponentMismatch => "component-mismatch"
    RecoveryRequired => "recovery-required"
    CleanupPending => "cleanup-pending"
    Bundle(_) => "bundle"
    Signature(_) => "signature"
    Filesystem(RootOpen(detail)) => "filesystem-root: " + detail
    Filesystem(Lock(detail)) => "filesystem-lock: " + detail
    Filesystem(_) => "filesystem"
    Database(_) => "database"
  }
}

///|
fn run_admission(
  matches : @argparse.Matches,
) -> @resident_host.ResidentRunAdmission raise CommandStop {
  let manifests = match
    @host.admit_client_compilation_manifests(
      @environment.compiler_grammar_manifest_wire(),
      @environment.compiler_barrier_contract_manifest_wire(),
      100000,
      10000,
      100,
    ) {
    Ok(value) => value
    Err(_) => stop("compiler manifests admission failed")
  }
  {
    source: match
      (
        optional(matches, "source-ref"),
        optional(matches, "source-contract-cid"),
      ) {
      (Some(source_ref), Some(source_contract_cid)) =>
        Some((source_ref, source_contract_cid))
      (None, None) => None
      _ => stop("incomplete Source admission configuration")
    },
    // Both Values and read-only Source tasks use the checked relation profile.
    expressions: { text_time: false, veca: false, },
    operations: {
      rela: true,
      sga: false,
      tea: false,
      calendar: false,
      text_rank: false,
    },
    manifests,
    limits: {
      preparation: @host.client_standard_program_preparation_limits(),
      sequence: {
        max_steps: 64,
        max_rows: 10000,
        max_cells: 100000,
        max_bindings: 256,
        max_name_bytes: 10000,
        expressions: {
          max_nodes: 10000,
          max_work: 100000,
          max_depth: 64,
          max_literal_nodes: 10000,
          max_literal_text_bytes: 100000,
        },
      },
      max_sequence_steps: 64,
      max_sequence_work: 1024,
      max_evidence_bytes: 100000,
      max_evidence_nodes: 10000,
      max_evidence_depth: 100,
    },
  }
}

///|
fn delegation(
  matches : @argparse.Matches,
  budget : @remote.RemoteDispatchBudget,
) -> @resident.ResidentSiteDelegation raise CommandStop {
  {
    coordinator_authority: required(matches, "coordinator-authority"),
    site_key: required(matches, "site-key"),
    runtime_bundle_cid: required(matches, "runtime-bundle-cid"),
    connector_registration: required(matches, "connector-registration"),
    connector_revision: required(matches, "connector-revision"),
    strategy_revision: required(matches, "strategy-revision"),
    grant_cid: required(matches, "operation-capability-cid"),
    evidence_issuer_capability_cid: required(matches, "issuer-capability-cid"),
    budget_cids: [@remote.remote_dispatch_budget_cid(budget)],
  }
}

///|
/// A trusted operator explicitly delegates internal movement. Do not reuse
/// the execution grant or evidence issuer as another grant role.
fn retained_input_delegation(
  matches : @argparse.Matches,
) -> @resident.ResidentRetainedInputDelegation? raise CommandStop {
  match
    (
      optional(matches, "retained-source-grant-cid"),
      optional(matches, "retained-destination-grant-cid"),
      optional(matches, "retained-route-capability-cid"),
    ) {
    (None, None, None) => None
    (
      Some(source_grant_cid),
      Some(destination_grant_cid),
      Some(route_capability_cid),
    ) =>
      Some({
        dispatch: delegation(matches, budget(matches)),
        source_grant_cid,
        destination_grant_cid,
        route_capability_cid,
      })
    _ => stop("incomplete internal Transfer delegation")
  }
}

///|
fn budget(
  matches : @argparse.Matches,
) -> @remote.RemoteDispatchBudget raise CommandStop {
  match
    @remote.prepare_remote_dispatch_budget(
      required_int64(matches, "budget-retained-bytes"),
      required_int64(matches, "budget-execution-bytes"),
    ) {
    Ok(value) => value
    Err(_) => stop("invalid dispatch budget")
  }
}

///|
fn control_client(
  matches : @argparse.Matches,
  entry : ResidentInitialControl,
) -> @http.Client raise CommandStop {
  let library_path = required(matches, "http-library")
  let authentication : @http.NativeHttpAuthentication = match
    (
      optional(matches, "control-cert"),
      optional(matches, "control-key"),
      optional(matches, "control-bearer-file"),
    ) {
    (Some(cert), Some(key), Some(bearer)) =>
      MutualTlsAndBearer(cert, key, bearer)
    (Some(cert), Some(key), None) => MutualTls(cert, key)
    (None, None, Some(bearer)) => Bearer(bearer)
    _ =>
      stop(
        "control authentication needs a bearer file or a certificate and key",
      )
  }
  let ca = required(matches, "ca")
  let max_response = required_int64(matches, "max-response-bytes")
  let connect_timeout = required_int(matches, "connect-timeout-ms")
  let total_timeout = required_int(matches, "total-timeout-ms")
  let library = match entry.load_http(library_path) {
    Ok(value) => value
    Err(_) => stop("HTTP library load failed")
  }
  // Latch this original constructor before physical entry. Its actual ready
  // or failed child remains on the SAME entry through Library/Read cleanup.
  if entry.http_client_attempted {
    stop("original HTTP Client already attempted")
  }
  entry.http_client_attempted = true
  match
    library.create_authenticated_client_with_custody(
      ca, authentication, max_response, connect_timeout, total_timeout,
    ) {
    Ok(original) => {
      entry.http_client = Some(original)
      original
    }
    Err(RefusedBeforeAcquisition(_)) => stop("HTTP client creation refused")
    Err(CleanupRequired(original)) => {
      entry.failed_http_client = Some(original)
      stop("HTTP client creation cleanup pending")
    }
  }
}

///|
/// The holder's arguments: this process's own options with `execute` in
/// place of `run`, plus the attempt and the holder's claimant name.
fn holder_arguments(
  attempt : String,
  claimant : String,
) -> Array[String] raise CommandStop {
  let own = @env.args()
  let arguments : Array[String] = []
  let mut replaced = false
  for index, value in own {
    if index == 0 {
      continue
    }
    if !replaced && value == "run" {
      arguments.push("execute")
      replaced = true
    } else {
      arguments.push(value)
    }
  }
  if !replaced {
    stop("resident Site was not started with run")
  }
  arguments.push("--attempt")
  arguments.push(attempt)
  arguments.push("--claimant")
  arguments.push(claimant)
  arguments
}

///|
/// Transport routing only. The live holder must still admit the exact checked
/// consumer/input through existing Owners before saving or acknowledging it.
/// Run equality is not execution or cleanup authority.
fn holder_can_receive(
  producer : @remote.DispatchRequest,
  incoming : @remote.DispatchRequest,
) -> Bool {
  let (run, _) = @remote.dispatch_request_task_scope(producer)
  let (other_run, _) = @remote.dispatch_request_task_scope(incoming)
  run == other_run &&
  @remote.dispatch_request_execution_scope(producer) ==
  @remote.dispatch_request_execution_scope(incoming) &&
  @remote.dispatch_request_journal_key(producer)[0] ==
  @remote.dispatch_request_journal_key(incoming)[0]
}

///|
priv struct RunningHolder {
  spawn_custody : @slot.NativeScopedExecutorHolder
  child : @slot.NativeExecutorSlotChild
  channel : @slot.NativeHolderChannel
  attempt : String
  request : @remote.DispatchRequest
  mut next_report_ms : UInt64
  mut reported_revision : Int?
}

///|
/// Acceptance evidence only: while `failures` is positive, a reclaim pass is
/// reported as skipped and the count goes down.
fn skip_reclaim(failures : Ref[Int]) -> Bool {
  if failures.val <= 0 {
    return false
  }
  failures.val -= 1
  report("orphan-reclaim-pending", [("reason", "injected")])
  true
}

///|
priv enum OrphanReclaim {
  /// No output intent is pending; the slot is not held by this process.
  OrphansDone
  /// Some intents stay pending for a later pass; the slot is released.
  OrphansPending
  /// The Store this process opened could not close yet; it keeps the Store
  /// and the slot until it does.
  OrphanStoreOpen(@publication_store.Store)
  /// Ownership cannot be reconstructed safely. Durable evidence and capacity
  /// remain held; no automatic retry can manufacture the missing authority.
  OrphanNeedsReconciliation(@publication_store.Store)
}

///|
/// Reclaim the payloads of output intents left by holders that are gone. It
/// acts only while this process holds the executor slot, which proves that no
/// holder can still write them, and uses the existing publication Store
/// owner. The Store is closed and the slot released before any holder
/// starts. Execution is never resumed or repeated.
fn reclaim_orphaned_outputs(
  settings : ControlOrphanStoreSettings,
  environment : ControlEnvironment,
  slot : @slot.NativeExecutorSlot,
  held : @publication_store.Store?,
  replay_journal : Ref[ControlReplayJournalCustody?],
  failed_store : Ref[@publication_store.NativePublicationStoreOpenFailure?],
  slot_progress : Ref[ControlTerminalClose],
) -> OrphanReclaim {
  let publication_root = settings.root
  let close_held = fn(store : @publication_store.Store) -> OrphanReclaim {
    if !retry_control_replay_journal_cleanup(replay_journal) {
      return OrphanStoreOpen(store)
    }
    match store.close() {
      Ok(_) => {
        retain_control_reclaim_slot_close(slot, slot_progress)
        OrphansPending
      }
      Err(@publication_store.RecoveryRequired) => {
        report("allocation-needs-reconciliation", [
          ("reason", "allocation-ownership-unconfirmed"),
          ("publication_root", publication_root),
          ("journal", environment.journal_path),
        ])
        OrphanNeedsReconciliation(store)
      }
      Err(_) => {
        report("orphan-reclaim-pending", [("reason", "store-close")])
        OrphanStoreOpen(store)
      }
    }
  }
  guard open_control_replay_journal(environment, replay_journal)
    is Some(journal) else {
    report("orphan-reclaim-pending", [("reason", "journal-open")])
    return match held {
      Some(store) => close_held(store)
      None => OrphansPending
    }
  }
  let intents = match journal.pending_output_intents() {
    Ok(value) => value
    Err(_) => {
      close_control_replay_journal(replay_journal)
      report("orphan-reclaim-pending", [("reason", "journal-read")])
      return match held {
        Some(store) => close_held(store)
        None => OrphansPending
      }
    }
  }
  let pending = intents.length()
  if pending == 0 && held is None {
    return if retry_control_replay_journal_cleanup(replay_journal) {
      OrphansDone
    } else {
      OrphansPending
    }
  }
  let store = match held {
    Some(value) => value
    None => {
      match slot.try_acquire() {
        Ok(true) => ()
        Ok(false) => {
          close_control_replay_journal(replay_journal)
          report("orphan-reclaim-pending", [("reason", "slot-busy")])
          return OrphansPending
        }
        Err(_) => {
          close_control_replay_journal(replay_journal)
          report("orphan-reclaim-pending", [("reason", "slot-lock")])
          return OrphansPending
        }
      }
      match open_control_orphan_store(environment, settings, failed_store) {
        Some(value) => value
        None => {
          // The failed Store was constructed after this Journal. Retain both
          // and the Slot until reverse-order cleanup acknowledges originals.
          if failed_store.val is None {
            retain_control_orphan_reader_cleanup(
              replay_journal, slot, slot_progress,
            )
          }
          report("orphan-reclaim-pending", [("reason", "store-open")])
          return OrphansPending
        }
      }
    }
  }
  let remaining = @resident_host.reclaim_resident_output_intents(journal, store)
  if remaining
    is Err(
      @resident_host.OutputPayloadStore(@publication_store.RecoveryRequired)
    ) {
    for intent in intents {
      report("allocation-reconciliation-intent", [
        ("payload_request_cid", intent.0),
      ])
    }
  }
  close_control_replay_journal(replay_journal)
  match remaining {
    Ok(0) => report("orphans-reclaimed", [("intents", pending.to_string())])
    Ok(count) =>
      report("orphan-reclaim-pending", [
        ("reason", "store"),
        ("intents", count.to_string()),
      ])
    Err(issue) =>
      report("orphan-reclaim-pending", [("reason", output_code(issue))])
  }
  match close_held(store) {
    OrphansPending if remaining is Ok(0) => OrphansDone
    other => other
  }
}

///|
/// One physical recovery owner, retained across retryable Store failures.
/// The slot stays held until both Store closure and journal work finish.
priv struct StoppedReleaseRecovery {
  slot : @slot.NativeExecutorSlot
  environment : ControlEnvironment
  bundles : @bundle.NativeRuntimeBundleStore
  journal : @journal.Journal
  request_identity : String
  mut bundle_closed : Bool
  mut transfer_journal : @transfer_journal.Journal?
  input_cleanup_resources : HolderPartialOutputResources
  mut input_cleanup_paths : (String, String?)?
  input_cleanup_step : Ref[Int]
  mut physical_cleanup : (() -> Bool)?
  mut physical_cleanup_done : Bool
  release_failure_hook : StoppedReleaseFailureHook
  mut retained_input : Bool
  mut recorded_source : @publication.RecordedRunPublication?
  mut recorded_consumer : (String, String)?
  mut completed_input_producer : (String, String)?
  mut terminal_close : StoppedRecoveryTerminalClose
}

///|
/// Cleanup never acquires an execution component or a new runtime holding.
/// The saved Site binding and signed installed bundle remain authoritative.
/// A failure is rendered only after the existing lifetime has retired its
/// original partial constructors and inherited Slot with checked ACKs.
fn open_release_recovery(
  matches : @argparse.Matches,
  environment : ControlEnvironment,
  slot : @slot.NativeExecutorSlot,
  identity : String,
) -> StoppedReleaseRecovery raise CommandStop {
  match
    open_release_recovery_with_custody(matches, environment, slot, identity) {
    Ok(owner) => owner
    Err(original) => {
      finish_failed_release_recovery_open(original)
      stop(original.failure)
    }
  }
}

///|
fn close_recovery_bundle(
  owner : StoppedReleaseRecovery,
  failures : Ref[Int],
) -> Bool {
  if owner.bundle_closed {
    return true
  }
  if failures.val > 0 {
    failures.val -= 1
    report("release-recovery-pending", [
      ("reason", "bundle-close"),
      ("request_cid", owner.request_identity),
    ])
    return false
  }
  match owner.bundles.close() {
    Ok(_) => {
      owner.bundle_closed = true
      true
    }
    Err(_) => false
  }
}

///|
/// A release for a settled dispatch whose original holder is gone. The slot
/// fences all holder descendants; durable intents and both exact bundle
/// holdings are checked before the common owner selects a transition.
fn recover_stopped_release(
  matches : @argparse.Matches,
  environment : ControlEnvironment,
  request : @remote.DispatchRequest,
  retained : Ref[StoppedReleaseRecovery?],
  close_failures : Ref[Int],
) -> Bool raise CommandStop {
  let identity = @remote.dispatch_request_identity(request)
  let owner = match retained.val {
    Some(value) => value
    None => {
      let slot = match
        @slot.open_native_executor_slot(required(matches, "executor-slot")) {
        Ok(value) => value
        Err(_) => return false
      }
      match acquire_release_recovery_slot_with_custody(slot, identity) {
        Ok(_) => ()
        Err(original) => {
          finish_failed_release_recovery_open(original)
          return false
        }
      }
      let value = match
        open_release_recovery_with_custody(matches, environment, slot, identity) {
        Ok(owner) => owner
        Err(original) => {
          // Keep all other controller responsibilities on this same stack.
          // Only checked retirement of this failed preparation permits return;
          // it does not confirm the original Run's release or retry execution.
          finish_failed_release_recovery_open(original)
          report("release-recovery-preparation-failed", [
            ("request_cid", identity),
          ])
          return false
        }
      }
      retained.val = Some(value)
      value
    }
  }
  if owner.request_identity != identity {
    return false
  }
  if !(owner.terminal_close is RecoveryTerminalOpen) {
    // The common Owner already selected its terminal cleanup action. Retrying
    // a partial close must not read through its retiring/closed journal.
    return retry_stopped_recovery_terminal_close(owner, retained)
  }
  let record = match owner.journal.require(request) {
    Ok(value) => value
    Err(_) => return false
  }
  let codes = @remote.dispatch_record_state_codes(record)
  let cancelled = match owner.journal.cancellation_requested(request) {
    Ok(value) => value
    Err(_) => return false
  }
  // The saved cancellation selects disposition, never process death alone.
  // Physical stop is independently established by this owner's exclusive slot.
  if (
      codes[0] != 3 &&
      !(cancelled &&
      (
        codes[0] == 1 ||
        codes[0] == 2 ||
        codes[0] == 4 ||
        codes[0] == 5 ||
        codes[0] == 6
      ))
    ) ||
    (codes[2] != 0 && codes[2] != 1 && codes[2] != 2 && codes[2] != 3) {
    return false
  }
  let claimant = match owner.journal.start_claimant(request) {
    Ok(value) => value
    Err(_) => return false
  }
  // Without a saved claim no process holding may be guessed or deleted.
  // Only a cancelled pre-start record may reconcile absence; all bundle
  // holdings must then be independently absent after the exact dispatch hold.
  if claimant is None && !(cancelled && codes[0] == 5) {
    return false
  }
  match owner.journal.pending_output_intents() {
    Ok(values) if values.is_empty() => ()
    _ => return false
  }
  // Apply the existing opt-in release fault to this exact stopped owner too.
  // The exclusive slot, journal and original material custody stay retained;
  // no physical cleanup or terminal transition occurs during the injected wait.
  if stopped_release_failure_attempt(
      owner.release_failure_hook,
      owner.physical_cleanup_done || codes[2] == 2,
    )
    is Some(attempt) {
    report("cleanup-pending", [
      ("step", "release"),
      ("request_cid", identity),
      ("attempt", attempt.to_string()),
    ])
    return false
  }
  if !settle_stopped_holder_custody(matches, owner, request) {
    retire_failed_stopped_holder_input_constructor(owner, retained)
    return false
  }
  if !owner.bundle_closed {
    let holds = ["dispatch:" + identity]
    if claimant is Some(value) {
      let attempt = match @remote.dispatch_request_attempt_identity(request) {
        Ok(value) => value
        Err(_) => return false
      }
      let process_hold = if owner.completed_input_producer is Some(_) &&
        owner.retained_input {
        // The completed-input cleanup Owner already admitted both original
        // occurrences and the exact accepted consumer binding. No current
        // compilation or executable input is needed to discharge this hold.
        Ok(consumer_process_hold_identity(request))
      } else {
        @resident_host.resident_holder_process_hold_identity(
          owner.journal,
          run_admission(matches),
          attempt,
          value,
          recorded_source=owner.recorded_source,
        )
      }
      match process_hold {
        Ok(hold) => holds.push(hold)
        Err(_) => return false
      }
    } else if owner.retained_input {
      // A consumer's pre-start component role is fixed by its exact dispatch,
      // so no missing claimant is guessed to identify that original holding.
      let attempt = match @remote.dispatch_request_attempt_identity(request) {
        Ok(value) => value
        Err(_) => return false
      }
      match
        @resident_host.resident_holder_process_hold_identity(
          owner.journal,
          run_admission(matches),
          attempt,
          "",
        ) {
        Ok(hold) if hold == "consumer:" + identity => holds.push(hold)
        _ => return false
      }
    }
    for hold in holds {
      match owner.bundles.release(hold) {
        Ok(_) => () // Absence of this exact holding is idempotent.
        Err(_) => return false
      }
    }
  }
  if claimant is None && !owner.retained_input && !owner.bundle_closed {
    // A source process role cannot be inferred without a start claimant.
    // A retained consumer instead has its exact admitted dispatch role above;
    // unrelated ancestor holdings remain independently owned during its cleanup.
    match owner.bundles.list() {
      Ok(values) if values.all(value => value.state[2] == "0") => ()
      _ => return false
    }
  }
  if !close_recovery_bundle(owner, close_failures) {
    return false
  }
  // The exclusive slot proves process-local operations/readers/holdings
  // are gone. The caller confirmed Store-owned orphan cleanup; exact
  // persistent output files, original input readers/receivers and exact
  // component holdings have now also been discharged.
  let custody = @remote.create_remote_runtime_custody()
  if cancelled {
    if !@remote.remote_runtime_custody_record_failure(
        custody, true, true, false,
      ) ||
      !@remote.remote_runtime_custody_confirm_stop(custody) {
      return false
    }
  }
  for step_index = 0; step_index < 4; step_index = step_index + 1 {
    let step = match
      @remote.prepare_owned_remote_runtime_cleanup(record, custody) {
      Ok(value) => value
      Err(_) => return false
    }
    match @remote.remote_runtime_step_action_code(step) {
      4 => {
        owner.terminal_close = RecoveryTerminalJournal
        return retry_stopped_recovery_terminal_close(owner, retained)
      }
      1 | 2 => {
        // SettleThenPersist is valid here only because the exact physical
        // stop and reclamation were already confirmed before owner progression.
        let transition = match @remote.remote_runtime_step_transition(step) {
          Ok(value) => value
          Err(_) => return false
        }
        if owner.journal.commit_transition(transition) is Err(_) {
          return false
        }
        if required(matches, "release-recovery-kill-at") == "after-transition" {
          report("release-recovery-killed", [("request_cid", identity)])
          @slot.native_kill_self()
        }
      }
      _ => return false
    }
  }
  false
}

///|
/// The exact dispatch request kept for an accepted attempt, read from a
/// fresh journal view. `failures` is an acceptance test hook: while it is
/// positive, one read is reported as failed.
fn accepted_request(
  environment : ControlEnvironment,
  attempt : String,
  failures : Array[Int],
) -> @remote.DispatchRequest? {
  if failures[0] > 0 {
    failures[0] -= 1
    return None
  }
  guard fresh_journal(environment) is Some(journal) else { return None }
  let envelope = journal.dispatch_envelope(attempt)
  retain_control_replay_journal_close(journal)
  admit_accepted_request_envelope(envelope, attempt)
}

///|
/// Existing wire admission and exact attempt check, shared by controller and
/// the legacy one-shot recovery reader. This grants no start or cleanup ACK.
fn admit_accepted_request_envelope(
  envelope : Result[String?, @journal.NativeRemoteJournalIssue],
  attempt : String,
) -> @remote.DispatchRequest? {
  match envelope {
    Ok(Some(body)) =>
      match @remote.admit_remote_poll_dispatch_json(body) {
        Ok(dispatch) => {
          let request = @remote.remote_poll_dispatch_request(dispatch)
          match @remote.dispatch_request_attempt_identity(request) {
            Ok(identity) if identity == attempt => Some(request)
            _ => None
          }
        }
        Err(_) => None
      }
    _ => None
  }
}

///|
/// Select the original completed producer from the existing saved envelope
/// and checked retained intent. This only joins the existing waiting queue;
/// the holder must acquire and recheck the physical slot before restoration.
/// A status-only receiver query never calls this operation.
fn queue_completed_retained_holder(
  journal : @journal.Journal,
  admission : @resident_host.ResidentRunAdmission,
  delegation : @resident.ResidentSiteDelegation,
  generation : Int,
  queue : @resident.ResidentAcceptedQueue,
  intent : @remote.RemoteRetainedInputIntent,
  at : String,
) -> Bool {
  let request = @remote.remote_retained_input_intent_request(intent)
  if @resident.check_resident_dispatch_delegation(
      delegation, request, generation,
    )
    is Err(_) ||
    !(journal.cancellation_requested(request) is Ok(false)) {
    return false
  }
  // This checks the original Run, checked edge, Source, producer completion
  // and exact intent against the saved journal, without physical acquisition.
  if @resident_host.prepare_resident_retained_producer_context(
      journal, admission, intent, at,
    )
    is Err(_) {
    return false
  }
  let saved = match journal.observation(request) {
    Ok(value) => value
    Err(_) => return false
  }
  guard @journal.recovered_site_dispatch_evidence(saved) is Some(evidence) &&
    @journal.recovered_site_dispatch_subject(saved) is Some(subject) &&
    @journal.recovered_site_dispatch_measurement(saved) is Some(measurement) &&
    @journal.recovered_site_dispatch_file_custody(saved) is Some(_) else {
    return false
  }
  if @remote.restore_remote_runtime_completed_custody(
      @journal.recovered_site_dispatch_record(saved),
      evidence,
      subject,
      measurement,
    )
    is Err(_) {
    return false
  }
  let attempt = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(_) => return false
  }
  // Do not let another queued start hide unaccounted completed custody. The
  // existing queue remains the only dispatch selection owner.
  if queue.length() > 0 && !queue.contains(attempt) {
    return false
  }
  queue.reserve(attempt) is Ok(_)
}

///|
fn replay_output_reports(
  environment : ControlEnvironment,
  retained : Ref[ControlReplayJournalCustody?],
  client : @http.Client,
  url : String,
  next : Ref[UInt64],
  backoff_ms : Int,
  cursor_owner : Ref[String],
  delegation : @resident.ResidentSiteDelegation,
  checkpoint : (String) -> Unit,
) -> Unit {
  // A class-wide pacing hint has constant size. The original journal/cursor
  // owns every report; a deadline never drops or reissues that responsibility.
  if @env.now() < next.val {
    return
  }
  guard open_control_replay_journal(environment, retained) is Some(journal) else {
    return
  }
  let mut cursor = cursor_owner.val
  // One report per pass; rotate the cursor so retries cannot starve poll,
  // release, or another report even when requests outlast the backoff.
  while true {
    match journal.output_report_after(cursor) {
      Ok(Some((key, custody, state))) => {
        cursor = key
        cursor_owner.val = key
        if state is Some(@remote.RemoteOutputReportReply::Accepted) {
          continue
        }
        next.val = @env.now() + backoff_ms.to_uint64()
        let result = @remote.remote_output_report_custody_result(custody)
        if state is Some(@remote.RemoteOutputReportReply::Refused(reason)) {
          report("output-report-attention", [
            ("report_cid", @remote.remote_output_result_identity(result)),
            ("reason", reason),
          ])
          break
        }
        if state is Some(@remote.RemoteOutputReportReply::Retry(reason)) {
          report("output-report-retry", [
            ("report_cid", @remote.remote_output_result_identity(result)),
            ("reason", reason),
          ])
        }
        let request = @remote.remote_output_report_custody_dispatch(custody)
        if @resident.check_resident_dispatch_delegation(
            delegation,
            request,
            environment.site_generation,
          )
          is Err(_) {
          let refusal = @remote.remote_output_report_reply_json(
            result,
            @remote.RemoteOutputReportReply::Refused("scope_mismatch"),
          )
          match refusal {
            Ok(body) =>
              match journal.record_output_report_reply(key, body) {
                Ok(_) =>
                  report("output-report-attention", [
                    (
                      "report_cid",
                      @remote.remote_output_result_identity(result),
                    ),
                    ("reason", "scope_mismatch"),
                  ])
                Err(_) =>
                  report("output-report-recovery-pending", [
                    (
                      "report_cid",
                      @remote.remote_output_result_identity(result),
                    ),
                    ("reason", "scope-mismatch-record"),
                  ])
              }
            Err(_) =>
              report("output-report-recovery-pending", [
                ("report_cid", @remote.remote_output_result_identity(result)),
                ("reason", "scope-mismatch-encode"),
              ])
          }
          break
        }
        match
          @client.acknowledge_retained_output_report(
            journal,
            client,
            url,
            key,
            checkpoint~,
          ) {
          Ok(_) =>
            report("output-delivered", [
              (
                "request_cid",
                @remote.dispatch_request_identity(
                  @remote.remote_output_report_custody_dispatch(custody),
                ),
              ),
              ("report_cid", @remote.remote_output_result_identity(result)),
            ])
          Err(issue) =>
            report("output-result-unreported", [
              ("report_cid", @remote.remote_output_result_identity(result)),
              ("reason", client_code(issue)),
            ])
        }
        break
      }
      Ok(None) => {
        cursor_owner.val = ""
        break
      }
      Err(_) => {
        report("output-report-recovery-pending", [("reason", "journal")])
        break
      }
    }
  }
  if !retry_control_replay_journal_cleanup(retained) {
    report("output-report-recovery-pending", [("reason", "journal-close")])
  }
}

///|
/// One existing journal record per control pass. Cancellation intent is
/// resumed after a lost reply or control-process restart, without a new queue
/// or execution attempt. The current physical recovery owner keeps the slot
/// while any bundle/store close or durable transition is still pending.
fn reconcile_saved_cancellation(
  matches : @argparse.Matches,
  environment : ControlEnvironment,
  retained : Ref[ControlReplayJournalCustody?],
  client : @http.Client,
  url : String,
  cursor : Ref[String],
  next : Ref[UInt64],
  backoff_ms : Int,
  delegation : @resident.ResidentSiteDelegation,
  recovery : Ref[StoppedReleaseRecovery?],
  close_failures : Ref[Int],
) -> Unit raise CommandStop {
  if @env.now() < next.val {
    return
  }
  guard open_control_replay_journal(environment, retained) is Some(journal) else {
    return
  }
  let recovered = journal.recover_after(cursor.val)
  match recovered {
    Ok(Some((key, record))) => {
      cursor.val = key
      let request = @remote.dispatch_record_request(record)
      let pending = journal.cancellation_requested(request)
      let already_released = @remote.remote_runtime_record_released(record)
      // Cleanup the original reader before entering the existing stopped
      // execution recovery. A failed close retains that reader and must not
      // be replaced by a second journal or an inferred cleanup ACK.
      guard retry_control_replay_journal_cleanup(retained) else {
        report("cancel-recovery-pending", [("reason", "original-journal-close")])
        return
      }
      guard pending is Ok(true) else { return }
      let identity = @remote.dispatch_request_identity(request)
      if @resident.check_resident_dispatch_delegation(
          delegation,
          request,
          environment.site_generation,
        )
        is Err(_) {
        report("cancel-recovery-pending", [
          ("request_cid", identity),
          ("reason", "scope-mismatch"),
        ])
        return
      }
      next.val = @env.now() + backoff_ms.to_uint64()
      if !already_released &&
        !recover_stopped_release(
          matches, environment, request, recovery, close_failures,
        ) {
        report("cancel-cleanup-pending", [("request_cid", identity)])
        return
      }
      guard open_control_replay_journal(environment, retained) is Some(current) else {
        return
      }
      match @client.acknowledge_status(current, client, url, request) {
        Ok(_) => report("cancel-reconciled", [("request_cid", identity)])
        Err(issue) =>
          report("cancel-unreported", [
            ("request_cid", identity),
            ("reason", client_code(issue)),
          ])
      }
      if !retry_control_replay_journal_cleanup(retained) {
        report("cancel-recovery-pending", [
          ("reason", "original-report-journal-close"),
        ])
      }
    }
    Ok(None) => {
      cursor.val = ""
      if !retry_control_replay_journal_cleanup(retained) {
        report("cancel-recovery-pending", [("reason", "original-journal-close")])
      }
    }
    Err(_) => {
      if !retry_control_replay_journal_cleanup(retained) {
        report("cancel-recovery-pending", [("reason", "original-journal-close")])
      }
      report("cancel-recovery-pending", [("reason", "journal-read")])
    }
  }
}

///|
fn run_control(
  matches : @argparse.Matches,
  entry : ResidentInitialControl,
) -> Unit raise CommandStop {
  if !@slot.install_native_termination_request() {
    stop("termination handling could not be installed")
  }
  let environment = open_control_environment(matches, entry)
  let slot_path = required(matches, "executor-slot")
  let poll_url = required(matches, "poll-url")
  let observation_url = required(matches, "observation-url")
  let dispatch_budget = budget(matches)
  let site_delegation = delegation(matches, dispatch_budget)
  let admission = run_admission(matches)
  // Only operator configuration is read here; physical acquisition belongs
  // to the exclusive holder after durable acceptance and a protected claim.
  let effect_configuration = if admission.source is Some(_) &&
    retained_input_delegation(matches) is Some(_) {
    let root = required(matches, "engine-root")
    let maximum = required_int64(matches, "max-file-bytes")
    match source_configuration(matches, root, maximum) {
      Some(source) => {
        let registry_body = load_text(root, "registry.json", maximum)
        let values_body = load_text(root, "values.json", maximum)
        match
          @local_values.prepare_installed_sequence_contracts(
            registry_body,
            values_body,
            Some(source.fragment_contract_body),
            None,
          ) {
          Ok(installed_contracts) =>
            retained_consumer_configuration(
              source,
              installed_contracts,
              values_body,
              required_int64(matches, "retained-consumer-engine-bytes"),
            )
          Err(_) => None
        }
      }
      None => None
    }
  } else {
    None
  }
  let generation = required_int(matches, "site-generation")
  let custody_configuration = bundle_custody_configuration(
    matches, site_delegation, generation,
  )
  let mut pending_custody : PendingBundleCustody? = None
  let queue = match
    @resident.ResidentAcceptedQueue::new(
      required_int(matches, "queue-capacity"),
    ) {
    Some(value) => value
    None => stop("invalid accepted queue capacity")
  }
  let executable = match @slot.native_current_executable() {
    Ok(value) => value
    Err(_) => stop("resident Site executable path is unavailable")
  }
  let max_polls = required_int(matches, "max-polls")
  let idle_wait_ms = required_int(matches, "idle-wait-ms")
  let min_backoff_ms = required_int(matches, "min-backoff-ms")
  let max_backoff_ms = required_int(matches, "max-backoff-ms")
  let shutdown_wait_ms = required_int(matches, "shutdown-wait-ms")
  let envelope_read_failures = [
    required_int(matches, "control-envelope-read-failures"),
  ]
  let recovery : Ref[StoppedReleaseRecovery?] = { val: None, }
  let recovery_close_failures : Ref[Int] = {
    val: required_int(matches, "release-recovery-close-failures"),
  }
  let mut holder : RunningHolder? = None
  let pending_spawn : Ref[@slot.NativeScopedExecutorHolder?] = Ref(None)
  // The original ended executor keeps its existing admission until report,
  // Channel and descendant-stop facts are independently confirmed. No new
  // holder starts while that responsibility is pending.
  let unsettled : Array[EndedHolderResponsibility] = []
  let mut backoff_ms = 0
  let mut next_start_ms : UInt64 = 0
  // Output intents of holders that are gone are looked for at startup and
  // whenever a holder ends. A publication Store this process opened for that
  // stays here, with the slot, until it closes.
  let mut reclaim_due = true
  let mut next_reclaim_ms : UInt64 = 0
  let mut orphan_store : @publication_store.Store? = None
  let mut orphan_reconciliation = false
  // Acceptance evidence only: reclaim passes skipped before the first one.
  let reclaim_failures : Ref[Int] = {
    val: required_int(matches, "control-reclaim-failures"),
  }
  let cancel_cursor : Ref[String] = { val: "", }
  let next_cancel_report : Ref[UInt64] = Ref(0UL)
  let mut polls = 0
  let mut holders = 0
  let replay_journal : Ref[ControlReplayJournalCustody?] = Ref(None)
  let next_output_report : Ref[UInt64] = Ref(0UL)
  let report_cursor : Ref[String] = { val: "", }
  let next_checkpoint_report : Ref[UInt64] = Ref(0UL)
  let checkpoint_report_cursor : Ref[String] = { val: "", }
  let report_kill_at = required(matches, "control-report-kill-at")
  // Extract fallible operator options before acquiring the HTTP/Slot pair.
  let orphan_settings : ControlOrphanStoreSettings = {
    root: required(matches, "publication-root"),
    authority_cid: required(matches, "publication-authority-cid"),
    capacity_bytes: required_int64(matches, "publication-capacity-bytes"),
  }
  let failed_orphan_store : Ref[
    @publication_store.NativePublicationStoreOpenFailure?,
  ] = Ref(None)
  let report_checkpoint = fn(point : String) {
    if point == report_kill_at {
      report("control-report-killed", [("point", point)])
      @slot.native_kill_self()
    }
  }
  // Complete fallible configuration, bounded input preparation and the HTTP
  // constructor before opening the slot. The entry retains every ready or
  // failed Library/Client if a constructor refuses; no slot can be orphaned
  // by those earlier CommandStop paths.
  let client = control_client(matches, entry)
  let mut slot = match @slot.open_native_executor_slot(slot_path) {
    Ok(value) => value
    Err(_) => stop("executor slot open failed")
  }
  let mut slot_progress = Ref(ControlSlotPending)
  while !@slot.native_termination_requested() {
    // The original preparation is retained before fallible channel/spawn work.
    // Partial close uncertainty cannot be replaced by another spawn attempt.
    if pending_spawn.val is Some(original) {
      if !original.cleanup() {
        report("holder-spawn-cleanup-pending", [])
        @slot.native_wait_milliseconds(max_backoff_ms)
        continue
      }
      pending_spawn.val = None
    }
    // Retiring owns the original Store/Slot. Neither another constructor nor
    // a poll/start/reclaim may bypass it. The existing loop supplies pacing.
    match pending_custody {
      Some(Retiring(original)) => {
        pending_custody = advance_control_bundle_custody_cleanup(original)
        @slot.native_wait_milliseconds(max_backoff_ms)
        continue
      }
      Some(Unconfirmed(_)) => {
        // No Store action is retried from a generic failure. Preserve the
        // original duty for terminal handoff/Owner reconciliation.
        @slot.native_wait_milliseconds(max_backoff_ms)
        continue
      }
      _ => ()
    }
    // A failed Store was acquired after its original Journal and Slot.
    if !retry_control_orphan_store_cleanup(
        failed_orphan_store, replay_journal, slot, slot_progress,
      ) {
      report("orphan-store-cleanup-pending", [])
      @slot.native_wait_milliseconds(idle_wait_ms)
      continue
    }
    // A failed replay constructor/close owns this same original handle. Do not
    // poll, dispatch, or open another journal until its checked cleanup ACK.
    if !retry_control_replay_journal_cleanup(replay_journal) {
      report("replay-journal-cleanup-pending", [])
      @slot.native_wait_milliseconds(idle_wait_ms)
      continue
    }
    replay_output_reports(
      environment, replay_journal, client, observation_url, next_output_report, max_backoff_ms,
      report_cursor, site_delegation, report_checkpoint,
    )
    replay_effect_checkpoint_reports(
      environment, replay_journal, client, observation_url, next_checkpoint_report,
      max_backoff_ms, checkpoint_report_cursor, site_delegation, report_checkpoint,
    )
    if replay_journal.val is Some(_) {
      // The original remains reachable through terminal handoff if stopped.
      @slot.native_wait_milliseconds(idle_wait_ms)
      continue
    }
    // A finished holder's durable record is reported before new work.
    match holder {
      Some(current) =>
        match current.child.wait(false) {
          Ok(Some(_)) => {
            holder = None
            // Physical child exit is separate from the Coordinator's ACK of
            // its durable status (which may be unavailable or already read).
            report("holder-exited", [("attempt", current.attempt)])
            // A holder that died may have left output intents behind.
            reclaim_due = true
            // Do not classify an unreadable journal as safe to start again,
            // or discard physical custody merely because a status is reported.
            unsettled.push(retain_ended_holder(current))
          }
          Ok(None) =>
            if @env.now() >= current.next_report_ms {
              // A live producer keeps its input until the consumer finishes.
              // Report its durable progress without treating child exit,
              // execution settlement, or resource release as equivalent facts.
              current.next_report_ms = @env.now() + max_backoff_ms.to_uint64()
              // Retry existing local Review custody independently of remote
              // Current queries. The holder checks its installed policy and
              // present read authority; the frame supplies no materials,
              // report, approval or execution permission. Reuse the existing
              // progress-report interval instead of an additional retry timer.
              ignore(current.channel.send("effect-review"))
              match open_control_replay_journal(environment, replay_journal) {
                Some(journal) => {
                  match journal.require(current.request) {
                    Ok(record) =>
                      if current.reported_revision !=
                        Some(@remote.dispatch_record_revision(record)) {
                        match
                          @client.acknowledge_status(
                            journal,
                            client,
                            observation_url,
                            current.request,
                          ) {
                          Ok(Some(observed)) =>
                            current.reported_revision = Some(
                              @remote.dispatch_record_revision(observed),
                            )
                          Ok(None) => ()
                          Err(issue) =>
                            report("observation-pending", [
                              ("attempt", current.attempt),
                              ("reason", client_code(issue)),
                            ])
                        }
                      }
                    Err(_) => ()
                  }
                  close_control_replay_journal(replay_journal)
                }
                None =>
                  report("observation-pending", [
                    ("attempt", current.attempt),
                    ("reason", "journal-open"),
                  ])
              }
            }
          Err(_) => ()
        }
      None => ()
    }
    if replay_journal.val is Some(_) {
      // Even a live holder's report ACK is independent of its reader cleanup.
      @slot.native_wait_milliseconds(idle_wait_ms)
      continue
    }
    // Back off status transport while preserving exact original journals on
    // failed close. Report ACK and physical cleanup never substitute each other.
    let still_unsettled = unsettled.filter(current => {
      if @env.now() >= current.original.next_report_ms {
        observe_ended_holder(current, environment, client, observation_url)
        current.original.next_report_ms = @env.now() +
          max_backoff_ms.to_uint64()
      }
      if orphan_store is Some(_) ||
        reclaim_due ||
        orphan_reconciliation ||
        recovery.val is Some(_) ||
        pending_custody is Some(_) ||
        !ended_holder_can_leave_window(current, slot) {
        return true
      }
      if current.startability is Some(true) {
        // Same queued attempt, not a new Run/attempt. Its next start still goes
        // through the existing current dispatch read and durable claim Owner.
        report("holder-unclaimed", [("attempt", current.original.attempt)])
        next_start_ms = @env.now() + max_backoff_ms.to_uint64()
      } else {
        ignore(queue.remove(current.original.attempt))
        // Preserve the private observation only after the original status,
        // Channel, scoped process and current slot have confirmed retirement.
        // This DATA is not a Run outcome or task/Store capacity release.
        report("holder-settled", [
          ("attempt", current.original.attempt),
          (
            "request_cid",
            @remote.dispatch_request_identity(current.original.request),
          ),
        ])
      }
      false
    })
    unsettled.clear()
    unsettled.append(still_unsettled)
    // Observe the existing scoped stop before a new description takes the
    // slot for reclaim. Its original anchor pins the same inode until close.
    let mut physical_pending = false
    for current in unsettled {
      if !retire_ended_holder_process(current) {
        physical_pending = true
      }
    }
    if physical_pending {
      @slot.native_wait_milliseconds(idle_wait_ms)
      continue
    }
    // Start the oldest accepted attempt when the slot is free. The lock is
    // taken here and passed to the holder without a gap.
    if holder is None && !slot.is_open() {
      // A slot handed to an earlier holder is opened again; the same file is
      // always used.
      slot = match @slot.open_native_executor_slot(slot_path) {
        Ok(value) => value
        Err(_) => stop("executor slot open failed")
      }
      slot_progress = Ref(ControlSlotPending)
    }
    if !orphan_reconciliation &&
      holder is None &&
      (
        orphan_store is Some(_) ||
        (reclaim_due && @env.now() >= next_reclaim_ms)
      ) &&
      !skip_reclaim(reclaim_failures) {
      match
        reclaim_orphaned_outputs(
          orphan_settings, environment, slot, orphan_store, replay_journal, failed_orphan_store,
          slot_progress,
        ) {
        OrphansDone => {
          reclaim_due = false
          orphan_store = None
        }
        OrphansPending => {
          orphan_store = None
          next_reclaim_ms = @env.now() + max_backoff_ms.to_uint64()
        }
        OrphanStoreOpen(store) => {
          orphan_store = Some(store)
          next_reclaim_ms = @env.now() + max_backoff_ms.to_uint64()
        }
        OrphanNeedsReconciliation(store) => {
          orphan_store = Some(store)
          orphan_reconciliation = true
        }
      }
    }
    if holder is None &&
      orphan_store is None &&
      !reclaim_due &&
      !orphan_reconciliation {
      reconcile_saved_cancellation(
        matches, environment, replay_journal, client, observation_url, cancel_cursor,
        next_cancel_report, max_backoff_ms, site_delegation, recovery, recovery_close_failures,
      )
    }
    if replay_journal.val is Some(_) {
      // Cancellation observation shares the same retained Journal lifetime.
      // Do not accept/start another operation while its handle is unretired.
      @slot.native_wait_milliseconds(idle_wait_ms)
      continue
    }
    // No holder starts while this process still has the slot for a Store
    // it could not close yet.
    if holder is None &&
      unsettled.is_empty() &&
      orphan_store is None &&
      !reclaim_due &&
      !orphan_reconciliation &&
      recovery.val is None &&
      pending_custody is None &&
      @env.now() >= next_start_ms {
      if !slot.is_open() {
        slot = match @slot.open_native_executor_slot(slot_path) {
          Ok(value) => value
          Err(_) => stop("executor slot open failed")
        }
        slot_progress = Ref(ControlSlotPending)
      }
      match queue.next() {
        Some(attempt) =>
          // The exact request is read and checked before a holder starts, so
          // nothing is left to fail between the spawn and its tracking.
          match
            accepted_control_request(
              environment, replay_journal, attempt, envelope_read_failures,
            ) {
            None => {
              report("holder-request-unavailable", [("attempt", attempt)])
              @slot.native_wait_milliseconds(min_backoff_ms)
            }
            Some(request) =>
              match slot.try_acquire() {
                Ok(true) => {
                  holders += 1
                  let claimant = "holder-" +
                    @env.now().to_string() +
                    "-" +
                    holders.to_string()
                  let prepared = slot.prepare_scoped_holder()
                  let original = match prepared {
                    Ready(original) | Refused(original, _) => original
                  }
                  pending_spawn.val = Some(original)
                  let spawned = match prepared {
                    Ready(_) =>
                      original.spawn_with_channel(
                        executable,
                        holder_arguments(attempt, claimant),
                      )
                    Refused(_, issue) => Err(issue)
                  }
                  match (original.child(), original.channel()) {
                    (Ok(child), Ok(channel)) => {
                      // An error can retain an actually started child. Keep
                      // that same child/channel; never classify it as absent.
                      holder = Some({
                        spawn_custody: original,
                        child,
                        channel,
                        attempt,
                        request,
                        next_report_ms: 0,
                        reported_revision: None,
                      })
                      pending_spawn.val = None
                      report(
                        if spawned is Ok(_) {
                          "holder-started"
                        } else {
                          "holder-start-observation-pending"
                        },
                        [("attempt", attempt), ("claimant", claimant)],
                      )
                    }
                    _ => {
                      // The same preparation retains every partial endpoint
                      // or unexpected child until its own cleanup confirms.
                      report("holder-spawn-failed", [("attempt", attempt)])
                      @slot.native_wait_milliseconds(max_backoff_ms)
                    }
                  }
                }
                Ok(false) => report("slot-busy", [("attempt", attempt)])
                Err(_) => stop("executor slot lock failed")
              }
          }
        None => ()
      }
    }
    if replay_journal.val is Some(_) {
      // A pre-start envelope reader still owns cleanup. Its queued attempt
      // remains reserved; neither a Bundle operation nor poll may bypass it.
      @slot.native_wait_milliseconds(idle_wait_ms)
      continue
    }
    // A delivered context cannot be dropped merely because a holder owns the
    // Store. Retain this one exact request until the original slot is free.
    match pending_custody {
      Some(Waiting(delivery)) => {
        if holder is None &&
          orphan_store is None &&
          recovery.val is None &&
          !orphan_reconciliation {
          if !slot.is_open() {
            slot = match @slot.open_native_executor_slot(slot_path) {
              Ok(value) => value
              Err(_) => stop("executor slot open failed")
            }
            slot_progress = Ref(ControlSlotPending)
          }
          if slot.try_acquire() == Ok(true) {
            let original = try {
              match custody_configuration {
                Some(configuration) =>
                  control_bundle_custody_response(
                    matches, environment, delivery, configuration, slot,
                  )
                None =>
                  control_bundle_custody_cleanup(
                    delivery,
                    slot,
                    BundleCustodyRejected("scope-not-configured"),
                  )
              }
            } catch {
              CommandStop(reason) =>
                control_bundle_custody_cleanup(
                  delivery,
                  slot,
                  BundleCustodyRejected(reason),
                )
            }
            pending_custody = Some(Retiring(original))
          }
        }
        @slot.native_wait_milliseconds(max_backoff_ms)
        continue
      }
      Some(Responding(original)) => {
        // Only the authenticated reply boundary can retire this exact duty.
        // This step has no Store port and cannot repeat retain or release.
        let (remaining, reply) = @agent.advance_native_bundle_custody_report(
          Some(original),
          (delivery, response) => {
            @client.report_bundle_custody(
              client, observation_url, delivery, response,
            )
          },
        )
        pending_custody = match remaining {
          Some(value) => Some(Responding(value))
          None => None
        }
        match reply {
          Some(Accepted) => report("bundle-custody-observed", [])
          Some(Obsolete) => report("bundle-custody-transport-obsolete", [])
          None => @slot.native_wait_milliseconds(max_backoff_ms)
        }
        continue
      }
      Some(Retiring(_)) | Some(Unconfirmed(_)) => continue
      None => ()
    }
    if max_polls > 0 && polls >= max_polls {
      if holder is None && unsettled.is_empty() {
        break
      }
      @slot.native_wait_milliseconds(idle_wait_ms)
      continue
    }
    polls += 1
    let started = @env.now()
    let operation = match @client.poll_site_operation(client, poll_url) {
      Ok(Some(@remote.BundleCustody(delivery))) => {
        pending_custody = Some(Waiting(delivery))
        continue
      }
      Ok(Some(@remote.Run(operation))) => Ok(Some(operation))
      Ok(None) => Ok(None)
      Err(issue) => Err(issue)
    }
    guard open_control_replay_journal(environment, replay_journal)
      is Some(journal) else {
      // Nothing is lost: the operation is served again on a later poll.
      report("journal-unavailable", [])
      @slot.native_wait_milliseconds(max_backoff_ms)
      continue
    }
    match operation {
      Ok(None) => {
        backoff_ms = 0
        // A long poll that returned at once must not spin.
        if @env.now() - started < idle_wait_ms.to_uint64() {
          @slot.native_wait_milliseconds(idle_wait_ms)
        }
      }
      Ok(Some(@remote.Dispatch(dispatch))) => {
        backoff_ms = 0
        let incoming = @remote.remote_poll_dispatch_request(dispatch)
        if holder is Some(current) &&
          @remote.dispatch_request_identity(incoming) !=
          @remote.dispatch_request_identity(current.request) &&
          holder_can_receive(current.request, incoming) {
          match @remote.remote_poll_dispatch_run_materials(dispatch) {
            Some(materials) =>
              match
                @remote.remote_poll_dispatch_materials_json(
                  incoming,
                  @remote.remote_poll_dispatch_input_binding(dispatch),
                  materials,
                ) {
                Ok(body) =>
                  report("consumer-relayed", [
                    ("request_cid", @remote.dispatch_request_identity(incoming)),
                    (
                      "sent",
                      current.channel.send("consumer " + body).to_string(),
                    ),
                  ])
                Err(_) =>
                  report("consumer-unavailable", [("reason", "envelope")])
              }
            None => report("consumer-unavailable", [("reason", "materials")])
          }
          close_control_replay_journal(replay_journal)
          continue
        }
        match
          accept_site_dispatch(
            journal,
            client,
            observation_url,
            site_delegation,
            generation,
            queue,
            admission,
            effect_configuration,
            dispatch,
            start_timestamp(matches),
          ) {
          Ok(Accepted(attempt, request)) =>
            report("accepted", [
              ("attempt", attempt),
              ("request_cid", @remote.dispatch_request_identity(request)),
            ])
          Ok(Refused(refusal)) =>
            report("refused", [("reason", refusal_code(refusal))])
          Ok(AlreadyStarted(attempt)) =>
            report("already-started", [("attempt", attempt)])
          Err(issue) =>
            report("accept-failed", [("reason", holder_issue_code(issue))])
        }
      }
      Ok(Some(@remote.Cancel(request))) => {
        backoff_ms = 0
        let identity = @remote.dispatch_request_identity(request)
        match
          @resident.check_resident_dispatch_delegation(
            site_delegation, request, generation,
          ) {
          Err(refusal) =>
            report("cancel-refused", [("reason", refusal_code(refusal))])
          Ok(_) =>
            match journal.request_cancellation(request) {
              Err(_) =>
                report("cancel-pending", [
                  ("reason", "journal"),
                  ("request_cid", identity),
                ])
              Ok(record) => {
                if required(matches, "control-cancel-kill-at") == "after-save" {
                  report("control-cancel-killed", [("request_cid", identity)])
                  @slot.native_kill_self()
                }
                match @remote.dispatch_request_attempt_identity(request) {
                  Ok(attempt) =>
                    // Cancellation intent does not retire an ended executor's
                    // physical/channel responsibility or its admission.
                    if !unsettled.any(value => value.original.attempt == attempt) {
                      ignore(queue.remove(attempt))
                    }
                  Err(_) => ()
                }
                let codes = @remote.dispatch_record_state_codes(record)
                if holder is Some(current) &&
                  holder_can_receive(current.request, request) {
                  if codes[0] == 1 || codes[0] == 2 {
                    // Sending SIGTERM is not stop evidence. The existing slot
                    // and physical cleanup recovery establish that later.
                    report("cancel-stop-requested", [
                      ("request_cid", identity),
                      ("sent", current.child.terminate().to_string()),
                    ])
                  } else if codes[0] == 3 || codes[0] == 4 || codes[0] == 5 {
                    // Terminal execution still owns cleanup, including a
                    // consumer cancelled after borrow but before its start claim.
                    // Preserve completed execution and its evidence; release
                    // the exact retained output through its live owner.
                    report("cancel-release-relayed", [
                      ("request_cid", identity),
                      (
                        "sent",
                        current.channel.send("release " + identity).to_string(),
                      ),
                    ])
                  }
                }
                // Accepted cancellation stays nonstartable. A holder that is
                // already setting up will lose its claim and close its owners.
                // Absent cancellation already has a formal no-resource record.
                match
                  @client.acknowledge_status(
                    journal, client, observation_url, request,
                  ) {
                  Ok(_) =>
                    report("cancel-observed", [("request_cid", identity)])
                  Err(issue) =>
                    report("cancel-unreported", [
                      ("request_cid", identity),
                      ("reason", client_code(issue)),
                    ])
                }
              }
            }
        }
      }
      Ok(Some(@remote.Query(request))) => {
        backoff_ms = 0
        match
          @client.acknowledge_status(journal, client, observation_url, request) {
          Ok(Some(record)) => {
            let identity = @remote.dispatch_request_identity(request)
            for current in unsettled {
              if @remote.dispatch_request_identity(current.original.request) ==
                identity {
                current.report_evidence = OriginalStatusAcknowledged
                current.startability = Some(
                  @remote.remote_runtime_record_startable(record),
                )
              }
            }
            // A late Query report never removes physical/channel custody.
            report("query", [
              ("request_cid", identity),
              ("revision", @remote.dispatch_record_revision(record).to_string()),
            ])
          }
          Ok(None) =>
            report("not-seen", [
              ("request_cid", @remote.dispatch_request_identity(request)),
            ])
          Err(issue) => report("query-failed", [("reason", client_code(issue))])
        }
      }
      Ok(Some(@remote.Release(request))) => {
        backoff_ms = 0
        if @resident.check_resident_dispatch_delegation(
            site_delegation, request, generation,
          )
          is Err(_) {
          report("release-failed", [("reason", "scope-mismatch")])
          close_control_replay_journal(replay_journal)
          continue
        }
        // A live holder owns this output: it releases it and then ends.
        let identity = @remote.dispatch_request_identity(request)
        if holder is Some(current) &&
          holder_can_receive(current.request, request) {
          if current.channel.send("release " + identity) {
            report("release-relayed", [("request_cid", identity)])
          } else {
            report("release-unrelayed", [("request_cid", identity)])
          }
          close_control_replay_journal(replay_journal)
          continue
        }
        // Save the authenticated release before waiting for orphan payload
        // cleanup. Reclaim requires Releasing, so waiting for intents to vanish
        // first would leave a completed holder's Output custody permanently stuck.
        match
          @resident_host.begin_resident_output_release(
            journal, site_delegation, generation, request,
          ) {
          Ok(_) =>
            match journal.pending_output_intents() {
              Ok(values) => if !values.is_empty() { reclaim_due = true }
              Err(_) => {
                report("release-failed", [("reason", "journal")])
                close_control_replay_journal(replay_journal)
                continue
              }
            }
          // Non-completed dispositions keep the existing cancellation and
          // unstarted cleanup paths; this helper never guesses execution status.
          Err(@resident_host.OutputUnavailable) => ()
          Err(issue) => {
            report("release-failed", [("reason", output_code(issue))])
            close_control_replay_journal(replay_journal)
            continue
          }
        }
        if orphan_store is None &&
          !reclaim_due &&
          !orphan_reconciliation &&
          (match journal.require(request) {
            Ok(record) => {
              let codes = @remote.dispatch_record_state_codes(record)
              codes[0] == 3 &&
              (
                recovery.val is Some(_) ||
                codes[2] == 0 ||
                codes[2] == 1 ||
                codes[2] == 3
              )
            }
            _ => false
          }) {
          guard retry_control_replay_journal_cleanup(replay_journal) else {
            report("release-failed", [("reason", "original-journal-close")])
            continue
          }
          if recover_stopped_release(
              matches, environment, request, recovery, recovery_close_failures,
            ) {
            report("release-recovered", [("request_cid", identity)])
          }
        }
        // Recovery commits through a separate journal Owner. The pre-recovery
        // view has already restored this dispatch and cannot admit its newer
        // cleanup revision. Report only from a new exact durable view, as the
        // cancellation recovery path does; do not relax reconstruction.
        guard retry_control_replay_journal_cleanup(replay_journal) else {
          report("release-failed", [("reason", "original-journal-close")])
          continue
        }
        guard open_control_replay_journal(environment, replay_journal)
          is Some(current) else {
          report("release-failed", [("reason", "journal")])
          close_control_replay_journal(replay_journal)
          continue
        }
        match
          @client.acknowledge_status(current, client, observation_url, request) {
          Ok(_) =>
            report("release-observed", [
              ("request_cid", @remote.dispatch_request_identity(request)),
            ])
          Err(issue) =>
            report("release-failed", [("reason", client_code(issue))])
        }
        close_control_replay_journal(replay_journal)
      }
      Ok(Some(@remote.RetainedPlan(input))) => {
        backoff_ms = 0
        let intent = @remote.remote_poll_retained_input_intent(input)
        let request = @remote.remote_retained_input_intent_request(intent)
        let identity = @remote.dispatch_request_identity(request)
        match (holder, @remote.remote_poll_retained_input_plan_json(intent)) {
          (Some(current), Ok(body)) if holder_can_receive(
              current.request,
              request,
            ) =>
            if current.channel.send("retained-plan " + body) {
              report("retained-plan-relayed", [("request_cid", identity)])
            } else {
              report("retained-plan-unavailable", [("request_cid", identity)])
            }
          _ => {
            if holder is None &&
              queue_completed_retained_holder(
                journal,
                admission,
                site_delegation,
                generation,
                queue,
                intent,
                start_timestamp(matches),
              ) {
              report("retained-holder-queued", [("request_cid", identity)])
            }
            report("retained-plan-unavailable", [("request_cid", identity)])
          }
        }
      }
      Ok(Some(@remote.RetainedTransfer(input))) => {
        backoff_ms = 0
        let intent = @remote.remote_poll_retained_transfer_intent(input)
        let selected = @remote.remote_retained_input_intent_request(intent)
        let identity = @remote.dispatch_request_identity(selected)
        let body = @remote.remote_poll_retained_input_transfer_json(
          @remote.remote_poll_retained_transfer_plan(input),
        )
        match (holder, body) {
          (Some(current), Ok(body)) if holder_can_receive(
              current.request,
              selected,
            ) =>
            report("retained-transfer-relayed", [
              ("request_cid", identity),
              (
                "sent",
                current.channel.send("retained-transfer " + body).to_string(),
              ),
            ])
          _ => {
            if holder is None &&
              queue_completed_retained_holder(
                journal,
                admission,
                site_delegation,
                generation,
                queue,
                intent,
                start_timestamp(matches),
              ) {
              report("retained-holder-queued", [("request_cid", identity)])
            }
            report("retained-transfer-unavailable", [("request_cid", identity)])
          }
        }
      }
      Ok(Some(@remote.RetainedCurrent(query))) => {
        backoff_ms = 0
        let request = @remote.remote_retained_input_current_request(query)
        let identity = @remote.dispatch_request_identity(request)
        let body = @remote.remote_poll_retained_input_current_json(
          @remote.remote_retained_input_current_plan(query),
          @remote.remote_retained_input_current_query_identity(query),
        )
        match (holder, body) {
          (Some(current), Ok(body)) if holder_can_receive(
              current.request,
              request,
            ) =>
            report("retained-current-relayed", [
              ("request_cid", identity),
              (
                "sent",
                current.channel.send("retained-current " + body).to_string(),
              ),
            ])
          _ =>
            report("retained-current-unavailable", [("request_cid", identity)])
        }
      }
      Ok(Some(@remote.EffectCurrent(query))) => {
        backoff_ms = 0
        let request = @remote.remote_poll_effect_current_request(query)
        // Relay the owner-issued query unchanged. Only the original holder's
        // Review may observe its Ledger; transport supplies no report proof.
        match
          @resident.check_resident_dispatch_delegation(
            site_delegation, request, generation,
          ) {
          Err(refusal) =>
            report("effect-current-refused", [("reason", refusal_code(refusal))])
          Ok(_) =>
            match
              (holder, @remote.remote_poll_effect_current_envelope_json(query)) {
              (Some(current), Ok(body)) if holder_can_receive(
                  current.request,
                  request,
                ) =>
                report("effect-current-relayed", [
                  ("request_cid", @remote.dispatch_request_identity(request)),
                  (
                    "sent",
                    current.channel.send("effect-current " + body).to_string(),
                  ),
                ])
              _ =>
                report("effect-current-pending", [
                  ("request_cid", @remote.dispatch_request_identity(request)),
                  ("reason", "review-owner-unavailable"),
                ])
            }
        }
      }
      Ok(Some(@remote.EffectResume(delivery))) => {
        backoff_ms = 0
        let request = @remote.remote_poll_effect_resume_request(delivery)
        let identity = @remote.dispatch_request_identity(request)
        // Relay only to exact existing holder custody. The receiving Review
        // must independently admit approval and observe the current claim.
        match
          @resident.check_resident_dispatch_delegation(
            site_delegation, request, generation,
          ) {
          Err(refusal) =>
            report("effect-resume-refused", [("reason", refusal_code(refusal))])
          Ok(_) =>
            match
              (
                holder,
                @remote.remote_poll_effect_resume_envelope_json(delivery),
              ) {
              (Some(current), Ok(body)) if holder_can_receive(
                  current.request,
                  request,
                ) =>
                report("effect-resume-relayed", [
                  ("request_cid", identity),
                  (
                    "sent",
                    current.channel.send("effect-resume " + body).to_string(),
                  ),
                ])
              _ =>
                report("effect-resume-pending", [
                  ("request_cid", identity),
                  ("reason", "review-owner-unavailable"),
                ])
            }
        }
      }
      Ok(Some(@remote.Plan(output))) | Ok(Some(@remote.Output(output))) => {
        backoff_ms = 0
        // Relay unchanged to the live holder. If it has exited, select only
        // the original completed custody for the existing restoration path.
        let request = @remote.remote_poll_output_request(output)
        let identity = @remote.dispatch_request_identity(request)
        let intent = @remote.remote_poll_output_intent(output)
        let (kind, envelope) = if operation is Ok(Some(@remote.Plan(_))) {
          ("plan", @remote.remote_poll_output_plan_json(request, intent))
        } else {
          ("output", @remote.remote_poll_output_json(request, intent))
        }
        match (holder, envelope) {
          (Some(current), Ok(body)) if holder_can_receive(
              current.request,
              request,
            ) =>
            if current.channel.send(kind + " " + body) {
              report("output-relayed", [
                ("operation", kind),
                ("request_cid", identity),
              ])
            } else {
              report("output-unavailable", [("request_cid", identity)])
            }
          _ => {
            if holder is None &&
              queue_completed_output_holder(
                journal, site_delegation, generation, queue, request,
              ) {
              report("output-holder-queued", [("request_cid", identity)])
            }
            report("output-unavailable", [("request_cid", identity)])
          }
        }
      }
      Err(issue) => {
        // Transport and authentication failures back off; no attempt,
        // record or pending observation is created or dropped for it.
        backoff_ms = if backoff_ms == 0 {
          min_backoff_ms
        } else if backoff_ms * 2 > max_backoff_ms {
          max_backoff_ms
        } else {
          backoff_ms * 2
        }
        report("poll-failed", [
          ("reason", client_code(issue)),
          ("backoff_ms", backoff_ms.to_string()),
        ])
        @slot.native_wait_milliseconds(backoff_ms)
      }
    }
    close_control_replay_journal(replay_journal)
  }
  if pending_custody is Some(_) {
    report("bundle-custody-unknown-on-stop", [])
  }
  // After a termination request no new work is taken. A running holder is
  // given a bounded time to finish; after it, the durable journal keeps its
  // record and nothing unconfirmed is settled here.
  let mut waited = 0
  while holder is Some(current) && waited < shutdown_wait_ms {
    match current.child.wait(false) {
      Ok(Some(_)) => {
        unsettled.push(retain_ended_holder(current))
        holder = None
      }
      _ => {
        @slot.native_wait_milliseconds(50)
        waited += 50
      }
    }
  }
  for current in unsettled {
    observe_ended_holder(current, environment, client, observation_url)
  }
  // Neither report ACK nor child exit discards physical responsibility at the
  // terminal controller boundary. Keep it in the existing lifetime shell.
  if !unsettled.is_empty() ||
    pending_spawn.val is Some(_) ||
    holder is Some(_) ||
    orphan_store is Some(_) ||
    failed_orphan_store.val is Some(_) ||
    recovery.val is Some(_) ||
    pending_custody is Some(_) ||
    replay_journal.val is Some(_) {
    let handed = retain_control_ended_holder_lifetime(
      unsettled, holder, environment, client, observation_url, slot, slot_path, orphan_store,
      recovery, matches, recovery_close_failures, pending_custody, replay_journal,
      pending_spawn, failed_orphan_store, slot_progress,
    )
    slot = handed.0
    slot_progress = handed.1
    holder = None
    orphan_store = None
    pending_custody = None
  }
  if holder is Some(current) {
    report("holder-still-running", [("attempt", current.attempt)])
  }
  // A Store kept open for reclaiming is closed once more; if it still cannot
  // close, its payloads stay recorded as pending intents for the next start.
  match orphan_store {
    Some(store) =>
      if store.close() is Err(_) {
        report("orphan-reclaim-pending", [("reason", "store-close")])
      }
    None => ()
  }
  retain_control_terminal_handles(client, slot, slot_progress)
  // Library and backing retirement happen after this command's aliases
  // unwind. The terminal report is emitted only after those Owners close.
  entry.controller_returned = true
}

///|
fn output_code(issue : @resident_host.ResidentOutputIssue) -> String {
  match issue {
    OutputForeign => "foreign"
    OutputUnavailable => "unavailable"
    OutputRouteRefused => "route-refused"
    OutputJournal(_) => "journal"
    OutputRuntime(_) => "runtime"
    OutputPlan(_) => "plan"
    OutputPayloadStore(_) => "payload-store"
    OutputPayload(_) => "payload"
    OutputTransfer(@output.TransferSend(failure)) =>
      match @transfer_client.transfer_send_failure_issue(failure) {
        Rejected(status) => "transfer-rejected-" + status.to_string()
        Physical(_) => "transfer"
        Durable(_) => "transfer-journal"
        Protocol(_) => "transfer-protocol"
        ReconciliationRequired => "transfer-reconciliation"
        _ => "transfer-source"
      }
    OutputTransfer(_) => "transfer-setup"
    OutputProtocol(_) => "protocol"
    OutputStoreRefused => "store-refused"
    OutputIntent(_) => "intent"
    OutputIntentInvalid => "intent-invalid"
    OutputReportPending(_, _) => "report-save-pending"
  }
}

///|
/// Everything a holder needs to serve and clean up its output. It is opened
/// before execution, so no fallible setup remains once the holder owns an
/// output.
priv struct HolderOutputResources {
  // Same initial Site reservation, separate from snapshot retirement.
  mut effect_host_caller_operation : @site.SiteOperation?
  mut effect_host_caller_current : (() -> Bool)?
  mut effect_host_caller_ordinary : Bool
  effect_host_setup : Ref[HolderEffectHostSetupScope?]
  effect_host_installation : Ref[HolderEffectHostOperatorInstallation?]
  effect_host_holding : Ref[@site.SiteHolding?]
  effect_host_cleanup : Ref[@site.SiteCleanup?]
  // Shared across the existing resources projection; same producer custody.
  retained_delegation : @resident.ResidentRetainedInputDelegation?
  retained_root : @filesystem.Root?
  retained_max_bytes : Int64
  retained_max_objects : Int64
  control : @http.Client
  control_library : @http.Library
  transfer : @http.Client
  transfer_library : @http.Library
  store : @publication_store.Store
  transfer_journal : @transfer_journal.Journal
  observation_url : String
  destination_origin : String
  coordinator_authority : String
  site_key : String
  site_generation : Int
  store_authority : String
  release_failures : Int
  // Acceptance evidence only: result reports withheld after a delivery.
  mut result_report_failures : Int
  // Acceptance evidence only: the output step at which the holder kills
  // itself with SIGKILL, and the step at which it pauses for `pause_ms`.
  kill_at : String
  pause_at : String
  pause_ms : Int
}

///|
fn open_holder_output_resources(
  matches : @argparse.Matches,
  sqlite_library : @sqlite.Library,
) -> Result[HolderOutputResources, HolderOutputSetupFailure] {
  let settings = (
    required(matches, "observation-url"),
    required(matches, "transfer-origin"),
    required(matches, "coordinator-authority"),
    required(matches, "site-key"),
    required_int(matches, "site-generation"),
    required_int(matches, "holder-release-failures"),
    required_int(matches, "holder-result-report-failures"),
    required(matches, "holder-kill-at"),
    required(matches, "holder-pause-at"),
    required_int(matches, "holder-pause-ms"),
    required_int64(matches, "max-bytes"),
    required_int64(matches, "max-record-bytes"),
    required_int64(matches, "publication-capacity-bytes"),
    required_int(matches, "max-transfers"),
    required(matches, "publication-root"),
    required(matches, "publication-authority-cid"),
    required(matches, "transfer-journal"),
  ) catch {
    CommandStop(issue) => return Err(HolderOutputSetupRefused(issue))
  }
  let (
    observation_url,
    destination_origin,
    coordinator_authority,
    site_key,
    site_generation,
    release_failures,
    result_report_failures,
    kill_at,
    pause_at,
    pause_ms,
    max_bytes,
    max_record_bytes,
    publication_capacity,
    max_transfers,
    publication_root,
    publication_authority,
    transfer_journal_path,
  ) = settings
  let retained_delegation = retained_input_delegation(matches) catch {
    CommandStop(issue) => return Err(HolderOutputSetupRefused(issue))
  }
  // Parse both roles before any Root/Library acquisition. Values remain
  // configuration; the actual HTTP Owner performs its existing admission.
  let control_settings = holder_http_settings(matches, "control") catch {
    CommandStop(issue) => return Err(HolderOutputSetupRefused(issue))
  }
  let transfer_settings = holder_http_settings(matches, "transfer") catch {
    CommandStop(issue) => return Err(HolderOutputSetupRefused(issue))
  }
  let original = new_holder_partial_output_resources()
  match (retained_delegation, optional(matches, "retained-input-root")) {
    (None, None) => ()
    (Some(_), Some(path)) =>
      match @filesystem.open_root_with_custody(path) {
        Ok(root) => original.retained_root = Some(root)
        Err(failure) => {
          original.failed_root = Some(failure)
          return Err(
            HolderOutputSetupPending(
              original, "retained input Root unavailable",
            ),
          )
        }
      }
    _ =>
      return Err(
        HolderOutputSetupRefused(
          "retained input delegation and Root must be configured together",
        ),
      )
  }
  let control = match
    open_holder_partial_http_client(original, control_settings, true) {
    Ok(value) => value
    Err(failure) => return Err(failure)
  }
  let transfer = match
    open_holder_partial_http_client(original, transfer_settings, false) {
    Ok(value) => value
    Err(failure) => return Err(failure)
  }
  let store = match
    @publication_store.open_store_with_custody(
      sqlite_library,
      publication_root,
      publication_authority,
      publication_capacity,
      max_transfers.to_int64(),
      max_record_bytes,
    ) {
    Ok(value) => {
      original.store = Some(value)
      value
    }
    Err(RefusedBeforeAcquisition(_)) =>
      return Err(
        HolderOutputSetupPending(
          original, "publication Store configuration refused after prior acquisition",
        ),
      )
    Err(CleanupRequired(failure)) => {
      original.failed_store = Some(failure)
      return Err(
        HolderOutputSetupPending(original, "publication Store open failed"),
      )
    }
  }
  let transfer_journal = match
    @transfer_journal.open_journal_with_custody(
      sqlite_library, transfer_journal_path, max_record_bytes, 65536, 1048576, max_bytes,
    ) {
    Ok(value) => {
      original.transfer_journal = Some(value)
      value
    }
    Err(RefusedBeforeAcquisition(_)) =>
      return Err(
        HolderOutputSetupPending(
          original, "Transfer Journal configuration refused after prior acquisition",
        ),
      )
    Err(CleanupRequired(failure)) => {
      original.failed_transfer_journal = Some(failure)
      return Err(
        HolderOutputSetupPending(original, "Transfer Journal open failed"),
      )
    }
  }
  guard original.control_library is Some(control_library) &&
    original.transfer_library is Some(transfer_library) else {
    return Err(
      HolderOutputSetupPending(original, "original HTTP Libraries unavailable"),
    )
  }
  Ok({
    retained_delegation,
    effect_host_setup: Ref(None),
    effect_host_installation: Ref(None),
    effect_host_caller_operation: None,
    effect_host_caller_current: None,
    effect_host_caller_ordinary: false,
    effect_host_holding: Ref(None),
    effect_host_cleanup: Ref(None),
    retained_root: original.retained_root,
    retained_max_bytes: max_bytes,
    retained_max_objects: max_transfers.to_int64(),
    control,
    control_library,
    transfer,
    transfer_library,
    store,
    transfer_journal,
    observation_url,
    destination_origin,
    coordinator_authority,
    site_key,
    site_generation,
    store_authority: publication_authority,
    release_failures,
    result_report_failures,
    kill_at,
    pause_at,
    pause_ms,
  })
}

///|
/// Acceptance evidence only: at the named output step the holder kills
/// itself with SIGKILL, as an abrupt external kill would.
fn holder_checkpoint(resources : HolderOutputResources) -> (String) -> Unit {
  // The Store retains this observer. Capture only its immutable settings:
  // retaining resources here would also retain that Store and its Journal.
  let pause_at = resources.pause_at
  let pause_ms = resources.pause_ms
  let kill_at = resources.kill_at
  fn(point : String) {
    if point == pause_at {
      report("holder-paused", [("point", point)])
      @slot.native_wait_milliseconds(pause_ms)
    }
    if point == kill_at {
      report("holder-killed", [("point", point)])
      @slot.native_kill_self()
    }
  }
}

///|
/// After execution the holder keeps its output and serves the Coordinator's
/// output operations, relayed by the control process over the holder's
/// standard input. When the output is released, or the control process is
/// gone, the holder releases the output and reclaims every payload the Store
/// may hold for it, retrying each step until it is confirmed. It never ends
/// while it still owns a cleanup: until then it keeps the executor slot and
/// the capacity counted. Nothing here can fail before that cleanup.
fn serve_holder_output(
  resources : HolderOutputResources,
  environment : SiteEnvironment,
  executed : @resident_host.ResidentExecuted,
  admission : @resident_host.ResidentRunAdmission,
  current_time : () -> String,
  execution : @resident_host.ResidentExecution,
  configuration : @resident_host.ResidentSourceComputeConfiguration?,
  delegation : @resident.ResidentSiteDelegation,
  claimant : String,
  executor_entry : ((String) -> Bool)?,
  exclusive_current : () -> Bool,
  effect_producer? : @resident_host.ResidentEffectProducerExecuted? = None,
  // Independent operator installation remains a separate entry. A missing
  // installation refuses evidence access instead of adopting poll policy.
  effect_catalog_review? : (HolderEffectOriginalPolicyContext) -> Bool = _ => {
    false
  },
  effect_host_operator? : Ref[HolderEffectHostOperatorInstallation?] = Ref(None),
  effect_resume_installation? : (@remote.DispatchRequest) -> @effect_review.NativeResidentEffectCloudResumeInstallation? = _ => {
    None
  },
) -> Unit {
  let request = executed.request
  let control = resources.control
  let transfer = resources.transfer
  let store = resources.store
  let transfer_journal = resources.transfer_journal
  let observation_url = resources.observation_url
  let destination_origin = resources.destination_origin
  let coordinator_authority = resources.coordinator_authority
  let site_key = resources.site_key
  let site_generation = resources.site_generation
  let resume_current_url = holder_effect_resume_current_url(observation_url)
  let reviewer_current_url = holder_effect_reviewer_current_url(observation_url)
  let mut resume_query_sequence = 0L
  let identity = @remote.dispatch_request_identity(request)
  // No production issuer supplies mapped Review preparation. Consumer accept
  // receives no Catalog-use envelope; ordinary execution remains unchanged.
  store.observe_allocation(holder_checkpoint(resources))
  let tasks : Map[String, HolderTaskCustody] = Map([])
  let order : Array[String] = [identity]
  let original = new_holder_task_custody(
    request,
    Some(executed),
    None,
    None,
    effect_producer~,
  )
  tasks.set(identity, original)
  let evidence_allowed = (
    task : HolderTaskCustody,
    purpose : HolderEffectEvidencePurpose,
  ) => {
    guard holder_effect_original_policy_context(
        task,
        tasks,
        environment.journal,
      )
      is Some(context) else {
      return false
    }
    guard effect_host_operator.val is Some(installed) else { return false }
    with_holder_effect_host_read_scope(installed.scope, () => {
      holder_effect_evidence_allowed(context, resources, purpose, original => {
        holder_effect_operator_admission(
          original,
          resources,
          effect_host_operator.val,
        )
      })
    })
  }
  if holder_effect_computation(original, environment.journal) is Some(_) {
    report("effect-computation-custody-retained", [("request_cid", identity)])
  }
  let mut serving = true
  while serving {
    match read_holder_lifetime_input() {
      InputEnded => {
        report("holder-control-gone", [("request_cid", identity)])
        serving = false
      }
      InputInvalid => report("holder-input-invalid", [])
      InputLine(line) => {
        // Fixed routing facts only: never emit the frame body, credentials
        // or an arbitrary malformed prefix. Receipt is not completion.
        let operation = if line.has_prefix("release ") {
          "release"
        } else if line == "effect-review" {
          "effect-review"
        } else if line.has_prefix("effect-current ") {
          "effect-current"
        } else if line.has_prefix("effect-resume ") {
          "effect-resume"
        } else if line.has_prefix("consumer ") {
          "consumer"
        } else if line.has_prefix("retained-plan ") {
          "retained-plan"
        } else if line.has_prefix("retained-current ") {
          "retained-current"
        } else if line.has_prefix("retained-transfer ") {
          "retained-transfer"
        } else if line.has_prefix("plan ") {
          "plan"
        } else if line.has_prefix("output ") {
          "output"
        } else {
          "unrecognized"
        }
        report("holder-input-frame", [
          ("operation", operation),
          ("holder_request_cid", identity),
        ])
        if line == "effect-review" {
          // Only the holder's exact completed task index supplies candidates.
          // A remote Current query cannot prepare a Review, refresh policy,
          // perform a Provider read or advance publication responsibility.
          for task_identity in order {
            guard tasks.get(task_identity) is Some(task) && !task.released else {
              continue
            }
            let current_authority = () => {
              exclusive_current() &&
              evidence_allowed(task, Read) &&
              @resident.check_resident_dispatch_delegation(
                delegation,
                task.request,
                @site.site_generation(environment.site),
              )
              is Ok(_)
            }
            // Response custody can be retried during release, but never sent
            // again. No approval or new credential is selected by this tick.
            if current_authority() && task.effect_review is Some(review) {
              match review.retry_approved_row_custody() {
                Ok(true) =>
                  report("effect-row-settled", [("request_cid", task_identity)])
                _ => ()
              }
            }
            if task.release_requested || task.consumer is None {
              continue
            }
            ignore(
              drive_holder_effect_review(
                task,
                tasks,
                environment.journal,
                resources,
                effect_catalog_review,
                current_authority,
                () => current_authority() && evidence_allowed(task, Publication),
              ),
            )
          }
        } else if line.has_prefix("effect-resume ") {
          let body = line.unsafe_substring(start=14, end=line.length())
          match @remote.admit_remote_poll_effect_resume_json(body) {
            Ok(delivery) => {
              let selected = @remote.remote_poll_effect_resume_request(delivery)
              let current_site = () => {
                exclusive_current() &&
                @resident.check_resident_dispatch_delegation(
                  delegation,
                  selected,
                  @site.site_generation(environment.site),
                )
                is Ok(_)
              }
              guard current_site() &&
                holder_effect_current_task(tasks, selected) is Some(task) &&
                !task.release_requested &&
                task.effect_review is Some(_) &&
                effect_resume_installation(task.request) is Some(installed) &&
                installed.scope.site_key == resources.site_key &&
                installed.scope.site_generation ==
                resources.site_generation.to_int64() &&
                installed.scope.authority_scope_cid ==
                resources.coordinator_authority &&
                resume_current_url is Some(current_url) &&
                reviewer_current_url is Some(reviewer_url) else {
                report("effect-resume-pending", [
                  ("request_cid", @remote.dispatch_request_identity(selected)),
                  ("reason", "review-owner-unavailable"),
                ])
                continue
              }
              let next_query_id = () => {
                if resume_query_sequence >= 9007199254740991L {
                  return ""
                }
                resume_query_sequence += 1L
                holder_effect_resume_query_id(
                  @remote.dispatch_request_identity(task.request),
                  @env.now().reinterpret_as_int64(),
                  resume_query_sequence,
                ).unwrap_or("")
              }
              let claim_control : @effect_review.NativeEffectCloudCurrentRead = {
                client: control,
                url: current_url,
                current_site,
                next_query_id,
                now_ms: () => @env.now().reinterpret_as_int64(),
              }
              ignore(
                execute_holder_effect_resume(
                  task,
                  @remote.remote_poll_effect_resume_delivery_json(delivery),
                  installed,
                  claim_control,
                  { ..claim_control, url: reviewer_url, },
                  current_site,
                ),
              )
            }
            Err(_) => report("holder-input-invalid", [])
          }
        } else if line.has_prefix("effect-current ") {
          let body = line.unsafe_substring(start=15, end=line.length())
          // Routing metadata selects the holder only. The Review separately
          // admits the query against its paired original accepted report.
          let poll = @remote.admit_remote_poll_effect_current_json(body)
          match poll {
            Ok(query) => {
              let selected = @remote.remote_poll_effect_current_request(query)
              guard holder_effect_current_task(tasks, selected) is Some(task) else {
                report("effect-current-pending", [
                  ("reason", "review-owner-unavailable"),
                ])
                continue
              }
              let current_authority = () => {
                exclusive_current() &&
                evidence_allowed(task, Read) &&
                @resident.check_resident_dispatch_delegation(
                  delegation,
                  selected,
                  @site.site_generation(environment.site),
                )
                is Ok(_)
              }
              guard current_authority() else {
                report("effect-current-pending", [
                  ("reason", "review-owner-unavailable"),
                ])
                continue
              }
              // Remote Current only observes an existing original Review.
              // Preparation is driven by completed local custody under the
              // independently installed policy, never by query routing input.
              guard task.effect_review is Some(review) else {
                report("effect-current-pending", [
                  ("reason", "review-owner-unavailable"),
                ])
                continue
              }
              match
                review.report_effect_current(
                  @remote.remote_poll_effect_current_query_json(query),
                  control,
                  observation_url,
                  current_authority,
                  { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 32, },
                ) {
                Ok(_) =>
                  report("effect-current-reported", [
                    ("request_cid", @remote.dispatch_request_identity(selected)),
                  ])
                Err(_) =>
                  report("effect-current-pending", [
                    ("reason", "original-custody"),
                  ])
              }
            }
            Err(_) => report("holder-input-invalid", [])
          }
        } else if line.has_prefix("release ") {
          let target = line.unsafe_substring(start=8, end=line.length())
          // Exact child cleanup precedes its producer. Replayed releases
          // also retry the current durable observation after cleanup.
          if !handle_holder_release_frame(tasks, order, target, task => {
              if !release_holder_task(
                  task, tasks, environment, execution, resources,
                ) {
                report("producer-release-pending", [
                  (
                    "request_cid",
                    @remote.dispatch_request_identity(task.request),
                  ),
                  ("reason", "consumer-custody"),
                ])
              }
            }) {
            report("holder-input-invalid", [])
            continue
          }
          if original.released {
            serving = false
          }
        } else if line.has_prefix("consumer ") {
          let envelope = line.unsafe_substring(start=9, end=line.length())
          match
            (@remote.admit_remote_poll_dispatch_json(envelope), configuration) {
            (Ok(dispatch), Some(configuration)) => {
              let family = match
                @resident_host.resident_dispatch_execution_family(
                  admission, dispatch,
                ) {
                Ok(value) => value
                Err(_) => {
                  report("consumer-refused", [("reason", "materials")])
                  continue
                }
              }
              let producer_identity = match
                (match family {
                  EffectFreeComputation =>
                    @resident_host.resident_retained_consumer_producer_identity(
                      admission,
                      dispatch,
                      current_time(),
                    ).map_err(issue => {
                      @resident_host.ResidentRetainedExecutionIssue::Host(issue)
                    })
                  EffectComputation =>
                    @resident_host.resident_effect_retained_consumer_producer_identity(
                      environment.journal,
                      admission,
                      resident_effect_limits(admission),
                      configuration,
                      dispatch,
                      current_time(),
                    )
                }) {
                Ok(value) => value
                Err(_) => {
                  report("consumer-refused", [("reason", "retained-input")])
                  continue
                }
              }
              guard tasks.get(producer_identity) is Some(producer) &&
                !producer.released &&
                producer.handoff is Some((_, handoff)) else {
                report("consumer-unavailable", [("reason", "holder-custody")])
                continue
              }
              let binding_limits : @output.NativeRemoteStandardTransferBindingLimits = {
                max_binding_bytes: 1048576,
                max_chunks: 65536,
                max_manifest_bytes: 1048576,
                max_referenced_bytes: resources.retained_max_bytes,
              }
              let owner = match
                (match family {
                  EffectFreeComputation =>
                    @resident_host.prepare_resident_retained_consumer(
                      handoff,
                      environment.journal,
                      admission,
                      dispatch,
                      current_time(),
                      binding_limits,
                    )
                  EffectComputation =>
                    @resident_host.prepare_resident_effect_retained_consumer(
                      handoff,
                      environment.journal,
                      admission,
                      resident_effect_limits(admission),
                      configuration,
                      dispatch,
                      current_time(),
                      binding_limits,
                    )
                }) {
                Ok(value) => value
                Err(_) => {
                  report("consumer-refused", [("reason", "retained-input")])
                  continue
                }
              }
              let candidate = new_holder_task_custody(
                @resident_host.resident_retained_consumer_request(owner),
                None,
                Some(owner),
                Some(producer_identity),
              )
              guard remember_holder_successor(tasks, order, producer, candidate)
                is Some(task) else {
                report("consumer-refused", [("reason", "retained-input")])
                continue
              }
              match
                owner.accept(
                  environment.journal,
                  control,
                  observation_url,
                  delegation,
                  @site.site_generation(environment.site),
                  admission,
                  dispatch,
                  current_time(),
                  initial_catalog_use=None,
                ) {
                Ok(Accepted(_, _)) => {
                  let active = match
                    execution.bundles.acquire_active_component(
                      @bundle.native_active_runtime_component_cid(
                        execution.active_runtime,
                      ),
                      @bundle.native_active_runtime_target_triple(
                        execution.active_runtime,
                      ),
                      consumer_process_hold_identity(
                        @resident_host.resident_retained_consumer_request(owner),
                      ),
                    ) {
                    Ok(value) => value
                    Err(_) => {
                      report("consumer-accept-pending", [
                        ("reason", "bundle-holding"),
                      ])
                      continue
                    }
                  }
                  task.process_hold.val = Some(active)
                  match
                    owner.execute(
                      environment.journal,
                      { ..execution, active_runtime: active, },
                      admission,
                      configuration,
                      retained_consumer_input_limits(),
                      claimant,
                      current_time,
                      executor_entry,
                      borrow_observe=() => {
                        holder_checkpoint(resources)(
                          "retained-consumer-borrowed",
                        )
                      },
                    ) {
                    Ok(completed) => {
                      task.process_hold.val = None
                      task.executed = Some(completed)
                      if owner.effect_computation(environment.journal)
                        is Some(_) {
                        ignore(
                          drive_holder_effect_review(
                            task,
                            tasks,
                            environment.journal,
                            resources,
                            effect_catalog_review,
                            () => {
                              exclusive_current() &&
                              evidence_allowed(task, Read) &&
                              @resident.check_resident_dispatch_delegation(
                                delegation,
                                task.request,
                                @site.site_generation(environment.site),
                              )
                              is Ok(_)
                            },
                            () => {
                              exclusive_current() &&
                              evidence_allowed(task, Publication)
                            },
                          ),
                        )
                      }
                      if holder_effect_computation(task, environment.journal)
                        is Some(_) {
                        report("effect-computation-custody-retained", [
                          (
                            "request_cid",
                            completed.completion.dispatch_request_cid,
                          ),
                        ])
                      }
                      report("consumer-executed", [
                        (
                          "request_cid",
                          completed.completion.dispatch_request_cid,
                        ),
                        ("revision", completed.completion.revision.to_string()),
                      ])
                      if completed.result_definition_cid is None {
                        holder_checkpoint(resources)(
                          "completed-retained-intermediate",
                        )
                      }
                      if completed.result_definition_cid is Some(_) {
                        // Interrupt only after the original consumer outcome
                        // and returned borrow are durable, before its reply.
                        holder_checkpoint(resources)("completed-consumer")
                      }
                    }
                    Err(failure) => {
                      if failure.pending_runtime is Some(_) {
                        task.process_hold.val = None
                      } else {
                        close_untransferred_consumer_binding(
                          execution,
                          task.process_hold,
                        )
                      }
                      report("consumer-failed", [("reason", "owned-execution")])
                    }
                  }
                  ignore(
                    @client.acknowledge_status(
                      environment.journal,
                      control,
                      observation_url,
                      @resident_host.resident_retained_consumer_request(owner),
                    ),
                  )
                }
                Ok(AlreadyStarted(_)) => report("consumer-already-started", [])
                Ok(Refused(issue)) =>
                  report("consumer-refused", [("reason", refusal_code(issue))])
                Err(issue) =>
                  report("consumer-accept-pending", [
                    ("reason", host_code(issue)),
                  ])
              }
            }
            _ => report("consumer-unavailable", [("reason", "holder-custody")])
          }
        } else if line.has_prefix("retained-plan ") {
          let envelope = line.unsafe_substring(start=14, end=line.length())
          match
            (
              @remote.admit_remote_poll_retained_input_plan_json(envelope),
              resources.retained_delegation,
            ) {
            (Ok(poll), Some(delegated)) => {
              let intent = @remote.remote_poll_retained_input_intent(poll)
              let selected = @remote.remote_retained_input_intent_request(
                intent,
              )
              let producer_identity = @remote.dispatch_request_identity(
                selected,
              )
              guard tasks.get(producer_identity) is Some(producer) &&
                !producer.released &&
                producer.executed is Some(producer_executed) else {
                report("retained-plan-failed", [("reason", "foreign-dispatch")])
                continue
              }
              let context = match
                prepare_holder_producer_context(
                  environment.journal,
                  admission,
                  configuration,
                  delegation,
                  @site.site_generation(environment.site),
                  intent,
                  current_time(),
                ) {
                Ok(value) => value
                Err(issue) => {
                  report("retained-plan-failed", [
                    ("reason", holder_issue_code(issue)),
                  ])
                  continue
                }
              }
              let current = @host.install_client_retained_input_current(
                () => environment.site,
                () => coordinator_authority,
                () => @env.now().reinterpret_as_int64(),
                (_, request) => {
                  @resident_host.resident_retained_producer_authorized(
                    context,
                    delegated,
                    request,
                    @site.site_generation(environment.site),
                    current_time(),
                  )
                },
              )
              match
                @resident_host.plan_resident_retained_input_transfer(
                  producer_executed.runtime,
                  @resident_host.resident_retained_producer(context),
                  intent,
                  current,
                  environment.site,
                ) {
                Ok(plan) => {
                  if producer.release_requested &&
                    !(producer.handoff is Some((saved, _)) &&
                    saved == @remote.remote_retained_input_plan_identity(plan)) {
                    report("retained-plan-failed", [
                      ("reason", "foreign-handoff"),
                    ])
                    continue
                  }
                  match
                    @client.acknowledge_retained_input_plan(
                      control, observation_url, plan,
                    ) {
                    Ok(_) =>
                      report("retained-input-planned", [
                        ("request_cid", producer_identity),
                      ])
                    Err(issue) =>
                      report("retained-plan-unreported", [
                        ("reason", client_code(issue)),
                      ])
                  }
                }
                Err(issue) =>
                  report("retained-plan-failed", [
                    ("reason", retained_transfer_code(issue)),
                  ])
              }
            }
            (Ok(_), None) =>
              report("retained-plan-failed", [
                ("reason", "movement-not-delegated"),
              ])
            _ => report("holder-input-invalid", [])
          }
        } else if line.has_prefix("retained-current ") {
          let envelope = line.unsafe_substring(start=17, end=line.length())
          match
            (
              @remote.admit_remote_poll_retained_input_current_json(envelope),
              resources.retained_delegation,
            ) {
            (Ok(query), Some(_)) => {
              let producer_identity = @remote.dispatch_request_identity(
                @remote.remote_retained_input_current_request(query),
              )
              guard tasks.get(producer_identity) is Some(producer) &&
                !producer.released &&
                producer.handoff is Some((saved, owner)) else {
                report("retained-current-pending", [
                  ("reason", "receiver-owner-unavailable"),
                ])
                continue
              }
              if @remote.remote_retained_input_plan_identity(
                  @remote.remote_retained_input_current_plan(query),
                ) !=
                saved {
                report("retained-current-failed", [
                  ("reason", "foreign-handoff"),
                ])
                continue
              }
              // Read the existing receiver only. A query never advances a
              // partial handoff, reserves capacity or starts a consumer.
              match owner.current_reply(query) {
                Ok(reply) =>
                  match
                    @client.acknowledge_retained_input_current(
                      control, observation_url, reply,
                    ) {
                    Ok(_) =>
                      report("retained-current-reported", [
                        ("request_cid", producer_identity),
                      ])
                    Err(issue) =>
                      report("retained-current-unreported", [
                        ("reason", client_code(issue)),
                      ])
                  }
                Err(issue) =>
                  report("retained-current-pending", [
                    ("reason", retained_transfer_code(issue)),
                  ])
              }
            }
            (Ok(_), _) =>
              report("retained-current-pending", [
                ("reason", "receiver-owner-unavailable"),
              ])
            _ => report("holder-input-invalid", [])
          }
        } else if line.has_prefix("retained-transfer ") {
          let envelope = line.unsafe_substring(start=18, end=line.length())
          match
            (
              @remote.admit_remote_poll_retained_input_transfer_json(envelope),
              resources.retained_delegation,
              resources.retained_root,
            ) {
            (Ok(poll), Some(delegated), Some(root)) => {
              let intent = @remote.remote_poll_retained_transfer_intent(poll)
              let plan = @remote.remote_poll_retained_transfer_plan(poll)
              let selected = @remote.remote_retained_input_intent_request(
                intent,
              )
              let plan_cid = @remote.remote_retained_input_plan_identity(plan)
              let producer_identity = @remote.dispatch_request_identity(
                selected,
              )
              guard tasks.get(producer_identity) is Some(producer) &&
                !producer.released &&
                (!producer.release_requested || producer.handoff is Some(_)) &&
                producer.executed is Some(producer_executed) else {
                report("retained-transfer-failed", [
                  ("reason", "foreign-dispatch"),
                ])
                continue
              }
              let handoff = match producer.handoff {
                Some((saved, owner)) if saved == plan_cid => owner
                Some(_) => {
                  report("retained-transfer-failed", [
                    ("reason", "foreign-plan"),
                  ])
                  continue
                }
                None => {
                  let context = match
                    prepare_holder_producer_context(
                      environment.journal,
                      admission,
                      configuration,
                      delegation,
                      @site.site_generation(environment.site),
                      intent,
                      current_time(),
                    ) {
                    Ok(value) => value
                    Err(issue) => {
                      report("retained-transfer-failed", [
                        ("reason", holder_issue_code(issue)),
                      ])
                      continue
                    }
                  }
                  let current = @host.install_client_retained_input_current(
                    () => environment.site,
                    () => coordinator_authority,
                    () => @env.now().reinterpret_as_int64(),
                    (_, request) => {
                      @resident_host.resident_retained_producer_authorized(
                        context,
                        delegated,
                        request,
                        @site.site_generation(environment.site),
                        current_time(),
                      )
                    },
                  )
                  let owner = match
                    @resident_host.prepare_resident_retained_plan_transfer(
                      producer_executed.runtime,
                      @resident_host.resident_retained_producer(context),
                      intent,
                      plan,
                      current,
                      environment.site,
                      transfer_journal,
                      root,
                      65536,
                      resources.retained_max_bytes,
                      resources.retained_max_objects,
                    ) {
                    Ok(value) => value
                    Err(issue) => {
                      report("retained-transfer-failed", [
                        ("reason", retained_transfer_code(issue)),
                      ])
                      continue
                    }
                  }
                  producer.handoff = Some((plan_cid, owner))
                  owner
                }
              }
              // A bounded round allows control to observe cancellation between
              // rounds. Reoffering the exact plan resumes the same pending chunk.
              let mut completed = handoff.result() is Ok(_)
              let mut failed = false
              for _index in 0..<16 {
                if completed {
                  break
                }
                match handoff.advance() {
                  Ok(true) => {
                    completed = true
                    break
                  }
                  Ok(false) =>
                    // A chunk is durable, but the destination is not yet
                    // committed. Reconstruction must resume this exact
                    // Transfer from the retained producer, not reacquire it.
                    holder_checkpoint(resources)("retained-transfer-pending")
                  Err(issue) => {
                    failed = true
                    report("retained-transfer-pending", [
                      ("reason", retained_transfer_code(issue)),
                    ])
                    break
                  }
                }
              }
              if completed {
                // Durable receiver receipt precedes this interruption point;
                // neither a result report nor a consumer start is implied.
                holder_checkpoint(resources)("retained-receiver-committed")
                match handoff.result() {
                  Ok(result) =>
                    match
                      @client.acknowledge_retained_input_result(
                        control, observation_url, result,
                      ) {
                      Ok(_) =>
                        report("retained-transfer-reported", [
                          ("request_cid", producer_identity),
                        ])
                      Err(issue) =>
                        report("retained-transfer-unreported", [
                          ("reason", client_code(issue)),
                        ])
                    }
                  Err(issue) =>
                    report("retained-transfer-pending", [
                      ("reason", retained_transfer_code(issue)),
                    ])
                }
              } else if !failed {
                report("retained-transfer-pending", [("reason", "more-chunks")])
              }
            }
            (Ok(_), _, _) =>
              report("retained-transfer-failed", [
                ("reason", "movement-not-delegated"),
              ])
            _ => report("holder-input-invalid", [])
          }
        } else if line.has_prefix("plan ") {
          let envelope = line.unsafe_substring(start=5, end=line.length())
          match @remote.admit_remote_poll_output_plan_json(envelope) {
            Ok(output) => {
              let output_identity = @remote.dispatch_request_identity(
                @remote.remote_poll_output_request(output),
              )
              let output_request = @remote.remote_poll_output_request(output)
              if !restore_completed_holder_successor(
                  tasks, order, output_request, environment, execution, resources,
                  admission, delegation, current_time, exclusive_current,
                ) {
                report("output-restoration-pending", [
                  ("request_cid", output_identity),
                ])
                continue
              }
              guard tasks.get(output_identity) is Some(output_task) &&
                !output_task.released &&
                !output_task.release_requested &&
                holder_result_output(output_task, effect_resume_installation, () => {
                  exclusive_current() &&
                  evidence_allowed(output_task, Read) &&
                  @resident.check_resident_dispatch_delegation(
                    delegation,
                    output_task.request,
                    @site.site_generation(environment.site),
                  )
                  is Ok(_)
                })
                is Some(output_owner) else {
                report("output-plan-failed", [("reason", "foreign-dispatch")])
                continue
              }
              match
                @resident_host.plan_resident_output(
                  output_owner,
                  environment.journal,
                  coordinator_authority,
                  site_key,
                  site_generation,
                  output,
                ) {
                Ok(plan) =>
                  match
                    @client.acknowledge_output_plan(
                      control, observation_url, plan,
                    ) {
                    Ok(_) =>
                      report("output-planned", [
                        (
                          "request_cid",
                          @remote.dispatch_request_identity(
                            output_owner.request,
                          ),
                        ),
                      ])
                    Err(issue) =>
                      report("output-plan-unreported", [
                        ("reason", client_code(issue)),
                      ])
                  }
                Err(issue) =>
                  report("output-plan-failed", [("reason", output_code(issue))])
              }
            }
            Err(_) => report("holder-input-invalid", [])
          }
        } else if line.has_prefix("output ") {
          let envelope = line.unsafe_substring(start=7, end=line.length())
          match @remote.admit_remote_poll_output_json(envelope) {
            Ok(output) => {
              let output_identity = @remote.dispatch_request_identity(
                @remote.remote_poll_output_request(output),
              )
              let output_request = @remote.remote_poll_output_request(output)
              if !restore_completed_holder_successor(
                  tasks, order, output_request, environment, execution, resources,
                  admission, delegation, current_time, exclusive_current,
                ) {
                report("output-restoration-pending", [
                  ("request_cid", output_identity),
                ])
                continue
              }
              guard tasks.get(output_identity) is Some(output_task) &&
                !output_task.released &&
                !output_task.release_requested &&
                holder_result_output(output_task, effect_resume_installation, () => {
                  exclusive_current() &&
                  evidence_allowed(output_task, Read) &&
                  @resident.check_resident_dispatch_delegation(
                    delegation,
                    output_task.request,
                    @site.site_generation(environment.site),
                  )
                  is Ok(_)
                })
                is Some(output_owner) else {
                report("output-plan-failed", [("reason", "foreign-dispatch")])
                continue
              }
              let identity = @remote.dispatch_request_identity(
                output_owner.request,
              )
              // Retry only this exact output's outstanding physical cleanup.
              let still_pending = output_task.failed_cleanups.filter(issue => {
                !@resident_host.retry_resident_output_cleanup(issue)
              })
              output_task.failed_cleanups.clear()
              output_task.failed_cleanups.append(still_pending)
              match
                @resident_host.deliver_resident_output(
                  output_owner,
                  environment.journal,
                  coordinator_authority,
                  site_key,
                  site_generation,
                  output,
                  store,
                  transfer,
                  transfer_journal,
                  destination_origin,
                  resources.store_authority,
                  65536,
                  holder_checkpoint(resources),
                ) {
                delivery => {
                  // Whatever happened, a payload the Store may hold for this
                  // output is this holder's to reclaim.
                  match delivery.payload {
                    Some(payload) => {
                      let payload_identity = @payload.publication_payload_request_identity(
                        payload,
                      )
                      if !output_task.payloads
                        .iter()
                        .any(kept => {
                          @payload.publication_payload_request_identity(kept) ==
                          payload_identity
                        }) {
                        output_task.payloads.push(payload)
                      }
                    }
                    None => ()
                  }
                  match delivery.result {
                    Ok(_) if resources.result_report_failures > 0 => {
                      // Acceptance hook: the delivered result is not
                      // reported, as if the report had been lost.
                      resources.result_report_failures -= 1
                      report("output-result-unreported", [
                        ("reason", "injected"),
                      ])
                    }
                    Ok(result) =>
                      report("output-report-retained", [
                        ("request_cid", identity),
                        (
                          "report_cid",
                          @remote.remote_output_result_identity(result),
                        ),
                      ])
                    Err(@resident_host.OutputReportPending(custody, _)) => {
                      let key = @remote.remote_output_report_custody_key(
                        custody,
                      )
                      if !output_task.unsaved_reports.any(value => {
                          @remote.remote_output_report_custody_key(value) == key
                        }) {
                        output_task.unsaved_reports.push(custody)
                      }
                      report("output-report-save-pending", [
                        ("request_cid", identity),
                      ])
                    }
                    Err(issue) => {
                      report("output-failed", [("reason", output_code(issue))])
                      if !@resident_host.retry_resident_output_cleanup(issue) {
                        output_task.failed_cleanups.push(issue)
                      }
                    }
                  }
                }
              }
            }
            Err(_) => report("holder-input-invalid", [])
          }
        } else {
          report("holder-input-invalid", [])
        }
      }
    }
  }
  // Persist all exact reports before the handoff interruption point. A later
  // reconstruction may replay them, but must never redeliver or recompute.
  for identity in order {
    let task = tasks.get(identity).unwrap()
    while !retain_holder_task_reports(task, environment.journal) {
      @slot.native_wait_milliseconds(250)
    }
  }
  if !original.released {
    holder_checkpoint(resources)("report-handoff")
  }
  // Control loss stops the whole retained chain. Reverse creation order is
  // dependency order because common admission allows only a completed parent
  // to acquire its one checked successor. Every retry keeps the same Owners.
  for index = order.length() - 1; index >= 0; index = index - 1 {
    let task = tasks.get(order[index]).unwrap()
    while !release_holder_task(
            task,
            tasks,
            environment,
            execution,
            resources,
            control_ended=true,
          ) {
      report("consumer-release-pending", [
        ("request_cid", order[index]),
        ("reason", "owned-cleanup"),
      ])
      @slot.native_wait_milliseconds(250)
    }
  }
  if order.length() > 1 {
    let state = @site.site_status(environment.site)
    report("retained-holder-settled", [
      ("active_operations", state[2].to_string()),
      ("active_transfers", state[3].to_string()),
      ("holdings", state[4].to_string()),
      ("cleanup_responsibilities", state[5].to_string()),
      ("held_bytes", state[6].to_string()),
      ("reserved_retention_bytes", state[7].to_string()),
      ("reserved_execution_bytes", state[8].to_string()),
    ])
  }
  // The caller retains the same resources for checked Host -> ordinary ->
  // environment/process-hold -> slot closure. No close result is discarded here.
}

///|
/// Called only after the exact consumer Owner has closed its borrow/Runtime,
/// the caller's untransferred bundle holding is returned, and the receiver
/// holding Owner has confirmed reclamation. A durable exclusive start claim
/// forbids the unstarted path; its physical execution needs Runtime recovery.
/// Save both shared release transitions before retiring the relay obligation.
fn confirm_unstarted_consumer_cleanup(
  journal : @journal.Journal,
  request : @remote.DispatchRequest,
) -> Bool {
  let record = match journal.require(request) {
    Ok(value) => value
    Err(_) => return false
  }
  let codes = @remote.dispatch_record_state_codes(record)
  if codes[2] == 2 &&
    (codes[0] == 3 || codes[0] == 4 || codes[0] == 5) &&
    codes[3] == 0 &&
    codes[4] == 0 {
    return true
  }
  if codes[0] != 5 || codes[1] != 0 || codes[3] != 0 || codes[4] != 0 {
    return false
  }
  match journal.start_claimant(request) {
    Ok(None) => ()
    _ => return false
  }
  if codes[2] == 0 {
    let transition = match @remote.prepare_begin_remote_release(record) {
      Ok(value) => value
      Err(_) => return false
    }
    if journal.commit_transition(transition) is Err(_) {
      return false
    }
  }
  let current = match journal.require(request) {
    Ok(value) => value
    Err(_) => return false
  }
  let transition = match @remote.prepare_confirm_remote_release(current) {
    Ok(value) => value
    Err(_) => return false
  }
  journal.commit_transition(transition) is Ok(_)
}

///|
/// Retain acquisition responsibility when execution failed before Runtime
/// custody, or when Runtime already confirmed close. An absent exact holding
/// is idempotent; persistence failure keeps the same binding for retry.
fn close_untransferred_consumer_binding(
  execution : @resident_host.ResidentExecution,
  holding : Ref[@bundle.NativeActiveRuntimeBinding?],
) -> Unit {
  while holding.val is Some(binding) {
    match
      execution.bundles.release(
        @bundle.native_active_runtime_process_hold_id(binding),
      ) {
      Ok(_) => holding.val = None
      Err(_) => {
        report("consumer-release-pending", [("reason", "bundle-holding")])
        @slot.native_wait_milliseconds(250)
      }
    }
  }
}

///|
/// Release the output and reclaim its payloads, retrying each step with a
/// bounded backoff until it is confirmed. `injected_release_failures` is an
/// acceptance test hook that fails that many release attempts first.
fn settle_holder_cleanup(
  runtime : @runtime.NativeRemoteRuntime,
  request : @remote.DispatchRequest,
  journal : @journal.Journal,
  store : @publication_store.Store,
  failed_cleanups : Array[@resident_host.ResidentOutputIssue],
  payloads : Array[@payload.PublicationPayloadRequest],
  injected_release_failures : Int,
  checkpoint : (String) -> Unit,
  close_store? : Bool = true,
) -> Unit {
  let identity = @remote.dispatch_request_identity(request)
  let mut wait_ms = 50
  let next_wait = fn(current : Int) {
    if current * 2 > 5000 {
      5000
    } else {
      current * 2
    }
  }
  // Readers and sources a failed output kept are stopped first: the output
  // cannot be released while they are open.
  for issue in failed_cleanups {
    wait_ms = 50
    while !@resident_host.retry_resident_output_cleanup(issue) {
      report("cleanup-pending", [("step", "output"), ("request_cid", identity)])
      @slot.native_wait_milliseconds(wait_ms)
      wait_ms = next_wait(wait_ms)
    }
  }
  wait_ms = 50
  let mut injected = injected_release_failures
  let mut attempts = 0
  while true {
    attempts += 1
    let released = if injected > 0 {
      injected -= 1
      false
    } else {
      match runtime.release(request) {
        Ok(true) => true
        _ => !runtime.retains_dispatch_resources()
      }
    }
    if released {
      break
    }
    report("cleanup-pending", [
      ("step", "release"),
      ("request_cid", identity),
      ("attempt", attempts.to_string()),
    ])
    @slot.native_wait_milliseconds(wait_ms)
    wait_ms = next_wait(wait_ms)
  }
  for payload in payloads {
    wait_ms = 50
    attempts = 0
    while true {
      attempts += 1
      // The intent is completed only after the Store confirmed the reclaim;
      // a reclaim that is already done is confirmed again at no cost.
      let done = match @resident_host.reclaim_resident_payload(store, payload) {
        Ok(true) => {
          checkpoint("reclaimed")
          @resident_host.complete_resident_output_intent(journal, payload).map(_ => {
            true
          })
        }
        Ok(false) => Ok(false)
        Err(issue) => Err(issue)
      }
      match done {
        Ok(true) => break
        _ => {
          report("cleanup-pending", [
            ("step", "payload"),
            ("request_cid", identity),
            ("attempt", attempts.to_string()),
          ])
          @slot.native_wait_milliseconds(wait_ms)
          wait_ms = next_wait(wait_ms)
        }
      }
    }
  }
  wait_ms = 50
  while true {
    match runtime.close() {
      Ok(_) => break
      Err(_) => {
        report("cleanup-pending", [
          ("step", "runtime"),
          ("request_cid", identity),
        ])
        @slot.native_wait_milliseconds(wait_ms)
        wait_ms = next_wait(wait_ms)
      }
    }
  }
  wait_ms = 50
  while close_store {
    match store.close() {
      Ok(_) => break
      Err(_) => {
        report("cleanup-pending", [("step", "store"), ("request_cid", identity)])
        @slot.native_wait_milliseconds(wait_ms)
        wait_ms = next_wait(wait_ms)
      }
    }
  }
  report("holder-released", [
    ("request_cid", identity),
    ("payloads", payloads.length().to_string()),
  ])
}

///|
fn run_holder(
  matches : @argparse.Matches,
  entry : ResidentInitialControl,
  holder : @argparse.Matches,
) -> HolderCommandClose raise CommandStop {
  // Validate the optional retained profile before acquiring Site custody.
  let retained_delegation = retained_input_delegation(matches)
  let retained_engine_bytes = match retained_delegation {
    None => 0L
    Some(_) => required_int64(matches, "retained-consumer-engine-bytes")
  }
  // A holder that cannot confirm it holds the named slot must not claim.
  let slot = match
    @slot.inherited_native_executor_slot(required(matches, "executor-slot")) {
    Ok(value) => value
    Err(_) => stop("executor slot is not held by this holder")
  }
  let claimant = required(holder, "claimant")
  let attempt = required(holder, "attempt")
  if slot.verify_current_hold() != Ok(()) {
    stop("completed holder current slot unavailable")
  }
  let inspection = match
    fresh_journal(open_control_environment(matches, entry)) {
    Some(value) => value
    None => stop("holder saved journal unavailable")
  }
  let saved_claimant = @resident_host.resident_completed_holder_claimant(
    inspection,
    run_admission(matches),
    delegation(matches, budget(matches)),
    required_int(matches, "site-generation"),
    attempt,
    start_timestamp(matches),
  )
  let selected_process_hold = match saved_claimant {
    Ok(Some(value)) =>
      @resident_host.resident_holder_process_hold_identity(
        inspection,
        run_admission(matches),
        attempt,
        value,
      )
    Ok(None) => Ok("runtime-process:resident-holder:" + claimant)
    Err(issue) => Err(issue)
  }
  if !inspection.close() {
    stop("holder saved journal close pending")
  }
  let process_hold_identity = match selected_process_hold {
    Ok(value) => value
    Err(issue) => {
      report("holder-restoration-refused", [("reason", host_code(issue))])
      stop("holder saved completion unavailable")
    }
  }
  let environment = match
    open_site_environment(
      matches,
      // The actual exclusive slot confirms the old process has stopped. The
      // journal selects its exact holding; retain is idempotent and Runtime
      // returns this holding only after its physical cleanup completes.
       process_hold_identity, entry,
    ) {
    Ok(value) => value
    Err(original) => return finish_failed_site_environment_open(original, slot)
  }
  // The installed runtime must be the one the Site delegates.
  let (registration, revision, strategy) = @bundle.native_active_runtime_connector_scope(
    environment.active_runtime,
  )
  if environment.runtime_bundle_cid != required(matches, "runtime-bundle-cid") ||
    registration != required(matches, "connector-registration") ||
    revision != required(matches, "connector-revision") ||
    strategy != required(matches, "strategy-revision") {
    return finish_unopened_holder_cleanup(
      environment, slot, "installed runtime differs from the Site delegation",
    )
  }
  let max_file_bytes = required_int64(matches, "max-file-bytes")
  let values_root = required(matches, "engine-root")
  let registry_body = load_text(values_root, "registry.json", max_file_bytes)
  let values_body = load_text(values_root, "values.json", max_file_bytes)
  let output_bytes = required_int64(matches, "max-output-bytes")
  let source = source_configuration(matches, values_root, max_file_bytes)
  let fragment_body = source.map(source => source.fragment_contract_body)
  let installed_contracts = match
    @local_values.prepare_installed_sequence_contracts(
      registry_body,
      values_body,
      fragment_body,
      None,
    ) {
    Ok(value) => value
    Err(_) =>
      return finish_unopened_holder_cleanup(
        environment, slot, "installed sequence contracts unavailable",
      )
  }
  let execution : @resident_host.ResidentExecution = {
    source,
    site: environment.site,
    active_runtime: environment.active_runtime,
    operation_capability_cid: required(matches, "operation-capability-cid"),
    issuer_capability_cid: required(matches, "issuer-capability-cid"),
    bundles: environment.bundles,
    budgets: [budget(matches)],
    installed_contracts,
    values_body,
    fixed_ms: 1L,
    per_row_ms: 0L,
    per_wire_byte_ms: 0L,
    per_pair_ms: 0L,
    limits: {
      finalization_quantum: 16,
      max_finalization_rounds: 10000,
      row_decode: {
        max_bytes: 65536,
        max_nodes: 4096,
        max_depth: 32,
        max_text_bytes: 65536,
      },
      bridge_max_entries: 1000,
      bridge_max_name_bytes: 100000,
      output: {
        output_export: {
          max_result_fields: 256,
          max_result_mapping_work: 100000,
          max_result_order_work: 100000,
          max_result_workspace_entries: 100000,
          max_rows: 100000,
          values: {
            max_nodes: 100000,
            max_text_bytes: 1048576,
            max_depth: 32,
            max_work: 1000000,
          },
          payload_wire: {
            max_columns: 256,
            max_order_work: 100000,
            max_bytes: output_bytes.to_int(),
            max_nodes: 1000000,
            max_depth: 32,
          },
          logical_wire: {
            max_columns: 256,
            max_order_work: 100000,
            max_bytes: output_bytes.to_int(),
            max_nodes: 1000000,
            max_depth: 32,
          },
          schema: {
            max_fields: 256,
            max_bytes: 100000,
            max_nodes: 100000,
            max_depth: 32,
          },
          max_batch_bytes: 65536,
        },
        max_manifest_bytes: 65536,
        max_retained_bytes: output_bytes,
      },
    },
  }
  let consumer_configuration = match retained_delegation {
    None => None
    Some(_) => {
      let configured = match execution.source {
        Some(source) =>
          retained_consumer_configuration(
            source, installed_contracts, values_body, retained_engine_bytes,
          )
        None => None
      }
      guard configured is Some(profile) else {
        return finish_unopened_holder_cleanup(
          environment, slot, "retained consumer bounded profile unavailable",
        )
      }
      Some(profile)
    }
  }
  // Acceptance evidence only: record each executor entry, and optionally
  // hold the slot for a while after it so process tests can act meanwhile.
  let entry_log = optional(matches, "executor-entry-log")
  // With a named pause point the executor entry does not pause.
  let pause_ms = if required(matches, "holder-pause-at") == "none" {
    required_int(matches, "holder-pause-ms")
  } else {
    0
  }
  let observer = match entry_log {
    Some(path) =>
      Some(fn(key : String) -> Bool {
        let recorded = @slot.native_append_evidence_line(
          path,
          claimant + " " + key,
        )
        if recorded && pause_ms > 0 {
          @slot.native_wait_milliseconds(pause_ms)
        }
        recorded
      })
    None => None
  }
  // Output setup precedes execution/claim, but an acquisition failure can
  // still own physical cleanup. Return that exact responsibility to the
  // existing holder lifetime; it never proves a start or release outcome.
  let resources = match
    open_holder_output_resources(matches, environment.sqlite_library) {
    Ok(value) => value
    Err(HolderOutputSetupRefused(issue)) => {
      // No output object was acquired, but the original environment/slot still
      // need their checked cleanup. Do not discard those existing Owners.
      retain_partial_holder_output_setup(
        new_holder_partial_output_resources(),
        environment,
        slot,
        issue,
      )
      return HolderCommandFailed(None, issue)
    }
    Err(HolderOutputSetupPending(original, issue)) => {
      retain_partial_holder_output_setup(original, environment, slot, issue)
      return HolderCommandFailed(None, issue)
    }
  }
  // Read original journal state before installing new Host settings. A failed
  // permission installation cannot block existing settlement/cleanup custody.
  let (saved_completion, proven_unstarted) = match
    environment.journal.dispatch_envelope(attempt) {
    Ok(Some(body)) =>
      match @remote.admit_remote_poll_dispatch_json(body) {
        Ok(dispatch) =>
          match
            environment.journal.require(
              @remote.remote_poll_dispatch_request(dispatch),
            ) {
            Ok(record) => {
              let state = @remote.dispatch_record_state_codes(record)[0]
              (state == 3, state == 0)
            }
            Err(_) => (false, false)
          }
        Err(_) => (false, false)
      }
    _ => (false, false)
  }
  ignore(
    load_holder_effect_host_operator(matches, resources, environment, slot),
  ) catch {
    CommandStop(issue) => {
      if proven_unstarted {
        // Failed preparation may retain original physical input cleanup.
        // Return it through the existing cleanup lifetime before any restore
        // or execution. Saved Run/Journal facts are not reclassified or erased.
        let (operation, failure) = finish_holder_cleanup_lifetime(
          resources, environment, slot, issue,
        )
        return HolderCommandFailed(operation, failure)
      }
      // Deny evidence access while retaining the original journal and passing
      // existing work to its normal restoration/unknown/cleanup Owners. This
      // is not a successful installation or permission to restart Source.
      report("effect-host-account-installation-failed", [
        ("reason", "operator-input"),
      ])
      ()
    }
  }
  let effect_host_operator = resources.effect_host_installation
  // A Provider grant binds the captured invocation, including actual Source
  // observation times. It is installed on the first exact Resume, not made a
  // prerequisite of the independently authorized Source start claim.
  let effect_resume : Ref[HolderEffectResumeInstallation?] = Ref(None)
  holder_checkpoint(resources)("before-start")
  let start_checks = [0]
  let holder_delegation = delegation(matches, budget(matches))
  let effect_producer : Ref[@resident_host.ResidentEffectProducerExecuted?] = Ref(
    None,
  )
  let result = if saved_completion {
    restore_holder_attempt(
      matches, environment, execution, resources, slot, attempt,
    ).map_err(issue => HolderExecutionFailure::Ordinary(issue))
  } else {
    execute_holder_source(
      environment.journal,
      execution,
      run_admission(matches),
      consumer_configuration,
      () => holder_delegation,
      attempt,
      claimant,
      // Read the holder clock at each authority check, not before rebuilding
      // materials/claiming. An invalid clock is fail-closed, without throwing
      // past the runtime's cleanup owner.
      () => {
        start_checks[0] += 1
        if start_checks[0] == 2 {
          // This point is reached by the runtime's mandatory barrier after
          // claim/Running persistence, not by the executor evidence observer.
          holder_checkpoint(resources)("before-physical-start")
        }
        start_timestamp(matches)
      },
      observer,
      event => {
        if event is @resident_host.AcquisitionEntered {
          // A physical acquisition boundary, separate from executor entry
          // and the later durable successful Source observation.
          report("source-acquisition-entered", [("attempt", attempt)])
        }
        true
      },
      retain_effect_producer=owner => effect_producer.val = Some(owner),
    )
  }
  let code = match result {
    Ok(executed) => {
      report(if saved_completion { "holder-restored" } else { "executed" }, [
        ("request_cid", executed.completion.dispatch_request_cid),
        ("revision", executed.completion.revision.to_string()),
      ])
      if !saved_completion && executed.result_definition_cid is None {
        // Deterministic interruption after the original completed producer is
        // durable. A restored holder never repeats this acquisition boundary.
        holder_checkpoint(resources)("completed-producer")
      }
      // The output stays owned by this holder's runtime until the
      // Coordinator releases it; the holder serves its output meanwhile.
      serve_holder_output(
        // These deterministic interruption points target the original holder.
        // The reconstructed holder must resume the same custody, not be
        // repeatedly killed at the same historical boundary.
        if saved_completion &&
          (
            resources.kill_at == "retained-transfer-pending" ||
            resources.kill_at == "retained-receiver-committed" ||
            resources.kill_at == "retained-consumer-borrowed"
          ) {
          { ..resources, kill_at: "none", pause_at: "none", }
        } else {
          resources
        },
        environment,
        executed,
        run_admission(matches),
        () => start_timestamp(matches),
        execution,
        consumer_configuration,
        delegation(matches, budget(matches)),
        claimant,
        observer,
        () => slot.verify_current_hold() == Ok(()),
        effect_producer=effect_producer.val,
        effect_host_operator~,
        effect_catalog_review=original => {
          open_holder_effect_review_installation(matches, original)
        },
        effect_resume_installation=request => {
          if effect_resume.val is None {
            let installed = open_holder_effect_resume_installation(
              matches,
              entry,
              environment.sqlite_library,
              resources,
              request,
            ) catch {
              CommandStop(_) => {
                // Keep the existing task and Review responsibility. Missing
                // or invalid Provider installation cannot restart computation.
                report("effect-resume-pending", [
                  ("request_cid", @remote.dispatch_request_identity(request)),
                  ("reason", "provider-installation"),
                ])
                None
              }
            }
            effect_resume.val = installed
          }
          match effect_resume.val {
            Some(owner) => owner.for_dispatch(request)
            None => None
          }
        },
      )
      0
    }
    Err(failure) => {
      let issue = failure.issue()
      report("execute-failed", [("reason", holder_issue_code(issue))])
      // A runtime whose cleanup is not confirmed is kept: only its close is
      // retried, with the slot still held, and nothing is started again.
      if failure is Effect({ cleanup_issue: Some(cleanup), .. }) {
        report("cleanup-pending", [
          ("step", "effect-source-after-failure"),
          ("reason", runtime_code(cleanup)),
        ])
      }
      match failure.runtime() {
        Some(runtime) => {
          let mut wait_ms = 50
          let mut attempts = 0
          while true {
            match runtime.close() {
              Ok(_) => break
              Err(cleanup) => {
                attempts += 1
                report("cleanup-pending", [
                  ("step", "runtime-after-failure"),
                  ("reason", runtime_code(cleanup)),
                  ("attempt", attempts.to_string()),
                ])
                @slot.native_wait_milliseconds(wait_ms)
                wait_ms = if wait_ms * 2 > 5000 { 5000 } else { wait_ms * 2 }
              }
            }
          }
          report("runtime-cleaned", [
            ("reason", holder_issue_code(issue)),
            ("attempts", attempts.to_string()),
          ])
        }
        None => ()
      }
      match issue {
        Ordinary(Runtime(@runtime.StartClaimLost(_)))
        | Ordinary(Runtime(@runtime.StartCancelled))
        | Effect(Host(Runtime(@runtime.StartClaimLost(_))))
        | Effect(Host(Runtime(@runtime.StartCancelled))) => 2
        _ => 1
      }
    }
  }
  if effect_resume.val is Some(owner) {
    let mut wait_ms = 50
    while !owner.close() {
      report("cleanup-pending", [("step", "effect-resume-installation")])
      @slot.native_wait_milliseconds(wait_ms)
      wait_ms = holder_effect_installation_backoff(wait_ms)
    }
  }
  let failure = "execute exited with " + code.to_string()
  let (operation, failure) = finish_holder_cleanup_lifetime(
    resources, environment, slot, failure,
  )
  if code != 0 {
    HolderCommandFailed(operation, failure)
  } else {
    HolderCommandClosed(operation)
  }
}

///|
/// A recreated holder reuses its saved completion, never the start path.
/// Keep one Runtime across pending acquisition; only confirmed cleanup can
/// discharge it. This loop does not release the exclusive slot or admit work.
fn restore_holder_attempt(
  matches : @argparse.Matches,
  environment : SiteEnvironment,
  execution : @resident_host.ResidentExecution,
  resources : HolderOutputResources,
  slot : @slot.NativeExecutorSlot,
  attempt : String,
) -> Result[
  @resident_host.ResidentExecuted,
  @resident_host.ResidentExecutionFailure,
] raise CommandStop {
  let owner = match
    @resident_host.prepare_resident_completed_attempt(
      environment.journal,
      execution,
      run_admission(matches),
      delegation(matches, budget(matches)),
      attempt,
      () => start_timestamp(matches),
      () => slot.verify_current_hold() == Ok(()),
      retained_cleanup=Some(
        (
          resources.transfer_journal,
          resources.retained_root,
          resources.retained_max_bytes,
        ),
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut wait_ms = 50
  while true {
    match owner.advance() {
      @resident_host.ResidentCompletedReady(value) => return Ok(value)
      @resident_host.ResidentCompletedRefused(issue) =>
        return Err({ issue, pending_runtime: Some(owner.runtime()), })
      @resident_host.ResidentCompletedPending(issue) => {
        report("holder-restoration-pending", [("reason", host_code(issue))])
        if owner.runtime().cleanup_pending() {
          return Err({ issue, pending_runtime: Some(owner.runtime()), })
        }
        @slot.native_wait_milliseconds(wait_ms)
        wait_ms = if wait_ms * 2 > 5000 { 5000 } else { wait_ms * 2 }
      }
    }
  } nobreak {
    abort("restoration loop ended without an ownership result")
  }
}

///|
/// One explicitly selected saved dispatch; no poll, materials preparation,
/// execution claim, or Output replay is reachable from this operation.
/// After the original Output ACK, recover only this dispatch's payloads through
/// their existing cleanup Owner. Other attempts' custody still refuses release.
/// An unconfirmed observation can be sent again on the next call.
fn recover_release_command(
  matches : @argparse.Matches,
  entry : ResidentInitialControl,
  child : @argparse.Matches,
) -> Unit raise CommandStop {
  let environment = open_control_environment(matches, entry)
  let request = match
    accepted_request(environment, required(child, "attempt"), [0]) {
    Some(value) => value
    None => stop("release recovery saved dispatch unavailable")
  }
  let identity = @remote.dispatch_request_identity(request)
  if identity != required(child, "expect-dispatch") {
    report("release-recovery-refused", [("reason", "dispatch-mismatch")])
    stop("release recovery dispatch mismatch")
  }
  if @resident.check_resident_dispatch_delegation(
      delegation(matches, budget(matches)),
      request,
      environment.site_generation,
    )
    is Err(_) {
    stop("release recovery current scope refused")
  }
  // Read bounded original evidence before taking physical cleanup ownership.
  let recorded_source = optional(child, "publication-custody-root").map(
    load_recorded_publication,
  )
  let recorded_consumer = if recorded_source is Some(_) {
    Some(
      (
        required(child, "consumer-attempt"),
        required(child, "expect-consumer-dispatch"),
      ),
    )
  } else {
    None
  }
  let completed_input_producer = optional(
    child, "completed-input-producer-attempt",
  ).map(attempt => (attempt, required(child, "expect-input-producer-dispatch")))
  if completed_input_producer is Some(_) && recorded_source is Some(_) {
    stop("release recovery conflicting cleanup roles")
  }
  let publication_settings : ControlOrphanStoreSettings = {
    root: required(matches, "publication-root"),
    authority_cid: required(matches, "publication-authority-cid"),
    capacity_bytes: required_int64(matches, "publication-capacity-bytes"),
  }
  let observation_url = required(matches, "observation-url")
  let slot = match
    @slot.open_native_executor_slot(required(matches, "executor-slot")) {
    Ok(value) => value
    Err(_) => stop("release recovery slot unavailable")
  }
  match acquire_release_recovery_slot_with_custody(slot, identity) {
    Ok(_) => ()
    Err(original) => {
      finish_failed_release_recovery_open(original)
      stop(original.failure)
    }
  }
  let owner = open_release_recovery(matches, environment, slot, identity)
  owner.recorded_source = recorded_source
  owner.recorded_consumer = recorded_consumer
  owner.completed_input_producer = completed_input_producer
  let retained : Ref[StoppedReleaseRecovery?] = Ref(Some(owner))
  let resources = new_holder_partial_output_resources()
  let failure = try {
    let mut cursor = ""
    while true {
      match owner.journal.output_report_after(cursor) {
        Ok(Some((key, custody, state))) => {
          cursor = key
          if @remote.dispatch_request_identity(
              @remote.remote_output_report_custody_dispatch(custody),
            ) ==
            identity &&
            !(state is Some(@remote.RemoteOutputReportReply::Accepted)) {
            stop("release recovery Output acknowledgement pending")
          }
        }
        Ok(None) => break
        Err(_) => stop("release recovery Output acknowledgement unreadable")
      }
    }
    match
      @resident_host.begin_resident_output_release(
        owner.journal,
        delegation(matches, budget(matches)),
        environment.site_generation,
        request,
      ) {
      Ok(_) => ()
      // Preserve the existing cancelled/unstarted cleanup dispositions.
      Err(@resident_host.OutputUnavailable) => ()
      Err(_) => stop("release recovery release persistence unconfirmed")
    }
    let store = match
      open_release_command_store(environment, resources, publication_settings) {
      Some(original) => original
      None => stop("release recovery publication Store unavailable")
    }
    let reclaimed = @resident_host.reclaim_resident_dispatch_output_intents(
      owner.journal,
      store,
      request,
    )
    let intents_empty = match owner.journal.pending_output_intents() {
      Ok(values) => values.is_empty()
      Err(_) => false
    }
    let empty = match store.capacity_usage() {
      Ok(value) => value.reserved_bytes == 0L && value.reserved_objects == 0L
      Err(_) => false
    }
    let closed = store.close()
    if closed is Ok(_) {
      resources.store = None
    }
    if !(reclaimed is Ok(0)) || !intents_empty || !empty || !(closed is Ok(_)) {
      stop("release recovery publication custody unconfirmed")
    }
    if !recover_stopped_release(matches, environment, request, retained, Ref(0)) {
      stop("release recovery pending")
    }
    None
  } catch {
    CommandStop(issue) => Some(issue)
  }
  if retained.val is Some(same) {
    // The same ready Owner survives every fallible body operation. Checked
    // handle cleanup never selects a terminal Run action or masks failure.
    retain_partial_output_recovery_setup(
      resources,
      same,
      same.slot,
      failure.unwrap_or("release recovery handle retirement"),
    )
    retained.val = None
  }
  if failure is Some(issue) {
    stop(issue)
  }
  let client = control_client(matches, entry)
  guard fresh_journal(environment) is Some(journal) else {
    stop("release recovery observation journal unavailable")
  }
  let observed = @client.acknowledge_status(
    journal, client, observation_url, request,
  )
  retain_control_replay_journal_close(journal)
  // The actual ready/failed Client stays on the same initial entry through
  // its existing checked Library/Read retirement; no close result is discarded.
  match observed {
    Ok(Some(record)) =>
      report("release-recovery-observed", [
        ("request_cid", identity),
        ("revision", @remote.dispatch_record_revision(record).to_string()),
      ])
    _ => stop("release recovery observation unconfirmed")
  }
}

///|
/// The signed installed bundle remains the execution identity. Maintenance
/// checks its current active scope but neither acquires nor executes it.
fn saved_output_bundle_current(
  bundles : @bundle.NativeRuntimeBundleStore,
  delegated : @resident.ResidentSiteDelegation,
  target : String,
) -> Bool {
  guard bundles.active() is Ok(Some(snapshot)) &&
    !snapshot.reclaim_pending &&
    snapshot.runtime_bundle_cid == delegated.runtime_bundle_cid else {
    return false
  }
  guard @bundle_protocol.admit_bundle_manifest_json(
      snapshot.manifest_json,
      snapshot.runtime_bundle_cid,
    )
    is Ok(manifest) else {
    return false
  }
  let fields = @bundle_protocol.bundle_manifest_projection(manifest)
  fields[4] == target &&
  fields[7] == delegated.connector_registration &&
  fields[8] == delegated.connector_revision &&
  fields[9] == delegated.strategy_revision
}

///|
/// Continue one original sealed Output after its holder has stopped. This
/// command never acquires Source, enters an executor or reuploads payload.
fn recover_output_command(
  matches : @argparse.Matches,
  entry : ResidentInitialControl,
  child : @argparse.Matches,
) -> Unit raise CommandStop {
  let attempt = required(child, "attempt")
  let expected = required(child, "expect-dispatch")
  let intent = required(child, "intent-cid")
  let recorded = load_recorded_publication(
    required(child, "publication-custody-root"),
  )
  let delegated = delegation(matches, budget(matches))
  let max_transfers = required_int(matches, "max-transfers")
  let target = required(matches, "target-triple")
  let environment = open_control_environment(matches, entry)
  let slot = match
    @slot.open_native_executor_slot(required(matches, "executor-slot")) {
    Ok(value) => value
    Err(_) => stop("Output recovery slot unavailable")
  }
  match acquire_release_recovery_slot_with_custody(slot, expected) {
    Ok(_) => ()
    Err(original) => {
      finish_failed_release_recovery_open(original)
      stop(original.failure)
    }
  }
  // Reuse the maintenance owner: it verifies saved custody without selecting
  // an executor or claiming that this tool is the original runtime component.
  let owner = open_release_recovery(matches, environment, slot, expected)
  let resources = open_holder_output_resources(
    matches,
    environment.sqlite_library,
  )
  match resources {
    Err(HolderOutputSetupRefused(issue)) => {
      retain_partial_output_recovery_setup(
        new_holder_partial_output_resources(),
        owner,
        slot,
        issue,
      )
      stop(issue)
    }
    Err(HolderOutputSetupPending(original, issue)) => {
      retain_partial_output_recovery_setup(original, owner, slot, issue)
      stop(issue)
    }
    Ok(_) => ()
  }
  let primary : String? = match resources {
    Err(_) => Some("output-resources-unavailable")
    Ok(resources) =>
      try {
        if owner.bundles.verify(environment.runtime_bundle_cid) is Err(_) {
          stop("installed-runtime-unconfirmed")
        }
        let site = match
          @site.create_site(
            environment.site_key,
            environment.site_generation,
            environment.runtime_bundle_cid,
            environment.max_operations,
            environment.max_transfers,
            environment.max_bytes,
            environment.max_bytes,
          ) {
          Some(value) => value
          None => stop("invalid-current-site")
        }
        let envelope = match owner.journal.dispatch_envelope(attempt) {
          Ok(Some(value)) => value
          _ => stop("saved-dispatch-unavailable")
        }
        let dispatch = match @remote.admit_remote_poll_dispatch_json(envelope) {
          Ok(value) => value
          _ => stop("saved-dispatch-invalid")
        }
        if @remote.dispatch_request_identity(
            @remote.remote_poll_dispatch_request(dispatch),
          ) !=
          expected {
          stop("dispatch-mismatch")
        }
        let current = () => {
          slot.verify_current_hold() == Ok(()) &&
          saved_output_bundle_current(owner.bundles, delegated, target)
        }
        let saved = match
          @resident_host.prepare_resident_recorded_output(
            owner.journal,
            site,
            recorded,
            delegated,
            attempt,
            intent,
            () => start_timestamp(matches),
            current,
          ) {
          Ok(value) => value
          Err(Refused(TaskMaterialsRejected(issue))) => {
            report("output-recovery-materials-refused", [
              ("stage", saved_output_materials_stage(issue)),
              ("request_cid", expected),
            ])
            stop("refused-task-materials-rejected")
          }
          Err(issue) => stop(host_code(issue))
        }
        let delivered = saved.recover(
          resources.store,
          resources.transfer_journal,
          resources.transfer,
          resources.destination_origin,
          max_transfers,
        )
        match delivered.result {
          Ok(_) => ()
          Err(issue) => {
            if !@resident_host.retry_resident_output_cleanup(issue) {
              report("output-recovery-cleanup-pending", [
                ("step", "source"),
                ("request_cid", expected),
              ])
            }
            stop(output_code(issue))
          }
        }
        // The existing client sends only the durable original and persists
        // the report-CID-bound ACK. A lost reply leaves that same custody.
        if !saved.is_current() {
          stop("current-owner-unconfirmed")
        }
        match
          @client.acknowledge_retained_output_report(
            owner.journal,
            resources.control,
            resources.observation_url,
            intent,
          ) {
          Ok(_) => ()
          Err(_) => stop("output-ack-pending")
        }
        None
      } catch {
        CommandStop(issue) => Some(issue)
      }
  }
  // Keep the same completed-setup originals in the existing recovery lifetime.
  // Pending child/Library cleanup must precede journal, Bundle and slot close.
  match resources {
    Ok(value) => {
      let original = new_holder_partial_output_resources()
      original.retained_root = value.retained_root
      original.control = Some(value.control)
      original.control_library = Some(value.control_library)
      original.transfer = Some(value.transfer)
      original.transfer_library = Some(value.transfer_library)
      original.store = Some(value.store)
      original.transfer_journal = Some(value.transfer_journal)
      retain_partial_output_recovery_setup(
        original,
        owner,
        slot,
        match primary {
          Some(issue) => issue
          None => "Output recovery resource retirement pending"
        },
      )
    }
    Err(_) => ()
  }
  match primary {
    Some(issue) => {
      report("output-recovery-pending", [
        ("reason", issue),
        ("request_cid", expected),
      ])
      stop("Output recovery pending")
    }
    None =>
      report("output-recovery-acknowledged", [
        ("request_cid", expected),
        ("intent_cid", intent),
      ])
  }
}

///|
fn command() -> @argparse.Command {
  let global = fn(name : String) { @argparse.OptionArg(name, global=true) }
  let defaulted = fn(name : String, value : String) {
    @argparse.OptionArg(name, default_values=[value], global=true)
  }
  @argparse.Command(
    "actql-native-remote-resident-site",
    about="Run an outbound-only resident ActQL Site",
    version="0.1",
    subcommand_required=true,
    options=[
      global("sqlite-library"),
      global("crypto-library"),
      global("http-library"),
      global("journal"),
      global("runtime-root"),
      global("bundle-issuer"),
      global("bundle-key-id"),
      global("bundle-public-key-root"),
      global("bundle-public-key-file"),
      global("target-triple"),
      global("component-cid"),
      global("site-key"),
      global("site-generation"),
      global("executor-slot"),
      global("ca"),
      global("control-bearer-file"),
      global("control-cert"),
      global("control-key"),
      global("transfer-bearer-file"),
      global("transfer-cert"),
      global("transfer-key"),
      global("transfer-origin"),
      global("transfer-journal"),
      global("publication-root"),
      global("publication-authority-cid"),
      global("poll-url"),
      global("observation-url"),
      global("coordinator-authority"),
      global("bundle-custody-workspace"),
      global("bundle-custody-authority-scope-cid"),
      global("bundle-custody-environment"),
      global("runtime-bundle-cid"),
      global("connector-registration"),
      global("connector-revision"),
      global("strategy-revision"),
      global("operation-capability-cid"),
      global("retained-input-root"),
      global("retained-consumer-engine-bytes"),
      global("retained-source-grant-cid"),
      global("retained-destination-grant-cid"),
      global("retained-route-capability-cid"),
      global("issuer-capability-cid"),
      global("budget-retained-bytes"),
      global("budget-execution-bytes"),
      global("engine-root"),
      global("effect-resume-root"),
      global("effect-review-root"),
      global("effect-host-account-root"),
      global("effect-catalog-root"),
      global("duckdb-library"),
      global("source-ref"),
      global("source-contract-cid"),
      global("source-database"),
      global("source-schema"),
      global("source-table"),
      global("executor-entry-log"),
      global("test-clock-root"),
      defaulted("queue-capacity", "4"),
      defaulted("max-operations", "4"),
      defaulted("max-transfers", "4"),
      defaulted("max-bytes", "268435456"),
      defaulted("max-file-bytes", "1048576"),
      defaulted("max-record-bytes", "1048576"),
      defaulted("max-output-bytes", "1048576"),
      defaulted("max-response-bytes", "1441792"),
      defaulted("connect-timeout-ms", "2000"),
      defaulted("total-timeout-ms", "30000"),
      defaulted("max-polls", "0"),
      defaulted("idle-wait-ms", "250"),
      defaulted("min-backoff-ms", "250"),
      defaulted("max-backoff-ms", "30000"),
      defaulted("shutdown-wait-ms", "30000"),
      defaulted("holder-pause-ms", "0"),
      // Acceptance test hooks only.
      defaulted("holder-release-failures", "0"),
      defaulted("release-recovery-close-failures", "0"),
      defaulted("release-recovery-kill-at", "none"),
      defaulted("holder-result-report-failures", "0"),
      defaulted("holder-kill-at", "none"),
      defaulted("control-report-kill-at", "none"),
      defaulted("control-cancel-kill-at", "none"),
      defaulted("holder-pause-at", "none"),
      defaulted("control-reclaim-failures", "0"),
      defaulted("control-envelope-read-failures", "0"),
      defaulted("publication-capacity-bytes", "268435456"),
    ],
    subcommands=[
      @argparse.Command("run"),
      @argparse.Command("output-reports"),
      @argparse.Command("recover-output", options=[
        @argparse.OptionArg("attempt", required=true),
        @argparse.OptionArg("expect-dispatch", required=true),
        @argparse.OptionArg("intent-cid", required=true),
        @argparse.OptionArg("publication-custody-root", required=true),
      ]),
      @argparse.Command("recover-retained-input", options=[
        @argparse.OptionArg("producer-attempt", required=true),
        @argparse.OptionArg("expect-producer-dispatch", required=true),
        @argparse.OptionArg("consumer-attempt", required=true),
        @argparse.OptionArg("expect-consumer-dispatch", required=true),
      ]),
      @argparse.Command("recover-cancelled-receiver", options=[
        @argparse.OptionArg("producer-attempt", required=true),
        @argparse.OptionArg("expect-producer-dispatch", required=true),
        @argparse.OptionArg("consumer-attempt", required=true),
        @argparse.OptionArg("expect-consumer-dispatch", required=true),
        @argparse.OptionArg("recovery-materials-root", required=true),
        @argparse.OptionArg("publication-custody-root", required=true),
      ]),
      @argparse.Command("recover-source-output", options=[
        @argparse.OptionArg("producer-attempt", required=true),
        @argparse.OptionArg("expect-producer-dispatch", required=true),
        @argparse.OptionArg("consumer-attempt", required=true),
        @argparse.OptionArg("expect-consumer-dispatch", required=true),
        @argparse.OptionArg("publication-custody-root"),
      ]),
      @argparse.Command("recover-release", options=[
        @argparse.OptionArg("attempt", required=true),
        @argparse.OptionArg("expect-dispatch", required=true),
        @argparse.OptionArg("publication-custody-root"),
        @argparse.OptionArg("consumer-attempt"),
        @argparse.OptionArg("expect-consumer-dispatch"),
        @argparse.OptionArg("completed-input-producer-attempt"),
        @argparse.OptionArg("expect-input-producer-dispatch"),
      ]),
      @argparse.Command("retry-output-report", options=[
        @argparse.OptionArg("intent-cid", required=true),
      ]),
      @argparse.Command("execute", options=[
        @argparse.OptionArg("attempt", required=true),
        @argparse.OptionArg("claimant", required=true),
      ]),
    ],
  )
}

///|
fn run_command(
  matches : @argparse.Matches,
  entry : ResidentInitialControl,
) -> HolderTerminalFailure? raise CommandStop {
  match matches.subcommand {
    Some(("run", _)) => run_control(matches, entry)
    Some(("execute", child)) =>
      return finish_holder_command(run_holder(matches, entry, child))
    Some(("recover-output", child)) =>
      recover_output_command(matches, entry, child)
    Some(("recover-retained-input", child)) =>
      recover_retained_input_command(matches, entry, child)
    Some(("recover-cancelled-receiver", child)) =>
      recover_retained_input_command(
        matches,
        entry,
        child,
        cancelled_receiver=true,
      )
    Some(("recover-source-output", child)) =>
      recover_retained_input_command(matches, entry, child, source_output=true)
    Some(("recover-release", child)) =>
      recover_release_command(matches, entry, child)
    Some(("output-reports", _)) => {
      let environment = open_control_environment(matches, entry)
      guard fresh_journal(environment) is Some(journal) else {
        stop("journal unavailable")
      }
      let mut cursor = ""
      while true {
        match journal.output_report_after(cursor) {
          Ok(Some((key, custody, state))) => {
            cursor = key
            let (status, reason) = match state {
              Some(@remote.RemoteOutputReportReply::Accepted) =>
                ("acknowledged", "")
              Some(@remote.RemoteOutputReportReply::Refused(reason)) =>
                ("attention", reason)
              Some(@remote.RemoteOutputReportReply::Retry(reason)) =>
                ("retry-pending", reason)
              None => ("pending", "")
            }
            report("output-report-state", [
              ("intent_cid", key),
              (
                "report_cid",
                @remote.remote_output_result_identity(
                  @remote.remote_output_report_custody_result(custody),
                ),
              ),
              ("state", status),
              ("reason", reason),
            ])
          }
          Ok(None) => break
          Err(_) => {
            retain_control_replay_journal_close(journal)
            stop("report inspection failed")
          }
        }
      }
      retain_control_replay_journal_close(journal)
    }
    Some(("retry-output-report", child)) => {
      let key = required(child, "intent-cid")
      let delegated = delegation(matches, budget(matches))
      let environment = open_control_environment(matches, entry)
      guard fresh_journal(environment) is Some(journal) else {
        stop("journal unavailable")
      }
      let custody = match journal.output_report(key) {
        Ok(value) => value.0
        Err(_) => {
          retain_control_replay_journal_close(journal)
          stop("report unavailable")
        }
      }
      if @resident.check_resident_dispatch_delegation(
          delegated,
          @remote.remote_output_report_custody_dispatch(custody),
          environment.site_generation,
        )
        is Err(_) {
        retain_control_replay_journal_close(journal)
        stop("current report scope refused")
      }
      let result = journal.retry_output_report(key)
      retain_control_replay_journal_close(journal)
      if result is Err(_) {
        stop("report retry rejected")
      }
      report("output-report-retry-enabled", [])
    }
    _ => stop("missing operation")
  }
  None
}

///|
fn run_resident_with_initial_control(control : ResidentInitialControl) -> Bool {
  let succeeded = try {
    control.require_current()
    let matches = command().parse() catch { error => stop(error.to_string()) }
    control.require_current()
    if run_command(matches, control) is Some(terminal) {
      consume_holder_terminal_failure(terminal.operation, terminal.failure)
    }
    true
  } catch {
    CommandStop(issue) => {
      // Consume the managed diagnostic before leaving its original Read.
      let message = @utf8.encode("actql-native-remote-resident-site: " + issue)
      resident_command_failure_ffi(message, message.length())
      false
    }
  }
  // Command environments and their aliases have unwound. The same carrier
  // retains every ready/failed component until its actual close acknowledges;
  // a pending child must keep the parent Read/domain/arena alive.
  while !control.close_libraries() {
    resident_control_diagnostic_ffi(3)
    wait_resident_initial_cleanup()
  }
  succeeded
}

///|
fn main {
  let control = capture_resident_initial_control()
  let ready = try {
    control.acquire()
    control.enter()
    true
  } catch {
    CommandStop(_) => {
      resident_control_diagnostic_ffi(1)
      false
    }
  }
  let succeeded = ready && run_resident_with_initial_control(control)
  while !control.close() {
    resident_control_diagnostic_ffi(2)
    wait_resident_initial_cleanup()
  }
  if succeeded && control.controller_returned {
    if resident_controller_retired_ffi(control.original) != 0 {
      resident_control_exit_failure_ffi()
    }
  }
  if !succeeded {
    resident_control_exit_failure_ffi()
  }
}
