///|
fn option(matches : @argparse.Matches, name : String) -> Result[String, String] {
  match matches.values.get(name) {
    Some([value]) if !value.is_empty() => Ok(value)
    _ => Err("missing or repeated option --" + name)
  }
}

///|
fn parse_int(value : String, name : String) -> Result[Int, String] {
  let parsed : Int = @string.from_str(value) catch {
    _ => return Err("invalid integer option --" + name)
  }
  Ok(parsed)
}

///|
fn parse_int64(value : String, name : String) -> Result[Int64, String] {
  let parsed : Int64 = @string.from_str(value) catch {
    _ => return Err("invalid integer option --" + name)
  }
  Ok(parsed)
}

///|
fn int_option(
  matches : @argparse.Matches,
  name : String,
) -> Result[Int, String] {
  match option(matches, name) {
    Ok(value) => parse_int(value, name)
    Err(issue) => Err(issue)
  }
}

///|
fn int64_option(
  matches : @argparse.Matches,
  name : String,
) -> Result[Int64, String] {
  match option(matches, name) {
    Ok(value) => parse_int64(value, name)
    Err(issue) => Err(issue)
  }
}

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
  match option(matches, name) {
    Ok(value) => value
    Err(issue) => stop(issue)
  }
}

///|
fn required_int(
  matches : @argparse.Matches,
  name : String,
) -> Int raise CommandStop {
  match int_option(matches, name) {
    Ok(value) => value
    Err(issue) => stop(issue)
  }
}

