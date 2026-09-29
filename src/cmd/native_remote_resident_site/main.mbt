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
fn now_timestamp() -> String raise CommandStop {
  match @resident.resident_utc_timestamp(@env.now().reinterpret_as_int64()) {
    Some(value) => value
    None => stop("Site clock is out of range")
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
    Runtime(@runtime.StartClaimLost(_)) => "start-claim-lost"
    Runtime(@runtime.StartCancelled) => "start-cancelled"
    Runtime(@runtime.ExecutorEntryUnrecorded) => "executor-entry-unrecorded"
    Runtime(_) => "runtime"
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
/// What the control process uses. It never opens the runtime bundle Store,
/// which only a holder holds while it executes; the installed runtime and
/// Connector it delegates are Site configuration.
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
fn run_admission() -> @resident_host.ResidentRunAdmission raise CommandStop {
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
    // This implementation runs source-free Values Runs with the relation
    // profile only.
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
  let admission = run_admission()
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
  let mut holder : RunningHolder? = None
  // Holder records not yet reported. They are kept and retried, never
  // dropped, and do not hold back new work; a query answered from the
  // journal for the same dispatch reports them too.
  let unsettled : Array[RunningHolder] = []
  let mut backoff_ms = 0
  let mut polls = 0
  let mut holders = 0
  while !@slot.native_termination_requested() {
    // A finished holder's durable record is reported before new work.
    match holder {
      Some(current) =>
        match current.child.wait(false) {
          Ok(Some(_)) => {
            ignore(current.channel.close())
            ignore(queue.remove(current.attempt))
            holder = None
            unsettled.push(current)
          }
          Ok(None) => ()
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
    if holder is None {
      // A slot handed to an earlier holder is opened again; the same file is
      // always used.
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
            now_timestamp(),
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
          @remote.dispatch_request_identity(current.request) == identity {
          if current.channel.send("release") {
            report("release-relayed", [("request_cid", identity)])
          } else {
            report("release-unrelayed", [("request_cid", identity)])
          }
          ignore(journal.close())
          continue
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
          (Some(current), Ok(body)) if @remote.dispatch_request_identity(
              current.request,
            ) ==
            identity =>
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
    OutputTransfer(_) => "transfer"
    OutputProtocol(_) => "protocol"
  }
}

///|
/// After execution the holder keeps its output and serves the Coordinator's
/// output operations, relayed by the control process over the holder's
/// standard input. When the output is released, or the control process is
/// gone, the holder releases the output and reclaims every payload it kept
/// in the Site's publication Store, retrying each step until it is
/// confirmed. It never ends while it still owns a cleanup: until then it
/// keeps the executor slot and the capacity counted.
fn serve_holder_output(
  matches : @argparse.Matches,
  environment : SiteEnvironment,
  executed : @resident_host.ResidentExecuted,
) -> Unit raise CommandStop {
  let runtime = executed.runtime
  let request = executed.request
  let coordinator_authority = required(matches, "coordinator-authority")
  let control = authenticated_client(matches, "control")
  let transfer = authenticated_client(matches, "transfer")
  let observation_url = required(matches, "observation-url")
  let destination_origin = required(matches, "transfer-origin")
  let max_bytes = required_int64(matches, "max-bytes")
  let max_record_bytes = required_int64(matches, "max-record-bytes")
  let store = match
    @publication_store.open_store(
      environment.sqlite_library,
      required(matches, "publication-root"),
      required(matches, "publication-authority-cid"),
      required_int64(matches, "publication-capacity-bytes"),
      required_int(matches, "max-transfers").to_int64(),
      max_record_bytes,
    ) {
    Ok(value) => value
    Err(_) => stop("publication Store open failed")
  }
  let transfer_journal = match
    @transfer_journal.open_journal(
      environment.sqlite_library,
      required(matches, "transfer-journal"),
      max_record_bytes,
      65536,
      1048576,
      max_bytes,
    ) {
    Ok(value) => value
    Err(_) => stop("Transfer journal open failed")
  }
  let site_key = required(matches, "site-key")
  let site_generation = required_int(matches, "site-generation")
  let identity = @remote.dispatch_request_identity(request)
  // Exact payloads this holder kept in the Store; it reclaims them.
  let payloads : Array[@payload.PublicationPayloadRequest] = []
  let mut serving = true
  while serving {
    match @slot.native_read_holder_input(2097152) {
      InputEnded => {
        report("holder-control-gone", [("request_cid", identity)])
        serving = false
      }
      InputInvalid => report("holder-input-invalid", [])
      InputLine(line) =>
        if line == "release" {
          serving = false
        } else if line.has_prefix("plan ") {
          let envelope = line.unsafe_substring(start=5, end=line.length())
          match @remote.admit_remote_poll_output_plan_json(envelope) {
            Ok(output) =>
              match
                @resident_host.plan_resident_output(
                  executed,
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
                      report("output-planned", [("request_cid", identity)])
                    Err(issue) =>
                      report("output-plan-unreported", [
                        ("reason", client_code(issue)),
                      ])
                  }
                Err(issue) =>
                  report("output-plan-failed", [("reason", output_code(issue))])
              }
            Err(_) => report("holder-input-invalid", [])
          }
        } else if line.has_prefix("output ") {
          let envelope = line.unsafe_substring(start=7, end=line.length())
          match @remote.admit_remote_poll_output_json(envelope) {
            Ok(output) =>
              match
                @resident_host.deliver_resident_output(
                  executed,
                  environment.journal,
                  coordinator_authority,
                  site_key,
                  site_generation,
                  output,
                  store,
                  transfer,
                  transfer_journal,
                  destination_origin,
                  65536,
                ) {
                Ok((result, payload)) => {
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
                  match
                    @client.acknowledge_output_result(
                      control, observation_url, result,
                    ) {
                    Ok(_) =>
                      report("output-delivered", [("request_cid", identity)])
                    Err(issue) =>
                      report("output-result-unreported", [
                        ("reason", client_code(issue)),
                      ])
                  }
                }
                Err(issue) =>
                  report("output-failed", [("reason", output_code(issue))])
              }
            Err(_) => report("holder-input-invalid", [])
          }
        } else {
          report("holder-input-invalid", [])
        }
    }
  }
  settle_holder_cleanup(
    runtime,
    request,
    store,
    payloads,
    required_int(matches, "holder-release-failures"),
  )
  ignore(transfer_journal.close())
  ignore(transfer.close())
  ignore(control.close())
}

///|
/// Release the output and reclaim its payloads, retrying each step with a
/// bounded backoff until it is confirmed. `injected_release_failures` is an
/// acceptance test hook that fails that many release attempts first.
fn settle_holder_cleanup(
  runtime : @runtime.NativeRemoteRuntime,
  request : @remote.DispatchRequest,
  store : @publication_store.Store,
  payloads : Array[@payload.PublicationPayloadRequest],
  injected_release_failures : Int,
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
      match @resident_host.reclaim_resident_payload(store, payload) {
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
  while true {
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
  // A holder that cannot confirm it holds the named slot must not claim.
  let slot = match
    @slot.inherited_native_executor_slot(required(matches, "executor-slot")) {
    Ok(value) => value
    Err(_) => stop("executor slot is not held by this holder")
  }
  let claimant = required(holder, "claimant")
  let environment = open_site_environment(
    matches,
    "runtime-process:resident-holder:" + claimant,
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
  // Acceptance evidence only: record each executor entry, and optionally
  // hold the slot for a while after it so process tests can act meanwhile.
  let entry_log = optional(matches, "executor-entry-log")
  let pause_ms = required_int(matches, "holder-pause-ms")
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
  let result = @resident_host.execute_resident_attempt(
    environment.journal,
    execution,
    run_admission(),
    required(holder, "attempt"),
    claimant,
    now_timestamp(),
    observer,
  )
  let code = match result {
    Ok(executed) => {
      report("executed", [
        ("request_cid", executed.completion.dispatch_request_cid),
        ("revision", executed.completion.revision.to_string()),
      ])
      // The output stays owned by this holder's runtime until the
      // Coordinator releases it; the holder serves its output meanwhile.
      serve_holder_output(matches, environment, executed)
      0
    }
    Err(issue) => {
      report("execute-failed", [("reason", host_code(issue))])
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
      global("issuer-capability-cid"),
      global("budget-retained-bytes"),
      global("budget-execution-bytes"),
      global("engine-root"),
      global("executor-entry-log"),
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
      defaulted("control-envelope-read-failures", "0"),
      defaulted("publication-capacity-bytes", "268435456"),
    ],
    subcommands=[
      @argparse.Command("run"),
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
