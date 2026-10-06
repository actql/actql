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
  match @bounded_files.read_bounded_text_file(root, name, max_bytes) {
    Ok(value) => value
    Err(_) => stop("failed to read " + name)
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
) -> ControlEnvironment raise CommandStop {
  let sqlite_library = match
    @sqlite.load_library(required(matches, "sqlite-library")) {
    Ok(value) => value
    Err(_) => stop("SQLite library load failed")
  }
  {
    sqlite_library,
    journal_path: required(matches, "journal"),
    max_record_bytes: required_int64(matches, "max-record-bytes"),
    site_key: required(matches, "site-key"),
    site_generation: required_int(matches, "site-generation"),
    runtime_bundle_cid: required(matches, "runtime-bundle-cid"),
    max_operations: required_int(matches, "max-operations"),
    max_transfers: required_int(matches, "max-transfers"),
    max_bytes: required_int64(matches, "max-bytes"),
  }
}

///|
fn open_site_environment(
  matches : @argparse.Matches,
  process_hold_id : String,
) -> SiteEnvironment raise CommandStop {
  let max_file_bytes = required_int64(matches, "max-file-bytes")
  let max_record_bytes = required_int64(matches, "max-record-bytes")
  let max_bytes = required_int64(matches, "max-bytes")
  let target = required(matches, "target-triple")
  let component_cid = required(matches, "component-cid")
  let loaded_component_cid = match
    @process_image.current_executable_cid(max_bytes, 1048576) {
    Ok(value) => value
    Err(_) => stop("resident Site executable identity failed")
  }
  if loaded_component_cid != component_cid {
    report("setup-failed", [("reason", "executable-identity-mismatch")])
    stop("resident Site executable identity mismatch")
  }
  let sqlite_library = match
    @sqlite.load_library(required(matches, "sqlite-library")) {
    Ok(value) => value
    Err(_) => stop("SQLite library load failed")
  }
  let signature_library = match
    @signature.load_library(required(matches, "crypto-library")) {
    Ok(value) => value
    Err(_) => stop("signature library load failed")
  }
  let public_key = load_text(
    required(matches, "bundle-public-key-root"),
    required(matches, "bundle-public-key-file"),
    max_file_bytes,
  )
  let bundles = match
    @bundle.open_runtime_bundle_store(
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
    Err(issue) =>
      stop("runtime bundle Store open failed: " + bundle_issue_code(issue))
  }
  let active = match bundles.active() {
    Ok(Some(value)) => value
    _ => {
      ignore(bundles.close())
      stop("active runtime bundle is missing")
    }
  }
  let active_runtime = match
    bundles.acquire_active_component(
      loaded_component_cid, target, process_hold_id,
    ) {
    Ok(value) => value
    Err(_) => {
      ignore(bundles.close())
      stop("active runtime component verification failed")
    }
  }
  let site = match
    @site.create_site(
      required(matches, "site-key"),
      required_int(matches, "site-generation"),
      active.runtime_bundle_cid,
      required_int(matches, "max-operations"),
      required_int(matches, "max-transfers"),
      max_bytes,
      max_bytes,
    ) {
    Some(value) => value
    None => {
      ignore(bundles.release(process_hold_id))
      ignore(bundles.close())
      stop("invalid execution Site")
    }
  }
  let control = match
    @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1") {
    Ok(value) => value
    Err(_) => {
      ignore(bundles.release(process_hold_id))
      ignore(bundles.close())
      stop("invalid dispatch journal binding")
    }
  }
  let journal = match
    @journal.open_journal(
      sqlite_library,
      required(matches, "journal"),
      max_record_bytes,
      control,
    ) {
    Ok(value) => value
    Err(_) => {
      ignore(bundles.release(process_hold_id))
      ignore(bundles.close())
      stop("dispatch journal open failed")
    }
  }
  {
    bundles,
    active_runtime,
    process_hold_id,
    site,
    journal,
    runtime_bundle_cid: active.runtime_bundle_cid,
    sqlite_library,
  }
}