///|
fn required_int64(
  matches : @argparse.Matches,
  name : String,
) -> Int64 raise CommandStop {
  match int64_option(matches, name) {
    Ok(value) => value
    Err(issue) => stop(issue)
  }
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
fn runtime_issue_message(issue : @runtime.NativeRemoteRuntimeIssue) -> String {
  match issue {
    @runtime.Closed => "remote runtime is closed"
    @runtime.InvalidConfiguration => "remote runtime configuration is invalid"
    @runtime.RegistrationCollision => "remote runtime registration collided"
    @runtime.RuntimeUnsupported => "remote runtime is unsupported"
    @runtime.BudgetUnsupported => "remote runtime budget is unsupported"
    @runtime.SiteUnavailable => "remote runtime Site is unavailable"
    @runtime.CapacityRejected => "remote runtime capacity rejected"
    @runtime.AcceptanceUnconfirmed => "remote runtime acceptance is unconfirmed"
    @runtime.DispatchAlreadyStarted => "remote runtime dispatch already started"
    @runtime.OperationRejected => "remote runtime operation was rejected"
    @runtime.HoldingRejected => "remote runtime holding was rejected"
    @runtime.SettlementRejected => "remote runtime settlement was rejected"
    @runtime.CustodyRejected => "remote runtime custody was rejected"
    @runtime.OutputRejected => "remote runtime output was rejected"
    @runtime.OutputReaderUnavailable => "remote output reader is unavailable"
    @runtime.OutputReaderClosed => "remote output reader is closed"
    @runtime.OutputReaderIncomplete => "remote output reader is incomplete"
    @runtime.OutputReaderChunkExceeded =>
      "remote output reader chunk limit was exceeded"
    @runtime.OutputReaderPhysical(message) =>
      "remote output reader failed: " + message
    @runtime.Physical(message) => "remote runtime failed: " + message
    @runtime.CleanupPending(message) =>
      "remote runtime cleanup remains pending: " + message
    @runtime.Protocol(_) => "remote runtime protocol rejected"
    @runtime.Journal(_) => "remote runtime journal failed"
    @runtime.Bundle(_) => "remote runtime bundle failed"
  }
}

///|
fn application_issue_message(
  issue : @application.NativeRemoteApplicationSiteIssue,
) -> String {
  match issue {
    @application.Distribution(
      @remote_standard.Component(@remote_standard.Runtime(runtime_issue))
    ) => runtime_issue_message(runtime_issue)
    @application.Distribution(
      @remote_standard.Component(
        @remote_standard.Agent(@agent.Runtime(runtime_issue))
      )
    ) => runtime_issue_message(runtime_issue)
    @application.Distribution(
      @remote_standard.Component(
        @remote_standard.Agent(@agent.RuntimeObserved(runtime_issue, _))
      )
    ) => runtime_issue_message(runtime_issue)
    @application.Distribution(
      @remote_standard.Component(
        @remote_standard.Agent(
          @agent.RuntimeObservationUnknown(runtime_issue, _)
        )
      )
    ) => runtime_issue_message(runtime_issue)
    @application.Distribution(
      @remote_standard.Component(@remote_standard.Host(_))
    ) => "remote standard Host failed"
    @application.Distribution(
      @remote_standard.Component(@remote_standard.Journal(_))
    ) => "remote Site journal failed"
    @application.Distribution(
      @remote_standard.Component(@remote_standard.Transfer(_))
    ) => "remote Transfer failed"
    @application.Distribution(
      @remote_standard.Component(@remote_standard.TransferSend(_))
    ) => "remote Transfer send failed"
    @application.Distribution(@remote_standard.Bundle(_)) =>
      "remote runtime bundle failed"
    @application.Distribution(@remote_standard.JournalClose) =>
      "remote Site journal close failed"
    @application.Distribution(@remote_standard.ClientClose) =>
      "remote Site client close failed"
    @application.OutputCleanupPending =>
      "remote application output cleanup remains pending"
    @application.TransferJournalClose =>
      "remote application Transfer journal close failed"
    _ => "remote application poll failed"
  }
}

///|
fn poll_outcome_json(
  outcome : @application.NativeRemoteApplicationSite,
  publication_store : @publication_store.Store,
  max_chunk_bytes : Int,
) -> Result[String, String] {
  match outcome.poll() {
    Ok(@agent.Idle) => Ok("{\"kind\":\"idle\"}")
    Ok(@agent.OutputRequested(output)) => {
      let request = @remote.remote_poll_output_request(output)
      let intent = @remote.remote_poll_output_intent(output)
      match outcome.execute_output(output, publication_store, max_chunk_bytes) {
        Ok(result) => {
          match outcome.acknowledge_output_result(result) {
            Ok(_) => ()
            Err(_) => return Err("remote output acknowledgement failed")
          }
          Ok(
            "{\"kind\":\"output\",\"request_cid\":\"" +
            @remote.dispatch_request_identity(request) +
            "\",\"intent_cid\":\"" +
            @remote.remote_output_intent_identity(intent) +
            "\",\"payload_digest\":\"" +
            result.payload.physical_digest +
            "\",\"transfer_request_cid\":\"" +
            @transfer.record_request_identity(result.transfer) +
            "\",\"transfer_revision\":" +
            @transfer.record_revision(result.transfer).to_string() +
            "}",
          )
        }
        Err(issue) => {
          ignore(issue)
          ignore(outcome.retry_output_cleanup())
          if outcome.output_cleanup_pending() {
            Err("remote output cleanup remains pending")
          } else {
            Err("remote output operation failed")
          }
        }
      }
    }
    Ok(@agent.DispatchObserved(request, completion, revision)) =>
      Ok(
        "{\"kind\":\"dispatch\",\"request_cid\":\"" +
        @remote.dispatch_request_identity(request) +
        "\",\"evidence_cid\":\"" +
        completion.evidence_cid +
        "\",\"revision\":" +
        revision.to_string() +
        "}",
      )
    Ok(@agent.QueryObserved(identity, revision)) =>
      Ok(
        "{\"kind\":\"query\",\"request_cid\":\"" +
        identity +
        "\",\"revision\":" +
        revision.to_string() +
        "}",
      )
    Ok(@agent.QueryNotSeen(identity)) =>
      Ok("{\"kind\":\"not-seen\",\"request_cid\":\"" + identity + "\"}")
    Ok(@agent.ReleaseObserved(identity, revision)) =>
      Ok(
        "{\"kind\":\"released\",\"request_cid\":\"" +
        identity +
        "\",\"revision\":" +
        revision.to_string() +
        "}",
      )
    Ok(@agent.ReleasePending(identity, revision)) =>
      Ok(
        "{\"kind\":\"release-pending\",\"request_cid\":\"" +
        identity +
        "\",\"revision\":" +
        revision.to_string() +
        "}",
      )
    Err(issue) => Err(application_issue_message(issue))
  }
}

///|
fn application_files() -> @application.NativeRemoteApplicationFiles {
  {
    program: "program.json",
    environment: "environment.json",
    environment_cid: "environment.cid",
    parameters: "parameters.json",
    registry: "registry.json",
    values: "values.json",
    fragment: "fragment.json",
    query: "query.json",
    evidence: "evidence.json",
    two_receipt: "two-receipt.json",
  }
}

///|
fn execution_limits(
  max_rows : Int,
  max_bytes : Int64,
) -> @application.NativeRemoteApplicationExecutionLimits {
  {
    ledger: {
      planning_work: 1000000,
      attempts: 1024,
      holdings: 1024,
      transfer_bytes: max_bytes,
      retained_bytes: max_bytes,
      execution_bytes: max_bytes,
    },
    native_fixed_ms: 5L,
    resident: false,
    imports: {
      max_rows,
      max_cells: max_rows * 64,
      max_parameters: 8192,
      max_sql_bytes: 1048576,
      max_batch_rows: 128,
    },
    transfer_bytes: max_bytes,
    execution_bytes: max_bytes,
  }
}

///|
fn output_limits(
  max_rows : Int,
  max_bytes : Int64,
) -> @application.NativeRemoteApplicationTaskProfile {
  {
    task_key: "application-task",
    expected_task: 1,
    output: {
      output_export: {
        max_result_fields: 64,
        max_result_mapping_work: 100000,
        max_result_order_work: 1000000,
        max_result_workspace_entries: 100000,
        max_rows,
        values: {
          max_nodes: 1000000,
          max_text_bytes: 1048576,
          max_depth: 64,
          max_work: 10000000,
        },
        payload_wire: {
          max_columns: 64,
          max_order_work: 1000000,
          max_bytes: max_bytes.to_int(),
          max_nodes: 1000000,
          max_depth: 64,
        },
        logical_wire: {
          max_columns: 64,
          max_order_work: 1000000,
          max_bytes: max_bytes.to_int(),
          max_nodes: 1000000,
          max_depth: 64,
        },
        schema: {
          max_fields: 64,
          max_bytes: 1048576,
          max_nodes: 100000,
          max_depth: 64,
        },
        max_batch_bytes: 65536,
      },
      max_manifest_bytes: 1048576,
      max_retained_bytes: max_bytes,
    },
  }
}

///|
fn binding_limits(
  max_bytes : Int64,
) -> @remote_standard.NativeRemoteStandardTransferBindingLimits {
  {
    max_binding_bytes: 1048576,
    max_chunks: 65536,
    max_manifest_bytes: 1048576,
    max_referenced_bytes: max_bytes,
  }
}

///|
fn source_limits(
  max_rows : Int,
  max_bytes : Int64,
) -> @remote_standard.NativeRemoteStandardTransferSourceLimits {
  {
    max_rows,
    max_wire_bytes: max_bytes.to_int(),
    max_read_bytes: 65536,
    max_entries: 1000000,
    max_name_bytes: 1048576,
    values: {
      max_nodes: 1000000,
      max_text_bytes: 1048576,
      max_depth: 64,
      max_work: 10000000,
    },
    wire: {
      max_bytes: 1048576,
      max_nodes: 100000,
      max_depth: 64,
      max_text_bytes: 1048576,
    },
  }
}

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "actql-native-remote-application-site",
    about="Run one verified native ActQL application Site",
    version="0.1",
    options=[
      @argparse.OptionArg("sqlite-library", required=true),
      @argparse.OptionArg("crypto-library", required=true),
      @argparse.OptionArg("http-library", required=true),
      @argparse.OptionArg("duckdb-library", required=true),
      @argparse.OptionArg("application-root", required=true),
      @argparse.OptionArg("transfer-root", required=true),
      @argparse.OptionArg("publication-root", required=true),
      @argparse.OptionArg("publication-authority-cid", required=true),
      @argparse.OptionArg("runtime-root", required=true),
      @argparse.OptionArg("transfer-journal", required=true),
      @argparse.OptionArg("dispatch-journal", required=true),
      @argparse.OptionArg("database-path", required=true),
      @argparse.OptionArg("database-schema", default_values=["main"]),
      @argparse.OptionArg("table", default_values=["records"]),
      @argparse.OptionArg("site-key", required=true),
      @argparse.OptionArg("site-generation", required=true),
      @argparse.OptionArg("target-triple", required=true),
      @argparse.OptionArg("component-cid", required=true),
      @argparse.OptionArg("process-hold-id", required=true),
      @argparse.OptionArg("bundle-issuer", required=true),
      @argparse.OptionArg("bundle-key-id", required=true),
      @argparse.OptionArg("bundle-public-key-root", required=true),
      @argparse.OptionArg("bundle-public-key-file", required=true),
      @argparse.OptionArg("ca", required=true),
      @argparse.OptionArg("cert", required=true),
      @argparse.OptionArg("key", required=true),
      @argparse.OptionArg("poll-url", required=true),
      @argparse.OptionArg("observation-url", required=true),
      @argparse.OptionArg("operation-capability-cid", required=true),
      @argparse.OptionArg("issuer-capability-cid", required=true),
      @argparse.OptionArg("input-schema-cid", required=true),
      @argparse.OptionArg("input-view-cid", required=true),
      @argparse.OptionArg("input-codec-cid", required=true),
      @argparse.OptionArg("task-key", required=true),
      @argparse.OptionArg("expected-task", required=true),
      @argparse.OptionArg("max-polls", default_values=["0"]),
      @argparse.OptionArg("max-rows", default_values=["100000"]),
      @argparse.OptionArg("max-bytes", default_values=["268435456"]),
      @argparse.OptionArg("max-file-bytes", default_values=["1048576"]),
      @argparse.OptionArg("max-record-bytes", default_values=["1048576"]),
      @argparse.OptionArg("max-operations", default_values=["64"]),
      @argparse.OptionArg("max-transfers", default_values=["64"]),
      @argparse.OptionArg("output-chunk-bytes", default_values=["65536"]),
    ],
  )
}

///|
fn execute_checked(matches : @argparse.Matches) -> Unit raise CommandStop {
  let max_rows = required_int(matches, "max-rows")
  let max_bytes = required_int64(matches, "max-bytes")
  let max_file_bytes = required_int64(matches, "max-file-bytes")
  let max_record_bytes = required_int64(matches, "max-record-bytes")
  let max_polls = required_int(matches, "max-polls")
  let expected_task = required_int(matches, "expected-task")
  let generation = required_int(matches, "site-generation")
  let max_operations = required_int(matches, "max-operations")
  let max_transfers = required_int(matches, "max-transfers")
  let output_chunk_bytes = required_int(matches, "output-chunk-bytes")
  if max_rows < 1 ||
    max_bytes < 1L ||
    max_bytes > 2147483647L ||
    max_file_bytes < 1L ||
    max_record_bytes < 1L ||
    max_polls < 0 ||
    expected_task < 1 ||
    generation < 0 ||
    max_operations < 1 ||
    max_transfers < 1 ||
    output_chunk_bytes < 1 ||
    output_chunk_bytes.to_int64() > max_bytes {
    stop("invalid application Site limits")
  }
  let sqlite_path = required(matches, "sqlite-library")
  let crypto_path = required(matches, "crypto-library")
  let http_path = required(matches, "http-library")
  let duckdb_path = required(matches, "duckdb-library")
  let application_root = required(matches, "application-root")
  let transfer_root_path = required(matches, "transfer-root")
  let publication_root_path = required(matches, "publication-root")
  let publication_authority = required(matches, "publication-authority-cid")
  let runtime_root = required(matches, "runtime-root")
  if publication_root_path == transfer_root_path ||
    publication_root_path == runtime_root ||
    transfer_root_path == runtime_root {
    stop("application Site roots must be distinct")
  }
  let transfer_journal_path = required(matches, "transfer-journal")
  let dispatch_journal_path = required(matches, "dispatch-journal")
  let database_path = required(matches, "database-path")
  let database_schema = required(matches, "database-schema")
  let table = required(matches, "table")
  let site_key = required(matches, "site-key")
  let target = required(matches, "target-triple")
  let component_cid = required(matches, "component-cid")
  let process_hold_id = required(matches, "process-hold-id")
  let bundle_issuer = required(matches, "bundle-issuer")
  let bundle_key_id = required(matches, "bundle-key-id")
  let public_key_root = required(matches, "bundle-public-key-root")
  let public_key_file = required(matches, "bundle-public-key-file")
  let ca = required(matches, "ca")
  let cert = required(matches, "cert")
  let key = required(matches, "key")
  let poll_url = required(matches, "poll-url")
  let observation_url = required(matches, "observation-url")
  let operation_capability = required(matches, "operation-capability-cid")
  let issuer_capability = required(matches, "issuer-capability-cid")
  let input_schema_cid = required(matches, "input-schema-cid")
  let input_view_cid = required(matches, "input-view-cid")
  let input_codec_cid = required(matches, "input-codec-cid")
  let task_key = required(matches, "task-key")
  let sqlite_library = match @sqlite.load_library(sqlite_path) {
    Ok(value) => value
    Err(_) => stop("SQLite library load failed")
  }
  let signature_library = match @signature.load_library(crypto_path) {
    Ok(value) => value
    Err(_) => stop("signature library load failed")
  }
  let public_key = load_text(public_key_root, public_key_file, max_file_bytes)
  let bundles = match
    @bundle.open_runtime_bundle_store(
      sqlite_library,
      signature_library,
      runtime_root,
      [
        {
          issuer_authority: bundle_issuer,
          key_id: bundle_key_id,
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
    Err(_) => stop("runtime bundle Store open failed")
  }
  let active = match bundles.active() {
    Ok(Some(value)) => value
    _ => {
      ignore(bundles.close())
      stop("active runtime bundle is missing")
    }
  }
  let active_runtime = match
    bundles.acquire_active_component(component_cid, target, process_hold_id) {
    Ok(value) => value
    Err(_) => {
      ignore(bundles.close())
      stop("active runtime component verification failed")
    }
  }
  let site = match
    @site.create_site(
      site_key,
      generation,
      active.runtime_bundle_cid,
      max_operations,
      max_transfers,
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
  let dispatch_control = match
    @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1") {
    Ok(value) => value
    Err(_) => {
      ignore(bundles.release(process_hold_id))
      ignore(bundles.close())
      stop("invalid dispatch journal binding")
    }
  }
  let dispatch_journal = match
    @journal.open_journal(
      sqlite_library, dispatch_journal_path, max_record_bytes, dispatch_control,
    ) {
    Ok(value) => value
    Err(_) => {
      ignore(bundles.release(process_hold_id))
      ignore(bundles.close())
      stop("dispatch journal open failed")
    }
  }
  let transfer_journal = match
    @transfer_journal.open_journal(
      sqlite_library, transfer_journal_path, max_record_bytes, 65536, 1048576, max_bytes,
    ) {
    Ok(value) => value
    Err(_) => {
      ignore(dispatch_journal.close())
      ignore(bundles.release(process_hold_id))
      ignore(bundles.close())
      stop("Transfer journal open failed")
    }
  }
  let transfer_root = match @filesystem.open_root(transfer_root_path) {
    Ok(value) => value
    Err(_) => {
      ignore(transfer_journal.close())
      ignore(dispatch_journal.close())
      ignore(bundles.release(process_hold_id))
      ignore(bundles.close())
      stop("Transfer root open failed")
    }
  }
  let http_library = match @http.load_library(http_path) {
    Ok(value) => value
    Err(_) => {
      ignore(transfer_journal.close())
      ignore(dispatch_journal.close())
      ignore(bundles.release(process_hold_id))
      ignore(bundles.close())
      stop("HTTP library load failed")
    }
  }
  let client = match
    http_library.create_client(ca, cert, key, max_record_bytes, 2000, 30000) {
    Ok(value) => value
    Err(_) => {
      ignore(transfer_journal.close())
      ignore(dispatch_journal.close())
      ignore(bundles.release(process_hold_id))
      ignore(bundles.close())
      stop("HTTP client creation failed")
    }
  }
  let native_duckdb = match @duckdb.load_library(duckdb_path) {
    Ok(value) => value
    Err(_) => {
      ignore(client.close())
      ignore(transfer_journal.close())
      ignore(dispatch_journal.close())
      ignore(bundles.release(process_hold_id))
      ignore(bundles.close())
      stop("DuckDB library load failed")
    }
  }
  let app = match
    @application.load_native_remote_application(
      application_root,
      application_files(),
      max_file_bytes,
      database_schema,
      table,
    ) {
    Ok(value) => value
    Err(_) => {
      ignore(client.close())
      ignore(transfer_journal.close())
      ignore(dispatch_journal.close())
      ignore(bundles.release(process_hold_id))
      ignore(bundles.close())
      stop("application admission failed")
    }
  }
  let codec = match
    @remote_standard.register_native_remote_standard_row_codec(
      input_schema_cid, input_view_cid, input_codec_cid,
    ) {
    Ok(value) => value
    Err(_) => {
      ignore(client.close())
      ignore(transfer_journal.close())
      ignore(dispatch_journal.close())
      ignore(bundles.release(process_hold_id))
      ignore(bundles.close())
      stop("input codec registration failed")
    }
  }
  let task = output_limits(max_rows, max_bytes)
  let task = { ..task, task_key, expected_task, }
  let budget = match
    @remote.prepare_remote_dispatch_budget(max_bytes, max_bytes) {
    Ok(value) => value
    Err(_) => {
      ignore(client.close())
      ignore(transfer_journal.close())
      ignore(dispatch_journal.close())
      ignore(bundles.release(process_hold_id))
      ignore(bundles.close())
      stop("dispatch budget admission failed")
    }
  }
  let publication_store = match
    @publication_store.open_store(
      sqlite_library,
      publication_root_path,
      publication_authority,
      max_bytes,
      max_transfers.to_int64(),
      max_record_bytes,
    ) {
    Ok(value) => value
    Err(_) => {
      ignore(client.close())
      ignore(transfer_journal.close())
      ignore(dispatch_journal.close())
      ignore(bundles.release(process_hold_id))
      ignore(bundles.close())
      stop("publication Store open failed")
    }
  }
  let application_site = match
    @application.open_native_remote_application_store_site_distribution(
      app,
      transfer_journal,
      transfer_root,
      codec,
      binding_limits(max_bytes),
      source_limits(max_rows, max_bytes),
      execution_limits(max_rows, max_bytes),
      task,
      site,
      active_runtime,
      operation_capability,
      issuer_capability,
      dispatch_journal,
      bundles,
      [budget],
      client,
      poll_url,
      observation_url,
      library=Some(native_duckdb),
      database_path~,
    ) {
    Ok(value) => value
    Err(_) => {
      ignore(publication_store.close())
      ignore(client.close())
      ignore(transfer_journal.close())
      ignore(dispatch_journal.close())
      ignore(bundles.release(process_hold_id))
      ignore(bundles.close())
      stop("application Site composition failed")
    }
  }
  let mut poll_failure : String? = None
  let mut polls = 0
  let mut closed = false
  while !closed && (max_polls == 0 || polls < max_polls) {
    polls += 1
    match
      poll_outcome_json(application_site, publication_store, output_chunk_bytes) {
      Ok(result) => {
        println(result)
        if result == "{\"kind\":\"idle\"}" {
          match application_site.close() {
            Ok(_) => closed = true
            Err(_) => ()
          }
        }
      }
      Err(issue) => {
        poll_failure = Some(issue)
        break
      }
    }
  }
  let close_failure = if closed {
    None
  } else {
    match application_site.close() {
      Ok(_) => None
      Err(_) => Some("application Site cleanup remains pending")
    }
  }
  let publication_close_failure = match publication_store.close() {
    Ok(_) => None
    Err(_) => Some("publication Store cleanup remains pending")
  }
  let failures : Array[String] = []
  match poll_failure {
    Some(value) => failures.push(value)
    None => ()
  }
  match close_failure {
    Some(value) => failures.push(value)
    None => ()
  }
  match publication_close_failure {
    Some(value) => failures.push(value)
    None => ()
  }
  if !failures.is_empty() {
    stop(failures.join("; "))
  }
}

///|
fn execute(matches : @argparse.Matches) -> Result[Unit, String] {
  try {
    execute_checked(matches)
    Ok(())
  } catch {
    CommandStop(issue) => Err(issue)
  }
}

///|
fn main {
  let matches = command().parse() catch { error => abort(error.to_string()) }
  match execute(matches) {
    Ok(_) => ()
    Err(issue) => abort("actql-native-remote-application-site: " + issue)
  }
}