///|
/// A fresh view of the shared dispatch journal. The holder advances records
/// in its own process, so the control process reads the durable record anew
/// for every operation instead of keeping an in-memory copy.
fn fresh_journal(environment : ControlEnvironment) -> @journal.Journal? {
  guard @site.create_site(
      environment.site_key,
      environment.site_generation,
      environment.runtime_bundle_cid,
      environment.max_operations,
      environment.max_transfers,
      environment.max_bytes,
      environment.max_bytes,
    )
    is Some(site) else {
    return None
  }
  match @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1") {
    Ok(control) =>
      @journal.open_journal(
        environment.sqlite_library,
        environment.journal_path,
        environment.max_record_bytes,
        control,
      ).to_option()
    Err(_) => None
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
fn close_site_environment(environment : SiteEnvironment) -> Unit {
  ignore(environment.journal.close())
  ignore(environment.bundles.release(environment.process_hold_id))
  ignore(environment.bundles.close())
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
) -> @http.Client raise CommandStop {
  let library = match @http.load_library(required(matches, "http-library")) {
    Ok(value) => value
    Err(_) => stop("HTTP library load failed")
  }
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
  match
    library.create_authenticated_client(
      required(matches, "ca"),
      authentication,
      required_int64(matches, "max-response-bytes"),
      required_int(matches, "connect-timeout-ms"),
      required_int(matches, "total-timeout-ms"),
    ) {
    Ok(value) => value
    Err(_) => stop("HTTP client creation failed")
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
  child : @slot.NativeExecutorSlotChild
  channel : @slot.NativeHolderChannel
  attempt : String
  request : @remote.DispatchRequest
  mut next_report_ms : UInt64
}

///|
/// Report the holder's durable record to the Coordinator after it ended. A
/// lost report is retried on the next pass; the journal keeps the record.
fn settle_holder(
  holder : RunningHolder,
  environment : ControlEnvironment,
  client : @http.Client,
  observation_url : String,
) -> Bool {
  guard fresh_journal(environment) is Some(journal) else {
    report("observation-pending", [
      ("attempt", holder.attempt),
      ("reason", "journal-open"),
    ])
    return false
  }
  let observed = @client.acknowledge_status(
    journal,
    client,
    observation_url,
    holder.request,
  )
  ignore(journal.close())
  match observed {
    Ok(Some(record)) => {
      report("holder-settled", [
        ("attempt", holder.attempt),
        ("request_cid", @remote.dispatch_request_identity(holder.request)),
        ("revision", @remote.dispatch_record_revision(record).to_string()),
      ])
      true
    }
    Ok(None) => {
      report("holder-settled", [("attempt", holder.attempt)])
      true
    }
    Err(issue) => {
      report("observation-pending", [
        ("attempt", holder.attempt),
        ("reason", client_code(issue)),
      ])
      false
    }
  }
}

///|
/// Whether an ended holder left its attempt startable. A record that cannot
/// be read counts as startable: starting again is safe, because a holder
/// claims before it executes and a record that can no longer start is not
/// claimed.
fn holder_left_startable(
  environment : ControlEnvironment,
  request : @remote.DispatchRequest,
) -> Bool {
  guard fresh_journal(environment) is Some(journal) else { return true }
  let record = journal.require(request)
  ignore(journal.close())
  match record {
    Ok(value) => @remote.remote_runtime_record_startable(value)
    Err(_) => true
  }
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
  matches : @argparse.Matches,
  environment : ControlEnvironment,
  slot : @slot.NativeExecutorSlot,
  held : @publication_store.Store?,
) -> OrphanReclaim raise CommandStop {
  let publication_root = required(matches, "publication-root")
  let close_held = fn(store : @publication_store.Store) -> OrphanReclaim {
    match store.close() {
      Ok(_) => {
        ignore(slot.close())
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
  guard fresh_journal(environment) is Some(journal) else {
    report("orphan-reclaim-pending", [("reason", "journal-open")])
    return match held {
      Some(store) => close_held(store)
      None => OrphansPending
    }
  }
  let intents = match journal.pending_output_intents() {
    Ok(value) => value
    Err(_) => {
      ignore(journal.close())
      report("orphan-reclaim-pending", [("reason", "journal-read")])
      return match held {
        Some(store) => close_held(store)
        None => OrphansPending
      }
    }
  }
  let pending = intents.length()
  if pending == 0 && held is None {
    ignore(journal.close())
    return OrphansDone
  }
  let store = match held {
    Some(value) => value
    None => {
      match slot.try_acquire() {
        Ok(true) => ()
        Ok(false) => {
          ignore(journal.close())
          report("orphan-reclaim-pending", [("reason", "slot-busy")])
          return OrphansPending
        }
        Err(_) => {
          ignore(journal.close())
          stop("executor slot lock failed")
        }
      }
      let opened = @publication_store.open_store(
        environment.sqlite_library,
        required(matches, "publication-root"),
        required(matches, "publication-authority-cid"),
        required_int64(matches, "publication-capacity-bytes"),
        required_int(matches, "max-transfers").to_int64(),
        environment.max_record_bytes,
      )
      match opened {
        Ok(value) => value
        Err(_) => {
          ignore(journal.close())
          ignore(slot.close())
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
  ignore(journal.close())
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
  bundles : @bundle.NativeRuntimeBundleStore
  journal : @journal.Journal
  request_identity : String
  mut bundle_closed : Bool
}

///|
/// Cleanup never acquires an execution component or a new runtime holding.
/// The saved Site binding and signed installed bundle remain authoritative;
/// a newer maintenance executable is not authority to run the old component.
fn open_release_recovery(
  matches : @argparse.Matches,
  slot : @slot.NativeExecutorSlot,
  identity : String,
) -> StoppedReleaseRecovery raise CommandStop {
  let environment = open_control_environment(matches)
  guard fresh_journal(environment) is Some(journal) else {
    stop("release recovery journal unavailable")
  }
  let signature_library = match
    @signature.load_library(required(matches, "crypto-library")) {
    Ok(value) => value
    Err(_) => stop("signature library load failed")
  }
  let public_key = load_text(
    required(matches, "bundle-public-key-root"),
    required(matches, "bundle-public-key-file"),
    required_int64(matches, "max-file-bytes"),
  )
  let bundles = match
    @bundle.open_runtime_bundle_store(
      environment.sqlite_library,
      signature_library,
      required(matches, "runtime-root"),
      [
        {
          issuer_authority: required(matches, "bundle-issuer"),
          key_id: required(matches, "bundle-key-id"),
          public_key_pem: public_key,
        },
      ],
      required(matches, "target-triple"),
      environment.max_bytes,
      64,
      1024,
      environment.max_record_bytes,
    ) {
    Ok(value) => value
    Err(_) => stop("release recovery bundle Store unavailable")
  }
  match bundles.inspect(environment.runtime_bundle_cid) {
    Ok(Some(_)) => ()
    _ => {
      ignore(journal.close())
      ignore(bundles.close())
      stop("release recovery saved bundle unavailable")
    }
  }
  { slot, bundles, journal, request_identity: identity, bundle_closed: false, }
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
      if slot.try_acquire() != Ok(true) {
        ignore(slot.close())
        return false
      }
      // Failure to initialize terminates this control process; no cleanup
      // transition is written and the durable claim remains for recovery.
      let value = open_release_recovery(matches, slot, identity)
      retained.val = Some(value)
      value
    }
  }
  if owner.request_identity != identity {
    return false
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
  if !owner.bundle_closed {
    let holds = ["dispatch:" + identity]
    if claimant is Some(value) {
      holds.push("runtime-process:resident-holder:" + value)
    }
    for hold in holds {
      match owner.bundles.release(hold) {
        Ok(_) => () // Absence of this exact holding is idempotent.
        Err(_) => return false
      }
    }
  }
  if claimant is None && !owner.bundle_closed {
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
  // persistent runtime holdings have now also been discharged.
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
        if !owner.journal.close() {
          stop("release recovery journal close unconfirmed")
        }
        if !owner.slot.close() {
          stop("release recovery slot close unconfirmed")
        }
        retained.val = None
        return true
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
  ignore(journal.close())
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
  client : @http.Client,
  url : String,
  next : Map[String, UInt64],
  backoff_ms : Int,
  cursor_owner : Ref[String],
  delegation : @resident.ResidentSiteDelegation,
  checkpoint : (String) -> Unit,
) -> Unit {
  guard fresh_journal(environment) is Some(journal) else { return }
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
        if next.get(key) is Some(deadline) && @env.now() < deadline {
          continue
        }
        next.set(key, @env.now() + backoff_ms.to_uint64())
        let result = @remote.remote_output_report_custody_result(custody)
        if state is Some(@remote.RemoteOutputReportReply::Refused(reason)) {
          report("output-report-attention", [
            ("report_cid", @remote.remote_output_result_identity(result)),
            ("reason", reason),
          ])
          continue
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
          continue
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
  if !journal.close() {
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
  client : @http.Client,
  url : String,
  cursor : Ref[String],
  next : Map[String, UInt64],
  backoff_ms : Int,
  delegation : @resident.ResidentSiteDelegation,
  recovery : Ref[StoppedReleaseRecovery?],
  close_failures : Ref[Int],
) -> Unit raise CommandStop {
  guard fresh_journal(environment) is Some(journal) else { return }
  let recovered = journal.recover_after(cursor.val)
  match recovered {
    Ok(Some((key, record))) => {
      cursor.val = key
      let request = @remote.dispatch_record_request(record)
      let pending = journal.cancellation_requested(request)
      let already_released = @remote.remote_runtime_record_released(record)
      ignore(journal.close())
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
      if next.get(identity) is Some(deadline) && @env.now() < deadline {
        return
      }
      next.set(identity, @env.now() + backoff_ms.to_uint64())
      if !already_released &&
        !recover_stopped_release(matches, request, recovery, close_failures) {
        report("cancel-cleanup-pending", [("request_cid", identity)])
        return
      }
      guard fresh_journal(environment) is Some(current) else { return }
      match @client.acknowledge_status(current, client, url, request) {
        Ok(_) => report("cancel-reconciled", [("request_cid", identity)])
        Err(issue) =>
          report("cancel-unreported", [
            ("request_cid", identity),
            ("reason", client_code(issue)),
          ])
      }
      ignore(current.close())
    }
    Ok(None) => {
      cursor.val = ""
      ignore(journal.close())
    }
    Err(_) => {
      ignore(journal.close())
      report("cancel-recovery-pending", [("reason", "journal-read")])
    }
  }
}

///|
fn run_control(matches : @argparse.Matches) -> Unit raise CommandStop {
  if !@slot.install_native_termination_request() {
    stop("termination handling could not be installed")
  }
  let environment = open_control_environment(matches)
  let slot_path = required(matches, "executor-slot")
  let mut slot = match @slot.open_native_executor_slot(slot_path) {
    Ok(value) => value
    Err(_) => stop("executor slot open failed")
  }
  let client = control_client(matches)
  let poll_url = required(matches, "poll-url")
  let observation_url = required(matches, "observation-url")
  let dispatch_budget = budget(matches)
  let site_delegation = delegation(matches, dispatch_budget)
  let admission = run_admission(matches)
  let generation = required_int(matches, "site-generation")
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
  // Holder records not yet reported. They are kept and retried, never
  // dropped, and do not hold back new work; a query answered from the
  // journal for the same dispatch reports them too.
  let unsettled : Array[RunningHolder] = []
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
  let next_cancel_report : Map[String, UInt64] = Map([])
  let mut polls = 0
  let mut holders = 0
  let next_output_report : Map[String, UInt64] = Map([])
  let report_cursor : Ref[String] = { val: "", }
  let report_kill_at = required(matches, "control-report-kill-at")
  let report_checkpoint = fn(point : String) {
    if point == report_kill_at {
      report("control-report-killed", [("point", point)])
      @slot.native_kill_self()
    }
  }
  while !@slot.native_termination_requested() {
    replay_output_reports(
      environment, client, observation_url, next_output_report, max_backoff_ms, report_cursor,
      site_delegation, report_checkpoint,
    )
    // A finished holder's durable record is reported before new work.
    match holder {
      Some(current) =>
        match current.child.wait(false) {
          Ok(Some(_)) => {
            ignore(current.channel.close())
            holder = None
            // Physical child exit is separate from the Coordinator's ACK of
            // its durable status (which may be unavailable or already read).
            report("holder-exited", [("attempt", current.attempt)])
            // A holder that died may have left output intents behind.
            reclaim_due = true
            // A holder that ended without claiming (its setup failed) left
            // the attempt startable: it stays queued and starts again after
            // the error backoff. Only a record that can no longer start is
            // reported and leaves the queue.
            if holder_left_startable(environment, current.request) {
              report("holder-unclaimed", [("attempt", current.attempt)])
              next_start_ms = @env.now() + max_backoff_ms.to_uint64()
            } else {
              ignore(queue.remove(current.attempt))
              unsettled.push(current)
            }
          }
          Ok(None) =>
            if @env.now() >= current.next_report_ms {
              // A live producer keeps its input until the consumer finishes.
              // Report its durable progress without treating child exit,
              // execution settlement, or resource release as equivalent facts.
              current.next_report_ms = @env.now() + max_backoff_ms.to_uint64()
              match fresh_journal(environment) {
                Some(journal) => {
                  match
                    @client.acknowledge_status(
                      journal,
                      client,
                      observation_url,
                      current.request,
                    ) {
                    Ok(_) => ()
                    Err(issue) =>
                      report("observation-pending", [
                        ("attempt", current.attempt),
                        ("reason", client_code(issue)),
                      ])
                  }
                  ignore(journal.close())
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
    // Unreported records are retried with the error backoff, not on every
    // pass.
    let still_unsettled = unsettled.filter(current => {
      if @env.now() < current.next_report_ms {
        return true
      }
      if settle_holder(current, environment, client, observation_url) {
        false
      } else {
        current.next_report_ms = @env.now() + max_backoff_ms.to_uint64()
        true
      }
    })
    unsettled.clear()
    unsettled.append(still_unsettled)
    // Start the oldest accepted attempt when the slot is free. The lock is
    // taken here and passed to the holder without a gap.
    if holder is None && !slot.is_open() {
      // A slot handed to an earlier holder is opened again; the same file is
      // always used.
      slot = match @slot.open_native_executor_slot(slot_path) {
        Ok(value) => value
        Err(_) => stop("executor slot open failed")
      }
    }
    if !orphan_reconciliation &&
      holder is None &&
      (
        orphan_store is Some(_) ||
        (reclaim_due && @env.now() >= next_reclaim_ms)
      ) &&
      !skip_reclaim(reclaim_failures) {
      match reclaim_orphaned_outputs(matches, environment, slot, orphan_store) {
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
        matches, environment, client, observation_url, cancel_cursor, next_cancel_report,
        max_backoff_ms, site_delegation, recovery, recovery_close_failures,
      )
    }
    // No holder starts while this process still has the slot for a Store
    // it could not close yet.
    if holder is None &&
      orphan_store is None &&
      recovery.val is None &&
      @env.now() >= next_start_ms {
      if !slot.is_open() {
        slot = match @slot.open_native_executor_slot(slot_path) {
          Ok(value) => value
          Err(_) => stop("executor slot open failed")
        }
      }
      match queue.next() {
        Some(attempt) =>
          // The exact request is read and checked before a holder starts, so
          // nothing is left to fail between the spawn and its tracking.
          match accepted_request(environment, attempt, envelope_read_failures) {
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
                  match
                    slot.spawn_holder_with_channel(
                      executable,
                      holder_arguments(attempt, claimant),
                    ) {
                    Ok((child, channel)) => {
                      holder = Some({
                        child,
                        channel,
                        attempt,
                        request,
                        next_report_ms: 0,
                      })
                      report("holder-started", [
                        ("attempt", attempt),
                        ("claimant", claimant),
                      ])
                    }
                    Err(_) => {
                      // Nothing started; the slot is released and the
                      // attempt stays queued for a later pass.
                      ignore(slot.close())
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
    if max_polls > 0 && polls >= max_polls {
      if holder is None && unsettled.is_empty() {
        break
      }
      @slot.native_wait_milliseconds(idle_wait_ms)
      continue
    }
    polls += 1
    let started = @env.now()
    let operation = @client.poll_operation(client, poll_url)
    guard fresh_journal(environment) is Some(journal) else {
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
          ignore(journal.close())
          continue
        }
        match
          @resident_host.accept_resident_dispatch(
            journal,
            client,
            observation_url,
            site_delegation,
            generation,
            queue,
            admission,
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
          Err(issue) => report("accept-failed", [("reason", host_code(issue))])
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
                  Ok(attempt) => ignore(queue.remove(attempt))
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
                  } else if codes[0] == 3 {
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
            let remaining = unsettled.filter(current => {
              @remote.dispatch_request_identity(current.request) != identity
            })
            unsettled.clear()
            unsettled.append(remaining)
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
        // A live holder owns this output: it releases it and then ends.
        let identity = @remote.dispatch_request_identity(request)
        if holder is Some(current) &&
          holder_can_receive(current.request, request) {
          if current.channel.send("release " + identity) {
            report("release-relayed", [("request_cid", identity)])
          } else {
            report("release-unrelayed", [("request_cid", identity)])
          }
          ignore(journal.close())
          continue
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
          if recover_stopped_release(
              matches, request, recovery, recovery_close_failures,
            ) {
            report("release-recovered", [("request_cid", identity)])
          }
        }
        match
          @client.acknowledge_status(journal, client, observation_url, request) {
          Ok(_) =>
            report("release-observed", [
              ("request_cid", @remote.dispatch_request_identity(request)),
            ])
          Err(issue) =>
            report("release-failed", [("reason", client_code(issue))])
        }
      }
      Ok(Some(@remote.RetainedPlan(input))) => {
        backoff_ms = 0
        let intent = @remote.remote_poll_retained_input_intent(input)
        let request = @remote.remote_retained_input_intent_request(intent)
        let identity = @remote.dispatch_request_identity(request)
        match (holder, @remote.remote_poll_retained_input_plan_json(intent)) {
          (Some(current), Ok(body)) if @remote.dispatch_request_identity(
              current.request,
            ) ==
            identity =>
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
          (Some(current), Ok(body)) if @remote.dispatch_request_identity(
              current.request,
            ) ==
            identity =>
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
          (Some(current), Ok(body)) if @remote.dispatch_request_identity(
              current.request,
            ) ==
            identity =>
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
      Ok(Some(@remote.Plan(output))) | Ok(Some(@remote.Output(output))) => {
        backoff_ms = 0
        // Only the live holder of the dispatch owns its output; the
        // operation is relayed to it unchanged.
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
          _ => report("output-unavailable", [("request_cid", identity)])
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
    ignore(journal.close())
  }
  // After a termination request no new work is taken. A running holder is
  // given a bounded time to finish; after it, the durable journal keeps its
  // record and nothing unconfirmed is settled here.
  let mut waited = 0
  while holder is Some(current) && waited < shutdown_wait_ms {
    match current.child.wait(false) {
      Ok(Some(_)) => {
        ignore(settle_holder(current, environment, client, observation_url))
        holder = None
      }
      _ => {
        @slot.native_wait_milliseconds(50)
        waited += 50
      }
    }
  }
  for current in unsettled {
    ignore(settle_holder(current, environment, client, observation_url))
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
  ignore(client.close())
  ignore(slot.close())
  report("stopped", [])
}

///|
fn authenticated_client(
  matches : @argparse.Matches,
  prefix : String,
) -> @http.Client raise CommandStop {
  let library = match @http.load_library(required(matches, "http-library")) {
    Ok(value) => value
    Err(_) => stop("HTTP library load failed")
  }
  let authentication : @http.NativeHttpAuthentication = match
    (
      optional(matches, prefix + "-cert"),
      optional(matches, prefix + "-key"),
      optional(matches, prefix + "-bearer-file"),
    ) {
    (Some(cert), Some(key), Some(bearer)) =>
      MutualTlsAndBearer(cert, key, bearer)
    (Some(cert), Some(key), None) => MutualTls(cert, key)
    (None, None, Some(bearer)) => Bearer(bearer)
    _ =>
      stop(
        prefix + " authentication needs a bearer file or a certificate and key",
      )
  }
  match
    library.create_authenticated_client(
      required(matches, "ca"),
      authentication,
      required_int64(matches, "max-response-bytes"),
      required_int(matches, "connect-timeout-ms"),
      required_int(matches, "total-timeout-ms"),
    ) {
    Ok(value) => value
    Err(_) => stop("HTTP client creation failed")
  }
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
  retained_delegation : @resident.ResidentRetainedInputDelegation?
  retained_root : @filesystem.Root?
  retained_max_bytes : Int64
  retained_max_objects : Int64
  control : @http.Client
  transfer : @http.Client
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
  environment : SiteEnvironment,
) -> Result[HolderOutputResources, String] {
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
    CommandStop(issue) => return Err(issue)
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
    CommandStop(issue) => return Err(issue)
  }
  let retained_root = match
    (retained_delegation, optional(matches, "retained-input-root")) {
    (None, None) => None
    (Some(_), Some(path)) =>
      match @filesystem.open_root(path) {
        Ok(root) => Some(root)
        Err(_) => return Err("retained input Root unavailable")
      }
    _ =>
      return Err(
        "retained input delegation and Root must be configured together",
      )
  }
  let control = authenticated_client(matches, "control") catch {
    CommandStop(issue) => return Err(issue)
  }
  let transfer = authenticated_client(matches, "transfer") catch {
    CommandStop(issue) => {
      ignore(control.close())
      return Err(issue)
    }
  }
  let store = match
    @publication_store.open_store(
      environment.sqlite_library,
      publication_root,
      publication_authority,
      publication_capacity,
      max_transfers.to_int64(),
      max_record_bytes,
    ) {
    Ok(value) => value
    Err(_) => {
      ignore(transfer.close())
      ignore(control.close())
      return Err("publication Store open failed")
    }
  }
  let transfer_journal = match
    @transfer_journal.open_journal(
      environment.sqlite_library,
      transfer_journal_path,
      max_record_bytes,
      65536,
      1048576,
      max_bytes,
    ) {
    Ok(value) => value
    Err(_) => {
      ignore(store.close())
      ignore(transfer.close())
      ignore(control.close())
      return Err("Transfer journal open failed")
    }
  }
  Ok({
    retained_delegation,
    retained_root,
    retained_max_bytes: max_bytes,
    retained_max_objects: max_transfers.to_int64(),
    control,
    transfer,
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
  fn(point : String) {
    if point == resources.pause_at {
      report("holder-paused", [("point", point)])
      @slot.native_wait_milliseconds(resources.pause_ms)
    }
    if point == resources.kill_at {
      report("holder-killed", [("point", point)])
      @slot.native_kill_self()
    }
  }
}

///|
/// Closes output resources when no output was produced, so nothing can be
/// owned by them.
fn close_holder_output_resources(resources : HolderOutputResources) -> Unit {
  ignore(resources.transfer_journal.close())
  ignore(resources.store.close())
  ignore(resources.transfer.close())
  ignore(resources.control.close())
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
) -> Unit {
  let runtime = executed.runtime
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
  let identity = @remote.dispatch_request_identity(request)
  store.observe_allocation(holder_checkpoint(resources))
  // Exact payloads this holder kept in the Store; it reclaims them.
  let payloads : Array[@payload.PublicationPayloadRequest] = []
  // Failed outputs that still own physical cleanup (a payload reader or
  // writer, a Store recovery, a Transfer source); retried until done.
  let failed_cleanups : Array[@resident_host.ResidentOutputIssue] = []
  let unsaved_reports : Array[@remote.RemoteOutputReportCustody] = []
  // One checked incoming edge in this profile. The same Owner survives
  // failed chunks/reports; a duplicate plan never creates a second handoff.
  let retained_handoff : Ref[(String, @resident_host.ResidentRetainedTransfer)?] = Ref(
    None,
  )
  let consumer : Ref[@resident_host.ResidentRetainedConsumer?] = Ref(None)
  let consumer_executed : Ref[@resident_host.ResidentExecuted?] = Ref(None)
  // A Runtime owns its component holding exclusively. Before Runtime
  // construction succeeds, acquisition/cleanup remains with this holder.
  let consumer_process_hold : Ref[@bundle.NativeActiveRuntimeBinding?] = Ref(
    None,
  )
  let mut consumer_released = false
  let mut producer_release_requested = false
  let mut serving = true
  while serving {
    match @slot.native_read_holder_input(2097152) {
      InputEnded => {
        report("holder-control-gone", [("request_cid", identity)])
        serving = false
      }
      InputInvalid => report("holder-input-invalid", [])
      InputLine(line) =>
        if line.has_prefix("release ") {
          let target = line.unsafe_substring(start=8, end=line.length())
          if consumer.val is Some(owner) &&
            target ==
            @remote.dispatch_request_identity(
              @resident_host.resident_retained_consumer_request(owner),
            ) {
            if consumer_released {
              continue
            }
            let remaining = unsaved_reports.filter(custody => {
              environment.journal.retain_output_report(custody) is Err(_)
            })
            unsaved_reports.clear()
            unsaved_reports.append(remaining)
            if !unsaved_reports.is_empty() {
              report("consumer-release-pending", [("reason", "report-save")])
              continue
            }
            if consumer_executed.val is Some(completed) {
              settle_holder_cleanup(
                completed.runtime,
                completed.request,
                environment.journal,
                store,
                failed_cleanups,
                payloads,
                resources.release_failures,
                holder_checkpoint(resources),
                close_store=false,
              )
              failed_cleanups.clear()
              payloads.clear()
            }
            while !owner.close() {
              report("consumer-release-pending", [("reason", "borrow-cleanup")])
              @slot.native_wait_milliseconds(250)
            }
            close_untransferred_consumer_binding(
              execution, consumer_process_hold,
            )
            if retained_handoff.val is Some((_, handoff)) {
              while handoff.reclaim() is Err(_) {
                report("consumer-release-pending", [
                  ("reason", "receiver-cleanup"),
                ])
                @slot.native_wait_milliseconds(250)
              }
            }
            consumer_released = true
            ignore(
              @client.acknowledge_status(
                environment.journal,
                control,
                observation_url,
                @resident_host.resident_retained_consumer_request(owner),
              ),
            )
            if producer_release_requested {
              serving = false
            }
          } else if target == identity {
            producer_release_requested = true
            // Do not destroy an input still needed by the chosen consumer. A
            // durable producer cancellation prevents any later consumer start.
            if retained_handoff.val is None ||
              consumer_released ||
              (
                consumer.val is None &&
                environment.journal.cancellation_requested(request) is Ok(true)
              ) {
              serving = false
            } else {
              report("producer-release-pending", [
                ("reason", "consumer-custody"),
              ])
            }
          } else {
            report("holder-input-invalid", [])
          }
        } else if line.has_prefix("consumer ") {
          let envelope = line.unsafe_substring(start=9, end=line.length())
          match
            (
              @remote.admit_remote_poll_dispatch_json(envelope),
              retained_handoff.val,
              configuration,
            ) {
            (Ok(dispatch), Some((_, handoff)), Some(configuration)) => {
              let owner = match
                @resident_host.prepare_resident_retained_consumer(
                  handoff,
                  environment.journal,
                  admission,
                  dispatch,
                  current_time(),
                  {
                    max_binding_bytes: 1048576,
                    max_chunks: 65536,
                    max_manifest_bytes: 1048576,
                    max_referenced_bytes: resources.retained_max_bytes,
                  },
                ) {
                Ok(value) => value
                Err(_) => {
                  report("consumer-refused", [("reason", "retained-input")])
                  continue
                }
              }
              consumer.val = Some(owner)
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
                      "consumer:" +
                      @remote.dispatch_request_identity(
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
                  consumer_process_hold.val = Some(active)
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
                      consumer_process_hold.val = None
                      consumer_executed.val = Some(completed)
                      report("consumer-executed", [
                        (
                          "request_cid",
                          completed.completion.dispatch_request_cid,
                        ),
                        ("revision", completed.completion.revision.to_string()),
                      ])
                    }
                    Err(failure) => {
                      if failure.pending_runtime is Some(_) {
                        consumer_process_hold.val = None
                      } else {
                        close_untransferred_consumer_binding(
                          execution, consumer_process_hold,
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
              if @remote.dispatch_request_identity(selected) != identity {
                report("retained-plan-failed", [("reason", "foreign-dispatch")])
                continue
              }
              let context = match
                @resident_host.prepare_resident_retained_producer_context(
                  environment.journal,
                  admission,
                  intent,
                  current_time(),
                ) {
                Ok(value) => value
                Err(issue) => {
                  report("retained-plan-failed", [("reason", host_code(issue))])
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
                  runtime,
                  @resident_host.resident_retained_producer(context),
                  intent,
                  current,
                  environment.site,
                ) {
                Ok(plan) =>
                  match
                    @client.acknowledge_retained_input_plan(
                      control, observation_url, plan,
                    ) {
                    Ok(_) =>
                      report("retained-input-planned", [
                        ("request_cid", identity),
                      ])
                    Err(issue) =>
                      report("retained-plan-unreported", [
                        ("reason", client_code(issue)),
                      ])
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
              retained_handoff.val,
            ) {
            (Ok(query), Some(_), Some((saved, owner))) => {
              if @remote.dispatch_request_identity(
                  @remote.remote_retained_input_current_request(query),
                ) !=
                identity ||
                @remote.remote_retained_input_plan_identity(
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
                        ("request_cid", identity),
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
            (Ok(_), _, _) =>
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
              if @remote.dispatch_request_identity(selected) != identity {
                report("retained-transfer-failed", [
                  ("reason", "foreign-dispatch"),
                ])
                continue
              }
              let handoff = match retained_handoff.val {
                Some((saved, owner)) if saved == plan_cid => owner
                Some(_) => {
                  report("retained-transfer-failed", [
                    ("reason", "foreign-plan"),
                  ])
                  continue
                }
                None => {
                  let context = match
                    @resident_host.prepare_resident_retained_producer_context(
                      environment.journal,
                      admission,
                      intent,
                      current_time(),
                    ) {
                    Ok(value) => value
                    Err(issue) => {
                      report("retained-transfer-failed", [
                        ("reason", host_code(issue)),
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
                      runtime,
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
                  retained_handoff.val = Some((plan_cid, owner))
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
                  Ok(false) => ()
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
                          ("request_cid", identity),
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
              let output_owner = match consumer_executed.val {
                Some(completed) if @remote.dispatch_request_identity(
                    completed.request,
                  ) ==
                  @remote.dispatch_request_identity(
                    @remote.remote_poll_output_request(output),
                  ) => completed
                _ => executed
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
          // Cleanup kept by earlier failed outputs is retried first, so a
          // repeated output never piles up open readers or sources.
          let still_pending = failed_cleanups.filter(issue => {
            !@resident_host.retry_resident_output_cleanup(issue)
          })
          failed_cleanups.clear()
          failed_cleanups.append(still_pending)
          let envelope = line.unsafe_substring(start=7, end=line.length())
          match @remote.admit_remote_poll_output_json(envelope) {
            Ok(output) => {
              let output_owner = match consumer_executed.val {
                Some(completed) if @remote.dispatch_request_identity(
                    completed.request,
                  ) ==
                  @remote.dispatch_request_identity(
                    @remote.remote_poll_output_request(output),
                  ) => completed
                _ => executed
              }
              let identity = @remote.dispatch_request_identity(
                output_owner.request,
              )
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
                      if !payloads
                        .iter()
                        .any(kept => {
                          @payload.publication_payload_request_identity(kept) ==
                          payload_identity
                        }) {
                        payloads.push(payload)
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
                      if !unsaved_reports.any(value => {
                          @remote.remote_output_report_custody_key(value) == key
                        }) {
                        unsaved_reports.push(custody)
                      }
                      report("output-report-save-pending", [
                        ("request_cid", identity),
                      ])
                    }
                    Err(issue) => {
                      report("output-failed", [("reason", output_code(issue))])
                      if !@resident_host.retry_resident_output_cleanup(issue) {
                        failed_cleanups.push(issue)
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
  // Saving is the only retried operation: neither delivery nor Compute.
  while !unsaved_reports.is_empty() {
    let remaining = unsaved_reports.filter(value => {
      environment.journal.retain_output_report(value) is Err(_)
    })
    unsaved_reports.clear()
    unsaved_reports.append(remaining)
    if !unsaved_reports.is_empty() {
      @slot.native_wait_milliseconds(250)
    }
  }
  holder_checkpoint(resources)("report-handoff")
  if consumer_executed.val is Some(completed) && !consumer_released {
    settle_holder_cleanup(
      completed.runtime,
      completed.request,
      environment.journal,
      store,
      failed_cleanups,
      payloads,
      resources.release_failures,
      holder_checkpoint(resources),
      close_store=false,
    )
    failed_cleanups.clear()
    payloads.clear()
  }
  if consumer.val is Some(owner) {
    while !owner.close() {
      report("consumer-release-pending", [("reason", "borrow-cleanup")])
      @slot.native_wait_milliseconds(250)
    }
  }
  close_untransferred_consumer_binding(execution, consumer_process_hold)
  if retained_handoff.val is Some((_, handoff)) {
    while handoff.reclaim() is Err(_) {
      report("retained-transfer-cleanup-pending", [("request_cid", identity)])
      @slot.native_wait_milliseconds(250)
    }
  }
  settle_holder_cleanup(
    runtime,
    request,
    environment.journal,
    store,
    failed_cleanups,
    payloads,
    resources.release_failures,
    holder_checkpoint(resources),
  )
  if consumer_released {
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
  ignore(transfer_journal.close())
  ignore(transfer.close())
  ignore(control.close())
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
  holder : @argparse.Matches,
) -> Unit raise CommandStop {
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
  let inspection = match fresh_journal(open_control_environment(matches)) {
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
  if !inspection.close() {
    stop("holder saved journal close pending")
  }
  let original_claimant = match saved_claimant {
    Ok(Some(value)) => value
    Ok(None) => claimant
    Err(issue) => {
      report("holder-restoration-refused", [("reason", host_code(issue))])
      stop("holder saved completion unavailable")
    }
  }
  let environment = open_site_environment(
    matches,
    // The actual exclusive slot confirms the old process has stopped. The
    // journal selects its exact holding; retain is idempotent and Runtime
    // returns this holding only after its physical cleanup completes.
    "runtime-process:resident-holder:" + original_claimant,
  )
  // The installed runtime must be the one the Site delegates.
  let (registration, revision, strategy) = @bundle.native_active_runtime_connector_scope(
    environment.active_runtime,
  )
  if environment.runtime_bundle_cid != required(matches, "runtime-bundle-cid") ||
    registration != required(matches, "connector-registration") ||
    revision != required(matches, "connector-revision") ||
    strategy != required(matches, "strategy-revision") {
    close_site_environment(environment)
    stop("installed runtime differs from the Site delegation")
  }
  let max_file_bytes = required_int64(matches, "max-file-bytes")
  let values_root = required(matches, "engine-root")
  let registry_body = load_text(values_root, "registry.json", max_file_bytes)
  let values_body = load_text(values_root, "values.json", max_file_bytes)
  let output_bytes = required_int64(matches, "max-output-bytes")
  let execution : @resident_host.ResidentExecution = {
    source: source_configuration(matches, values_root, max_file_bytes),
    site: environment.site,
    active_runtime: environment.active_runtime,
    operation_capability_cid: required(matches, "operation-capability-cid"),
    issuer_capability_cid: required(matches, "issuer-capability-cid"),
    bundles: environment.bundles,
    budgets: [budget(matches)],
    registry_body,
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
            source, registry_body, values_body, retained_engine_bytes,
          )
        None => None
      }
      guard configured is Some(profile) else {
        close_site_environment(environment)
        ignore(slot.close())
        stop("retained consumer bounded profile unavailable")
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
  // Everything the output needs is opened before execution. A holder that
  // cannot open it ends without claiming, so nothing is left to clean up and
  // the attempt stays startable.
  let resources = match open_holder_output_resources(matches, environment) {
    Ok(value) => value
    Err(issue) => {
      report("setup-failed", [("reason", issue)])
      close_site_environment(environment)
      ignore(slot.close())
      stop("holder setup failed before claim")
    }
  }
  holder_checkpoint(resources)("before-start")
  let start_checks = [0]
  let saved_completion = match environment.journal.dispatch_envelope(attempt) {
    Ok(Some(body)) =>
      match @remote.admit_remote_poll_dispatch_json(body) {
        Ok(dispatch) =>
          match
            environment.journal.require(
              @remote.remote_poll_dispatch_request(dispatch),
            ) {
            Ok(record) => @remote.dispatch_record_state_codes(record)[0] == 3
            Err(_) => false
          }
        Err(_) => false
      }
    _ => false
  }
  let result = if saved_completion {
    restore_holder_attempt(matches, environment, execution, slot, attempt)
  } else {
    @resident_host.execute_resident_attempt(
      environment.journal,
      execution,
      run_admission(matches),
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
      source_observe=event => {
        if event is @resident_host.AcquisitionEntered {
          // A physical acquisition boundary, separate from executor entry
          // and the later durable successful Source observation.
          report("source-acquisition-entered", [("attempt", attempt)])
        }
        true
      },
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
      )
      0
    }
    Err(failure) => {
      let issue = failure.issue
      report("execute-failed", [("reason", host_code(issue))])
      // A runtime whose cleanup is not confirmed is kept: only its close is
      // retried, with the slot still held, and nothing is started again.
      match failure.pending_runtime {
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
            ("reason", host_code(issue)),
            ("attempts", attempts.to_string()),
          ])
        }
        None => ()
      }
      close_holder_output_resources(resources)
      match issue {
        Runtime(@runtime.StartClaimLost(_))
        | Runtime(@runtime.StartCancelled) => 2
        _ => 1
      }
    }
  }
  close_site_environment(environment)
  ignore(slot.close())
  if code != 0 {
    stop("execute exited with " + code.to_string())
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
/// Any outstanding publication custody refuses rather than reclaiming other
/// attempts. An unconfirmed observation can be sent again on the next call.
fn recover_release_command(
  matches : @argparse.Matches,
  child : @argparse.Matches,
) -> Unit raise CommandStop {
  let environment = open_control_environment(matches)
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
  let slot = match
    @slot.open_native_executor_slot(required(matches, "executor-slot")) {
    Ok(value) => value
    Err(_) => stop("release recovery slot unavailable")
  }
  if slot.try_acquire() != Ok(true) {
    ignore(slot.close())
    stop("release recovery slot busy")
  }
  let owner = open_release_recovery(matches, slot, identity)
  match owner.journal.pending_output_intents() {
    Ok(values) if values.is_empty() => ()
    _ => stop("release recovery Output custody pending")
  }
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
  let store = match
    @publication_store.open_store(
      environment.sqlite_library,
      required(matches, "publication-root"),
      required(matches, "publication-authority-cid"),
      required_int64(matches, "publication-capacity-bytes"),
      required_int(matches, "max-transfers").to_int64(),
      environment.max_record_bytes,
    ) {
    Ok(value) => value
    Err(_) => stop("release recovery publication Store unavailable")
  }
  let empty = match store.capacity_usage() {
    Ok(value) => value.reserved_bytes == 0L && value.reserved_objects == 0L
    Err(_) => false
  }
  let closed = store.close()
  if !empty || !(closed is Ok(true)) {
    stop("release recovery publication custody unconfirmed")
  }
  let retained : Ref[StoppedReleaseRecovery?] = { val: Some(owner), }
  if !recover_stopped_release(matches, request, retained, { val: 0, }) {
    stop("release recovery pending")
  }
  let client = control_client(matches)
  guard fresh_journal(environment) is Some(journal) else {
    stop("release recovery observation journal unavailable")
  }
  let observed = @client.acknowledge_status(
    journal,
    client,
    required(matches, "observation-url"),
    request,
  )
  let closed = journal.close()
  ignore(client.close())
  match observed {
    Ok(Some(record)) if closed =>
      report("release-recovery-observed", [
        ("request_cid", identity),
        ("revision", @remote.dispatch_record_revision(record).to_string()),
      ])
    _ => stop("release recovery observation unconfirmed")
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
      @argparse.Command("recover-release", options=[
        @argparse.OptionArg("attempt", required=true),
        @argparse.OptionArg("expect-dispatch", required=true),
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
fn run_command(matches : @argparse.Matches) -> Unit raise CommandStop {
  match matches.subcommand {
    Some(("run", _)) => run_control(matches)
    Some(("execute", child)) => run_holder(matches, child)
    Some(("recover-release", child)) => recover_release_command(matches, child)
    Some(("output-reports", _)) => {
      let environment = open_control_environment(matches)
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
            ignore(journal.close())
            stop("report inspection failed")
          }
        }
      }
      if !journal.close() {
        stop("journal close pending")
      }
    }
    Some(("retry-output-report", child)) => {
      let environment = open_control_environment(matches)
      guard fresh_journal(environment) is Some(journal) else {
        stop("journal unavailable")
      }
      let key = required(child, "intent-cid")
      let custody = match journal.output_report(key) {
        Ok(value) => value.0
        Err(_) => {
          ignore(journal.close())
          stop("report unavailable")
        }
      }
      if @resident.check_resident_dispatch_delegation(
          delegation(matches, budget(matches)),
          @remote.remote_output_report_custody_dispatch(custody),
          environment.site_generation,
        )
        is Err(_) {
        ignore(journal.close())
        stop("current report scope refused")
      }
      let result = journal.retry_output_report(key)
      let closed = journal.close()
      if result is Err(_) {
        stop("report retry rejected")
      }
      if !closed {
        stop("journal close pending")
      }
      report("output-report-retry-enabled", [])
    }
    _ => stop("missing operation")
  }
}

///|
fn main {
  let matches = command().parse() catch { error => abort(error.to_string()) }
  run_command(matches) catch {
    CommandStop(issue) => abort("actql-native-remote-resident-site: " + issue)
  }
}
