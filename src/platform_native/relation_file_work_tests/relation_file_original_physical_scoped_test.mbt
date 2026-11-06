///|
// This is a finite test installation, not the bundled CLI profile. Its manifest
// reader observes actual component bytes and its generic Account/Adoption
// owners select the configuration before any Submission or Source attempt.
fn[T, E] Result::relation_original_value(
  self : Result[T, E],
  stage : String,
) -> T raise {
  match self {
    Ok(value) => value
    Err(_) => fail(stage)
  }
}

///|
#borrow(path)
extern "C" fn relation_original_open(path : Bytes, flags : Int) -> Int = "open"

///|
extern "C" fn relation_original_close(fd : Int) -> Int = "close"

///|
let relation_original_document : String =
  #|{"version":"actql/0.1","id":"native-file-capture","stages":[{"id":"acquire","inputs":{"remote":{"connector":"native-file-fixture","resource":"records"}},"steps":[{"filter":"value > 1"},{"select":["id","value"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","value"]}}},{"id":"compute","inputs":{"input":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"filter":"value > 0"},{"select":["id","value"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","value"]}}}],"results":{"rows":{"from":{"stage":"compute","result":"rows"}}}}

///|
fn relation_original_declaration(wire : String) -> @rows.RowDeclaration raise {
  guard @json.parse(wire) is Object(root) &&
    root.get("connector_id") is Some(String(connector)) &&
    root.get("connector_registration") is Some(String(registration)) &&
    root.get("connector_version") is Some(String(version)) &&
    root.get("views") is Some(views) else {
    fail("invalid selected declaration")
  }
  let body : Json = { "views": views }
  @rows.restore_row_declaration(
    connector,
    registration,
    version,
    body.stringify(),
    None,
  ).relation_original_value("restore selected original declaration")
}

///|
// Test diagnostics preserve the original lower issue without changing its
// production type, cleanup owner or library acquisition behavior.
fn relation_original_sqlite_issue(issue : @sqlite.NativeSqliteIssue) -> String {
  match issue {
    UnsupportedTarget => "UnsupportedTarget"
    InvalidName => "InvalidName"
    InvalidLimit => "InvalidLimit"
    LibraryLoad(message) => "LibraryLoad: " + message
    DatabaseOpen(message) => "DatabaseOpen: " + message
    DatabaseClosed => "DatabaseClosed"
    NotFound => "NotFound"
    Collision => "Collision"
    Busy => "Busy"
    BodyTooLarge => "BodyTooLarge"
    CapacityExceeded => "CapacityExceeded"
    Physical(message) => "Physical: " + message
    OperationRoutingBefore(code) => "OperationRoutingBefore: \{code}"
    OperationRoutingAfter(primary, code) =>
      "OperationRoutingAfter: \{code} " +
      (match primary {
        None => "None"
        Some(issue) => relation_original_sqlite_issue(issue)
      })
  }
}

///|
fn relation_initial_open_filesystem_issue(
  issue : @filesystem.NativeFilesystemIssue,
) -> String {
  match issue {
    UnsupportedTarget => "UnsupportedTarget"
    InvalidName => "InvalidName"
    InvalidLimit => "InvalidLimit"
    RootOpen(message) => "RootOpen: " + message
    Lock(message) => "Lock: " + message
    WriterCreate(message) => "WriterCreate: " + message
    CapacityExceeded => "CapacityExceeded"
    WriterClosed => "WriterClosed"
    Write(message) => "Write: " + message
    Conflict => "Conflict"
    GenerationMismatch => "GenerationMismatch"
    InvalidReadSize => "InvalidReadSize"
    IncompleteRead => "IncompleteRead"
    ReaderClosed => "ReaderClosed"
    Read(message) => "Read: " + message
    Seal(message) => "Seal: " + message
    Cleanup(message) => "Cleanup: " + message
  }
}

///|
// Initial-open diagnostics only: later Journal/arena issue variants cannot
// originate from this constructor. Keep that boundary explicit rather than
// pretend this is a complete Journal formatter. No observation or cleanup runs.
fn relation_initial_open_adoption_issue(
  issue : @client.NativeLocalAdoptionIssue,
) -> String {
  match issue {
    InvalidInput => "InvalidInput"
    ConfigurationLimit => "ConfigurationLimit"
    Configuration(reason) => "Configuration: " + @debug.to_string(reason)
    ForeignAccount => "ForeignAccount"
    UninstalledBootstrapProfile => "UninstalledBootstrapProfile"
    CustodyLost => "CustodyLost"
    SourceChanged => "SourceChanged"
    AmbiguousInitialization => "AmbiguousInitialization"
    Closed => "Closed"
    Encoding => "Encoding"
    Crypto(reason) => "Crypto: " + @debug.to_string(reason)
    Filesystem(reason) =>
      "Filesystem: " + relation_initial_open_filesystem_issue(reason)
    ReadAcquisitionFailure(original) =>
      "ReadAcquisitionFailure: " +
      relation_initial_open_filesystem_issue(original.issue())
    ReadPending(_, reason) =>
      "ReadPending: " + relation_initial_open_filesystem_issue(reason)
    WritePending(_, reason) =>
      "WritePending: " + relation_initial_open_filesystem_issue(reason)
    Physical(reason) => "Physical: " + relation_original_sqlite_issue(reason)
    Epoch(_) => "unexpected during initial open: Epoch"
    Journal(_) => "unexpected during initial open: Journal"
    Fenced => "unexpected during initial open: Fenced"
    TransactionUnknown => "unexpected during initial open: TransactionUnknown"
    DatabasePending(_, _) => "unexpected during initial open: DatabasePending"
    Inspection(_) => "unexpected during initial open: Inspection"
    InstallationReadTransactionFailure(_, _) =>
      "unexpected during initial open: InstallationReadTransactionFailure"
    OriginalResources(_) => "unexpected during initial open: OriginalResources"
    OriginalResourceScopePending =>
      "unexpected during initial open: OriginalResourceScopePending"
    OriginalResourceLeave(_, _) =>
      "unexpected during initial open: OriginalResourceLeave"
    InspectionCleanup(_) => "unexpected during initial open: InspectionCleanup"
    InspectionPending(_, _, _) =>
      "unexpected during initial open: InspectionPending"
  }
}

///|
fn relation_initial_open_issue(
  issue : @client.NativeLocalAdoptionCaptureIssue,
) -> String {
  match issue {
    AdoptionNotOpened => "AdoptionNotOpened"
    AdoptionOpeningUnconfirmed => "AdoptionOpeningUnconfirmed"
    AdoptionCaptureClosed => "AdoptionCaptureClosed"
    AdoptionJournalAlreadyCaptured => "AdoptionJournalAlreadyCaptured"
    AdoptionOriginal(original) => relation_initial_open_adoption_issue(original)
    AdoptionJournal(_) => "unexpected during initial open: AdoptionJournal"
  }
}

///|
fn relation_original_limits() -> @row_file.NativeRelationFileLimits {
  {
    page: { max_bytes: 8192, max_nodes: 512, max_depth: 8, max_rows: 2, },
    max_work: 1000000,
    chunk_bytes: 7,
    diagnostic_ceiling: 128,
  }
}

///|
fn relation_original_selection(
  directory : String,
) -> @row_file.NativeRelationFileSelection {
  {
    directory,
    name: "records.json",
    resource: "records",
    items_path: ["items"],
    key_path: None,
    primary_identity: "id",
  }
}

///|
// Compare borrowed UTF-16 units without a slice, decoded value, iterator,
// accumulator or copied chunk. The result is only a scalar cursor or refusal.
fn relation_original_match_chunk(
  expected : String,
  offset : Int,
  chunk : String,
) -> Int {
  if offset < 0 ||
    offset > expected.length() ||
    chunk.length() > expected.length() - offset {
    return -1
  }
  let mut index = 0
  while index < chunk.length() {
    if chunk.code_unit_at(index) != expected.code_unit_at(offset + index) {
      return -1
    }
    index += 1
  }
  offset + chunk.length()
}

///|
// PublicationOutputExport is a canonical JSON array stream, not a row
// iterator. None ends the rows; finish still supplies the final document tail.
// This independent literal does not encode any particular chunk boundary.
// Every borrowed chunk/result dies in this helper before caller cleanup.
fn relation_original_export_matches(
  exported : @host.PublicationOutputExport,
) -> Bool {
  let expected = "[{\"id\":\"second\",\"value\":2}]"
  let mut offset = 0
  let mut polls = 0
  // Each nonempty next chunk consumes at least one expected code unit. One
  // final None poll is allowed; malformed/no-progress streams fail finitely.
  while polls <= expected.length() {
    polls += 1
    match exported.next() {
      Err(_) => return false
      Ok(Some(chunk)) => {
        if chunk.is_empty() {
          return false
        }
        offset = relation_original_match_chunk(expected, offset, chunk)
        if offset < 0 {
          return false
        }
      }
      Ok(None) =>
        return match exported.finish() {
          Err(_) => false
          Ok(tail) =>
            relation_original_match_chunk(expected, offset, tail) ==
            expected.length()
        }
    }
  }
  false
}

///|
// Public quote DATA only, executed in this same selected physical case's outer
// test setup. The constants independently expand original construction recipes;
// no maximum quote is a resource grant or actual maximum-size Source execution.
fn relation_original_verify_quote_vectors() -> Unit raise {
  let selection = relation_original_selection("/fixture")
  let fixture_limits = relation_original_limits()
  for
    (page, path_count, key_count, source_bytes, work_bytes, read_bytes) in [
      (
        @rows.RowPageLimits::{
          max_bytes: 1,
          max_nodes: 1,
          max_depth: 1,
          max_rows: 1,
        },
        1,
        0,
        222451L,
        270469L,
        29346L,
      ),
      (
        @rows.RowPageLimits::{
          max_bytes: 8192,
          max_nodes: 512,
          max_depth: 8,
          max_rows: 2,
        },
        1,
        0,
        23075950L,
        23123968L,
        29346L,
      ),
      (
        @rows.RowPageLimits::{
          max_bytes: 65536,
          max_nodes: 8192,
          max_depth: 32,
          max_rows: 100,
        },
        16,
        16,
        296410702L,
        296458720L,
        32770L,
      ),
    ] {
    let selected = {
      ..selection,
      items_path: Array::make(path_count, "items"),
      key_path: if key_count == 0 {
        None
      } else {
        Some(Array::make(key_count, "key"))
      },
    }
    let limits = { ..fixture_limits, page, }
    assert_eq(
      @execution.preparation_representation_cost(
        @row_file.native_relation_file_caller_preparation_inventory(
          selected, limits,
        ).unwrap(),
      ).unwrap(),
      source_bytes,
    )
    let work = @client.native_relation_file_work_control_capacity(
      selected, limits,
    ).unwrap()
    let read = @client.native_relation_file_entry_read_capacity(
      selected, limits,
    ).unwrap()
    assert_eq(@execution.execution_capacity_retained_bytes(work), work_bytes)
    assert_eq(@execution.execution_capacity_execution_bytes(work), work_bytes)
    assert_eq(@execution.execution_capacity_retained_bytes(read), read_bytes)
    assert_eq(@execution.execution_capacity_execution_bytes(read), read_bytes)
  }
  for
    page in [
      @rows.RowPageLimits::{
        max_bytes: 65537,
        max_nodes: 8192,
        max_depth: 32,
        max_rows: 100,
      },
      @rows.RowPageLimits::{
        max_bytes: 65536,
        max_nodes: 8193,
        max_depth: 32,
        max_rows: 100,
      },
      @rows.RowPageLimits::{
        max_bytes: 65536,
        max_nodes: 8192,
        max_depth: 33,
        max_rows: 100,
      },
      @rows.RowPageLimits::{
        max_bytes: 65536,
        max_nodes: 8192,
        max_depth: 32,
        max_rows: 101,
      },
    ] {
    assert_true(
      @row_file.native_relation_file_caller_preparation_inventory(selection, {
        ..fixture_limits,
        page,
      })
      is None,
    )
    assert_true(
      @client.native_relation_file_work_control_capacity(selection, {
        ..fixture_limits,
        page,
      })
      is None,
    )
    assert_true(
      @client.native_relation_file_entry_read_capacity(selection, {
        ..fixture_limits,
        page,
      })
      is None,
    )
  }
  assert_true(
    @row_file.native_relation_file_caller_preparation_inventory(
      { ..selection, items_path: Array::make(17, "items"), },
      fixture_limits,
    )
    is None,
  )
  assert_true(
    @row_file.native_relation_file_caller_preparation_inventory(
      { ..selection, key_path: Some(Array::make(17, "key")), },
      fixture_limits,
    )
    is None,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(
      @client.native_relation_file_entry_outer_capacity().unwrap(),
    ),
    2842L,
  )
}

///|
// All generated owners below are actual input preparation. The expected result
// and exact received byte count are independently authored assertions.
fn relation_original_run(
  physical : @arena.InstalledArenaHost,
  pair : @arena.InstalledArenaLocalHostResources,
  read : @arena.InstalledArenaOriginalRead,
  runtime : @client.NativeLocalPackagedRuntime,
  descriptor : Int,
  business_domain : Ref[@arena.InstalledArenaDomain?],
  business_execution : Ref[@arena.InstalledArenaRetainedExecution?],
  fixture : String,
  crypto_path : String,
) -> Unit raise {
  let mib = 1048576L
  let mode = @env.get_env_var("ACTQL_TEST_RELATION_ORIGINAL_MODE").unwrap_or(
    "positive",
  )
  physical
  .enter_local_host_phase(pair, @arena.HostRead)
  .relation_original_value("adoption Read enter")
  let component = match
    physical
    .prepare_local_host_read_crypto(pair, read, crypto_path, 2L * mib, 128)
    .relation_original_value("Crypto component") {
    @arena.ReadyCrypto(value) => value
    @arena.PendingCrypto(_, _) => fail("Crypto component pending")
  }
  let crypto_original = physical
    .current_crypto_component(component)
    .relation_original_value("Crypto original")
  let crypto = match
    crypto_original.new_library().relation_original_value("Crypto Library") {
    @crypto.ReadyCryptoLibrary(value) => value
    @crypto.PendingCryptoLibrary(_, _) => fail("Crypto Library pending")
  }
  let adoption = @client.prepare_native_local_initial_adoption_capture_in_current_read_context(
    {
      parent_path: fixture,
      state_name: "state",
      source_path: fixture,
      source_name: "account.json",
      account_id: "operator",
      configuration_files: [
        "environment.json", "run.json", "runtime.json", "row-declaration.json",
      ],
      managed_root_path: None,
    },
    crypto,
    128,
  ).relation_original_value("prepare original Adoption")
  // Open once. The same capture retains the original issue and partial owners;
  // formatting a refusal must not retry acquisition or erase its cleanup duty.
  if adoption.open().issue() is Some(issue) {
    fail("initial Adoption open: " + relation_initial_open_issue(issue))
  }
  let session = adoption.original_session().unwrap()
  let material = session
    .create_initial_signing_material(crypto)
    .relation_original_value("initial signing")
  let capture = adoption
    .capture_initial_journal_with_original_resources(
      physical,
      pair,
      read,
      material,
      @host.client_local_default_signing_bootstrap_policy(),
      60000.0,
      8,
      8388608L,
    )
    .relation_original_value("original Journal capture")
  physical
  .leave_local_host_phase(pair)
  .relation_original_value("adoption Read leave")
  let operation : Ref[@client.NativeLocalStoreOperation?] = Ref(None)
  let foreign_operation : Ref[@client.NativeLocalStoreOperation?] = Ref(None)
  let body : Ref[Result[Unit, String]?] = Ref(None)
  let prepared_entry : Ref[@client.NativeClientRelationFileWorkEntry?] = Ref(
    None,
  )
  let escaped_work : Ref[@client.NativeClientRelationFileWork?] = Ref(None)
  let escaped_failure : Ref[@client.NativeClientRelationFileWorkFailure?] = Ref(
    None,
  )
  let entry = capture.with_original_read(fn(host) {
    let result = try {
      capture
      .bind_packaged_runtime_in_original_read(
        runtime, "machine-user", "cli", "environment.json", "run.json", "runtime.json",
      )
      .relation_original_value("bind original Runtime")
      let (assets, contracts) = runtime
        .installed_assets()
        .relation_original_value("installed original assets")
      let source_limits = relation_original_limits()
      let fragment = Some(assets.fragment)
      let configuration = capture
        .configuration_in_original_read()
        .relation_original_value("original configuration")
      let scope = capture
        .authority_scope_cid_in_original_read("machine-user", "cli")
        .relation_original_value("original scope")
      guard @json.parse(assets.environment) is Object(environment_body) &&
        environment_body.get("evidence_bundle_cid") is Some(String(cid)) else {
        fail("missing environment identity")
      }
      let environment = @host.admit_client_check_environment(
        assets.environment,
        cid,
        { text_time: false, veca: false, },
        {
          rela: true,
          sga: false,
          tea: false,
          calendar: false,
          text_rank: false,
        },
      ).unwrap()
      let intent = @host.prepare_client_submitted_intent(
        "{\"kind\":\"program\",\"input\":" +
        relation_original_document +
        ",\"parameters\":null}",
        65536,
        8192,
        64,
      ).relation_original_value("submitted intent")
      let preparation = @client.prepare_native_client_submitted_program(
        intent,
        environment,
        None,
        [],
        @host.client_standard_effect_computation_limits(),
      ).relation_original_value("ordinary Source preparation")
      guard @client.native_client_submitted_preparation(preparation)
        is Computation(prepared) else {
        fail("Source computation missing")
      }
      let declaration_wire = @utf8.decode(
        capture
        .selected_configuration_in_original_read("row-declaration.json")
        .relation_original_value("selected original declaration"),
      )
      let declaration = relation_original_declaration(declaration_wire)
      let requirement = @local.prepare_local_query_requirement(
        prepared,
        0,
        0,
        contracts,
        assets.values,
        fragment,
        assets.ordered,
      ).relation_original_value("original requirement")
      let acquisition = @rows.prepare_row_acquisition(
        declaration, requirement, relation_original_query_contract, relation_original_evidence_contract,
      ).relation_original_value("original acquisition")
      let requirements = @local.prepare_captured_local_requirements(
        prepared,
        contracts,
        assets.values,
        fragment,
        assets.ordered,
      ).unwrap()
      let selection = relation_original_selection(fixture)
      let source_quote = @row_file.native_relation_file_capture_limits(
        declaration, requirement, acquisition, selection, source_limits,
      ).relation_original_value("Source quote")
      let compute_quote = requirements.simultaneous_limits().unwrap()
      let control = @client.native_relation_file_work_control_capacity(
        selection, source_limits,
      ).unwrap()
      let combined = @resources.add_ledger_limits(
        { ..source_quote, attempts: 0, holdings: 0, },
        compute_quote,
      ).unwrap()
      let selected : @resources.LedgerLimits = {
        ..combined,
        retained_bytes: combined.retained_bytes +
        @execution.execution_capacity_retained_bytes(control) -
        (if mode == "short-capacity" { 127L } else { 0L }),
        execution_bytes: combined.execution_bytes +
        @execution.execution_capacity_execution_bytes(control),
      }
      assert_true(
        selected.planning_work <= 100000 &&
        selected.attempts <= 16 &&
        selected.holdings <= 8,
      )
      assert_true(
        selected.transfer_bytes <= 8L * mib &&
        selected.retained_bytes <= 180L * mib &&
        selected.execution_bytes <= 360L * mib,
      )
      // No-VM delegation counts retained and execution together. Keep the
      // independently quoted logical limits and require the selected provider's
      // actual control/context coexistence inside this finite physical extent.
      let business_payload = selected.retained_bytes + selected.execution_bytes
      let business_necessary = @bootstrap.execution_domain_necessary_bytes(
        536L * mib,
        business_payload,
      )
      if business_payload > 536L * mib ||
        business_necessary <= 0L ||
        business_necessary > 536L * mib {
        fail(
          "business physical fit refused: payload=\{business_payload} necessary=\{business_necessary} extent=\{536L * mib}",
        )
      }
      assert_true(business_payload <= 536L * mib)
      assert_true(business_necessary > 0L && business_necessary <= 536L * mib)
      let library = physical
        .borrow_local_host_sqlite(pair)
        .relation_original_value("original SQLite Library")
      capture
      .suspend_original_read_for_preparation()
      .relation_original_value("suspend original Read")
      let backing = physical
        .borrow_backing()
        .relation_original_value("business backing borrow")
      physical
      .enter_backing_borrow_scope(backing)
      .relation_original_value("business backing entry")
      let domain = match
        physical
        .prepare_domain(backing, descriptor, 536L * mib, selected)
        .relation_original_value("quoted business domain") {
        @arena.PreparedDomain(value) => value
        @arena.PendingDomain(value, issue) => {
          business_domain.val = Some(value)
          fail("business domain pending: " + @debug.to_string(issue))
        }
      }
      business_domain.val = Some(domain)
      physical
      .transfer_domain(domain)
      .relation_original_value("business domain transfer")
      physical
      .leave_backing_borrow_scope(backing)
      .relation_original_value("business backing leave")
      physical
      .return_backing_borrow(backing)
      .relation_original_value("business backing return")
      physical
      .prepare_domain_read(domain)
      .relation_original_value("business original Read context")
      let execution = match
        physical
        .prepare_domain_retained_execution(domain)
        .relation_original_value("quoted retained execution") {
        @arena.ReadyRetainedExecution(value) => value
        @arena.PendingRetainedExecution(value, _) => {
          business_execution.val = Some(value)
          fail("retained execution pending")
        }
      }
      business_execution.val = Some(execution)
      operation.val = Some(
        @client.prepare_native_local_store_operation(
          capture, execution, runtime, library,
        ).relation_original_value("original Store operation"),
      )
      foreign_operation.val = Some(
        @client.prepare_native_local_store_operation(
          capture, execution, runtime, library,
        ).relation_original_value("unactivated foreign operation"),
      )
      capture
      .resume_original_read_after_preparation()
      .relation_original_value("resume original Read")
      let operation = operation.val.unwrap()
      operation
      .activate()
      .relation_original_value("activate original Store operation")
      let epoch = capture
        .issue_epoch_in_original_read("machine-user", "cli", scope, 1000.0)
        .relation_original_value("original epoch")
      let reference = @client.prepare_native_client_submission_reference(
        epoch, "original-relation",
      ).relation_original_value("submission reference")
      let request = @host.prepare_client_request_identity(
        prepared,
        scope,
        @client.native_client_submission_request_id(reference),
        @host.client_submitted_intent_cid(intent),
      ).relation_original_value("request identity")
      let manifests = @host.admit_client_compilation_manifests(
        @environment.compiler_grammar_manifest_wire(),
        @environment.compiler_barrier_contract_manifest_wire(),
        10000,
        1000,
        20,
      ).relation_original_value("compiler manifests")
      let compilation = @host.issue_prepared_client_task_compilation(
        prepared,
        manifests,
        @host.client_standard_values_sequence_limits(),
        1000,
        1000,
        65536,
        8192,
        64,
      ).relation_original_value("actual task compilation")
      let compiled = @host.issue_client_task_compiled_run(
        prepared,
        compilation,
        scope,
        configuration.configuration_cid(),
        "2099-01-01T00:00:00.000Z",
      ).relation_original_value("compiled original Run")
      let definition = @host.issue_client_compiled_run_definition(
        compiled,
        "original-relation-fixture",
        @client.native_client_submission_request_id(reference),
        "2026-11-06T00:00:00.000Z",
        "2099-01-01T00:00:00.000Z",
      ).relation_original_value("original Run definition")
      capture
      .record_submitted_intent_in_original_read(
        "machine-user", "cli", scope, reference, intent, 1001.0,
      )
      .relation_original_value("record original intent")
      |> ignore
      capture
      .accept_submitted_run_in_original_read(
        "machine-user", "cli", scope, reference, preparation, request, compiled,
        definition, 1002.0,
      )
      .relation_original_value("accept original Run")
      |> ignore
      if mode == "positive" {
        // A genuine unrelated opaque reservation refuses client entry before
        // any business allocation. Its unused owner can then dispose it in Read.
        let unrelated = match
          physical
          .prepare_domain_nonmodel_work_entry(pair, read, execution, 1L, 1L)
          .unwrap()
          .relation_original_value("unrelated original token") {
          @arena.ReadyNonModelWorkEntry(value) => value
          @arena.PendingNonModelWorkEntry(_) => fail("unrelated token pending")
        }
        match
          host
          .prepare_original_relation_file_work_entry(
            operation, "machine-user", "cli", request, prepared, compiled, definition,
            declaration, requirement, acquisition, selection, source_limits,
          )
          .unwrap() {
          Ok(_) => fail("unrelated original token admitted Work entry")
          Err(failure) => assert_true(failure.close())
        }
        assert_eq(unrelated.usage().attempts, 0)
        assert_eq(unrelated.usage().transferred_bytes, 0L)
        assert_true(unrelated.cancel_unclaimed_in_original_read())
      }
      let selected_declaration = if mode == "foreign-declaration" {
        relation_original_declaration(declaration_wire)
      } else {
        declaration
      }
      let original_entry = match
        host
        .prepare_original_relation_file_work_entry(
          operation,
          "machine-user",
          "cli",
          request,
          prepared,
          compiled,
          definition,
          selected_declaration,
          requirement,
          acquisition,
          if mode == "wrong-selection" {
            { ..selection, resource: "different", }
          } else {
            selection
          },
          source_limits,
        )
        .unwrap() {
        Ok(value) => value
        Err(failure) => {
          escaped_failure.val = Some(failure)
          fail("original entry preparation refused")
        }
      }
      // Save the exact Read-side receiver before any entered child or lost return.
      prepared_entry.val = Some(original_entry)
      // The entry owns its path DATA snapshot, not a mutable caller alias.
      // Actual capture below must still read the original "items" selection.
      selection.items_path[0] = "changed-after-entry"
      assert_eq(original_entry.usage().attempts, 0)
      assert_eq(original_entry.usage().holdings, 0)
      assert_eq(original_entry.usage().live_reservations, 1)
      // This fixture-owned projection is Read preparation (360 bytes), not
      // business allocation funded retroactively by Work's own export quote.
      let (_, export_limits) = requirements
        .publication_limits(prepared, 65536)
        .unwrap()
      operation
      .enter_business_from_original_read()
      .relation_original_value("funded original business entry")
      // Wrong-scope preparation returns inline None, before any failure carrier.
      assert_true(
        host.prepare_original_relation_file_work_entry(
          operation, "machine-user", "cli", request, prepared, compiled, definition,
          declaration, requirement, acquisition, selection, source_limits,
        )
        is None,
      )

      let before_foreign = original_entry.usage()
      match
        host.open_original_relation_file_source_work(
          foreign_operation.val.unwrap(),
          original_entry,
          contracts,
          assets.values,
          fragment,
          assets.ordered,
          requirements,
          "original-relation-source",
          64,
          100000,
        ) {
        Ok(_) => fail("foreign operation consumed original entry")
        Err(refusal) => {
          assert_true(refusal.close())
          assert_true(refusal.close())
        }
      }
      assert_eq(original_entry.usage(), before_foreign)
      match
        host.open_original_relation_file_source_work(
          operation,
          original_entry,
          contracts,
          assets.values,
          fragment,
          assets.ordered,
          requirements,
          "original-relation-source",
          64,
          100000,
        ) {
        Ok(work) => {
          escaped_work.val = Some(work)
          assert_eq(mode, "positive")
          let acquired = work.source_capture_usage()
          assert_eq(acquired.attempts, 1)
          assert_eq(acquired.holdings, 1)
          assert_eq(acquired.live_reservations, 3)
          assert_eq(acquired.reserved_attempts, 0)
          assert_eq(acquired.transferred_bytes, 62L)
          assert_eq(acquired.reserved_transfer_bytes, 8192L - 62L)
          assert_eq(
            acquired.held_bytes + acquired.reserved_retention_bytes,
            source_quote.retained_bytes +
            @execution.execution_capacity_retained_bytes(control),
          )
          assert_eq(
            acquired.reserved_execution_bytes,
            source_quote.execution_bytes +
            @execution.execution_capacity_execution_bytes(control),
          )
          assert_eq(work.usage(), original_entry.usage())
          // Observe wrong-scope refusal while the Work is still usable, not
          // merely after logical close. Keep only scalar accounting snapshots.
          let attempts_before_scope = work.usage().attempts
          let reservations_before_scope = work.usage().live_reservations
          let retention_before_scope = work.usage().reserved_retention_bytes
          let execution_before_scope = work.usage().reserved_execution_bytes
          operation
          .return_business_to_original_read()
          .relation_original_value("active Work return for scope refusal")
          assert_true(
            work.prepare_result_export(export_limits)
            is Err(@client.OriginalRunNotCurrent),
          )
          assert_false(work.close())
          assert_eq(work.usage().attempts, attempts_before_scope)
          assert_eq(work.usage().live_reservations, reservations_before_scope)
          assert_eq(
            work.usage().reserved_retention_bytes,
            retention_before_scope,
          )
          assert_eq(
            work.usage().reserved_execution_bytes,
            execution_before_scope,
          )
          operation
          .enter_business_from_original_read()
          .relation_original_value("same Work business reentry")
          let exported = work
            .prepare_result_export(export_limits)
            .relation_original_value("actual final output export")
          assert_true(relation_original_export_matches(exported))
          exported.cancel()
          assert_eq(
            original_entry.usage().attempts,
            @strategy.graph_task_count(@host.prepared_client_graph(prepared)),
          )
          let before_reuse = original_entry.usage()
          match
            host.open_original_relation_file_source_work(
              operation,
              original_entry,
              contracts,
              assets.values,
              fragment,
              assets.ordered,
              requirements,
              "original-relation-source",
              64,
              100000,
            ) {
            Ok(_) => fail("used entry replayed Source")
            Err(refusal) => {
              assert_true(refusal.close())
              assert_true(refusal.close())
            }
          }
          assert_eq(original_entry.usage(), before_reuse)
          assert_true(work.close())
          assert_true(work.close())
        }
        Err(failure) => {
          escaped_failure.val = Some(failure)
          // Retain the original refusal and attempt its existing cleanup
          // before reporting an unexpected positive-mode outcome. Formatting
          // here could allocate in the very business frame being diagnosed.
          if mode == "positive" {
            ()
          } else if mode == "run-only" ||
            mode == "wrong-connection" ||
            mode == "wrong-resource" {
            assert_true(
              failure.issue() is OriginalOperation(AuthorizationDenied),
            )
          } else if mode == "short-capacity" {
            assert_true(failure.issue() is Configuration)
          } else {
            assert_true(
              mode == "foreign-declaration" || mode == "wrong-selection",
            )
          }
          // The same two cleanup calls remain ordered. A refusal stops with
          // the retained Work family, without formatting or an ACK claim.
          if !failure.close() {
            raise Failure(relation_return_work_label(failure.issue()))
          }
          if !failure.close() {
            raise Failure(relation_return_work_label(failure.issue()))
          }
          if mode != "positive" {
            assert_eq(original_entry.usage().attempts, 0)
            assert_eq(original_entry.usage().transferred_bytes, 0L)
          }
        }
      }
      assert_eq(original_entry.usage().live_reservations, 1)
      assert_eq(original_entry.usage().held_bytes, 0L)
      assert_eq(original_entry.usage().holdings, 0)
      operation
      .return_business_to_original_read()
      .relation_original_value("original business return")
      // Public operations must refuse in Read before allocating business
      // products. Their refusal Results are preowned inert entry fields.
      if escaped_work.val is Some(work) {
        assert_true(
          work.prepare_result_export(export_limits)
          is Err(@client.OriginalRunNotCurrent),
        )
        assert_false(work.close())
      }
      // Even a correct Read scope is not a physical retirement acknowledgement.
      assert_false(original_entry.close_after_original_return())
      Ok(())
    } catch {
      error => Err(@debug.to_string(error))
    }
    body.val = Some(result)
  })
  let mut unexpected_work_diagnostic : String? = None
  if operation.val is Some(operation) {
    operation
    .retry_scope_cleanup()
    .relation_original_value("original routing scope cleanup")
    // A sticky operation error can survive a successful physical leave. Err
    // therefore proves failure, not a pending scope or a cleanup ACK. Stop
    // without formatting in a scope whose return has not been established.
    guard entry is Ok(_) else {
      match body.val {
        // Direct Failure borrows the already retained first message. Unlike
        // fail(primary), it does not build a new location/message String.
        Some(Err(primary)) => raise Failure(primary)
        Some(Ok(_)) | None => ()
      }
      // These selectors only borrow static labels and existing issue fields.
      // Direct Failure still allocates a test-only terminal error and can
      // retain failed-frame memory. It is not allocation-free reporting or a
      // cleanup ACK; unlike builtin fail it adds no formatted message String.
      raise Failure(relation_return_failure_label(entry, escaped_failure.val))
    }
    let body_diagnostic = match body.val {
      Some(Ok(_)) => "body returned normally"
      Some(Err(original)) => original
      None => "body did not return"
    }
    let work_diagnostic = match escaped_failure.val {
      Some(failure) => relation_work_issue(failure.issue())
      None => "no Work refusal"
    }
    let unexpected_work = mode == "positive" && escaped_failure.val is Some(_)
    if prepared_entry.val is Some(original_entry) {
      let before_reservations = original_entry.usage().live_reservations
      let before_retained = original_entry.usage().reserved_retention_bytes
      let before_execution = original_entry.usage().reserved_execution_bytes
      assert_false(original_entry.close_after_original_return())
      assert_eq(original_entry.usage().live_reservations, before_reservations)
      assert_eq(
        original_entry.usage().reserved_retention_bytes,
        before_retained,
      )
      assert_eq(
        original_entry.usage().reserved_execution_bytes,
        before_execution,
      )
      escaped_work.val = None
      escaped_failure.val = None
      if !original_entry.close_after_original_return() {
        fail(
          "entry close=false after original return; " +
          body_diagnostic +
          "; Work=" +
          work_diagnostic +
          "; original Read/routing returns acknowledged",
        )
      }
      assert_true(original_entry.close_after_original_return())
      let closed = original_entry.usage()
      assert_eq(closed.held_bytes, 0L)
      assert_eq(closed.reserved_retention_bytes, 0L)
      assert_eq(closed.reserved_execution_bytes, 0L)
      assert_eq(closed.live_reservations, 0)
      assert_eq(closed.holdings, 0)
      assert_eq(closed.reserved_attempts, 0)
      assert_eq(closed.reserved_transfer_bytes, 0L)
      prepared_entry.val = None
    }
    operation.close_checked().relation_original_value("original routing close")
    if unexpected_work {
      unexpected_work_diagnostic = Some(work_diagnostic)
    }
  }
  operation.val = None
  if foreign_operation.val is Some(foreign) {
    foreign
    .close_checked()
    .relation_original_value("foreign operation metadata close")
  }
  foreign_operation.val = None
  let closed = capture.close()
  assert_true(closed.issue() is None)
  assert_true(adoption.close().issue() is None)
  physical
  .enter_local_host_cleanup(pair, @arena.HostRead)
  .relation_original_value("Crypto cleanup Read")
  crypto.close_checked().relation_original_value("Crypto Library close")
  physical
  .close_crypto_component(component)
  .relation_original_value("Crypto component close")
  physical
  .leave_local_host_phase(pair)
  .relation_original_value("Crypto cleanup leave")
  entry.relation_original_value("original Journal callback")
  match body.val {
    Some(Ok(_)) => ()
    Some(Err(primary)) =>
      fail(
        "original Work assertion: " +
        primary +
        "; Work=" +
        unexpected_work_diagnostic.unwrap_or("no Work refusal"),
      )
    None => fail("original Work body did not return")
  }
  if unexpected_work_diagnostic is Some(original) {
    fail("unexpected positive Work refusal after cleanup: " + original)
  }
}

///|
test "actual original Account Journal StoreOperation captures relation and executes Common suffix" {
  relation_original_verify_quote_vectors()
  let root = @env.get_env_var("ACTQL_TEST_RELATION_ORIGINAL_ROOT").unwrap()
  let runtime_root = @env.get_env_var("ACTQL_TEST_RELATION_RUNTIME_ROOT").unwrap()
  let source = @env.get_env_var("ACTQL_TEST_RELATION_RUNTIME_SOURCE").unwrap()
  let digest = @env.get_env_var("ACTQL_TEST_RELATION_RUNTIME_DIGEST").unwrap()
  let platform = @env.get_env_var("ACTQL_TEST_RELATION_RUNTIME_PLATFORM").unwrap()
  let mib = 1048576L
  // These DATA queries run in test setup before arena/consumer admission.
  // Their own finite query products are test-setup preparation under the
  // externally bounded diagnostic process, never charged retroactively to the
  // future arena: Source query23832+cost160, Read query928, outer query280,
  // Source evaluator-record56+cost160 and provider backing-control Some32
  // =25448 logical bytes. Ordinary test input records remain test setup DATA,
  // not installed-profile evidence.
  // The Read baseline owns ordinary Adoption/Account/compiler/Journal work.
  // Add the full Source planning constructor (including its first mapping)
  // once for the actual Read-side quote at relation_original_run. Work later
  // pays its separate business-side first mapping from the exact entry token.
  let selection = relation_original_selection(root)
  let limits = relation_original_limits()
  let source_preparation = @execution.preparation_representation_cost(
    @row_file.native_relation_file_caller_preparation_inventory(
      selection, limits,
    ).unwrap(),
  ).unwrap()
  let entry_read = @client.native_relation_file_entry_read_capacity(
    selection, limits,
  ).unwrap()
  let entry_outer = @client.native_relation_file_entry_outer_capacity().unwrap()
  let source_evaluator = @execution.preparation_representation_cost(
    @row_file.native_relation_file_caller_preparation_evaluation_inventory(
      selection,
    ),
  ).unwrap()
  // The positive fixture has one unrelated-token/refused-entry/cancel path and
  // one original entry. Sum two complete components without phase reuse. Its
  // earlier Work-capacity planning query is one further actual evaluation:
  // Source evaluator + old fixed408 + source conversion/composition192.
  // Entry out-slot Some and enclosing Unit result each add32 in Read.
  // The fixture export-limit projection adds360 before business entry.
  // Immutable API arguments (Limits+Page+fragment Some) add128 in Read;
  // no argument construction precedes the wrong-scope primitive refusal.
  // The live Work return/reentry adds Read H314/R121/S578 (10616 bytes);
  // its business H86/R23/S149 is in the exact Work control token.
  let read_addition = source_preparation +
    2L * @execution.execution_capacity_execution_bytes(entry_read) +
    source_evaluator +
    408L +
    192L +
    64L +
    360L +
    128L +
    10616L
  // Three new caller out-slot Refs are outer-owned, not Read-owned. The existing
  // test baseline separately owns original operation/runtime/retirement duties.
  // The same live roundtrip adds outer H346/R168/S672 (12256 bytes),
  // excluding generic capture-current stages already owned by that baseline.
  let outer_addition = @execution.execution_capacity_execution_bytes(
      entry_outer,
    ) +
    3L * 24L +
    12256L
  assert_eq(source_preparation, 23075950L)
  assert_eq(@execution.execution_capacity_retained_bytes(entry_read), 29346L)
  assert_eq(read_addition, 23170242L)
  assert_eq(outer_addition, 15170L)
  // The real no-VM domain contract requires R+E, not just E. These test-owned
  // physical partitions preserve the same 768 MiB backing and logical quotes.
  // The same compiled provider observes its control/context geometry; neither
  // observation grants capacity or substitutes for per-object construction.
  let read_payload = 113L * mib + 2L * read_addition
  assert_eq(read_payload, 164829572L)
  let read_necessary = @bootstrap.execution_domain_necessary_bytes(
    160L * mib,
    read_payload,
  )
  let sqlite_necessary = @bootstrap.execution_domain_necessary_bytes(
    56L * mib,
    48L * mib,
  )
  let backing_control = @bootstrap.command_backing_control_necessary_bytes(
    768L * mib,
  ).unwrap()
  if read_necessary <= 0L ||
    read_necessary > 160L * mib ||
    sqlite_necessary <= 0L ||
    sqlite_necessary > 56L * mib ||
    backing_control + (160L + 536L + 56L) * mib > 768L * mib {
    fail(
      "physical partition refused: read=\{read_necessary} sqlite=\{sqlite_necessary} backing_control=\{backing_control}",
    )
  }
  assert_true(read_payload <= 160L * mib)
  assert_true(read_necessary > 0L && read_necessary <= 160L * mib)
  assert_true(sqlite_necessary > 0L && sqlite_necessary <= 56L * mib)
  assert_true(backing_control + (160L + 536L + 56L) * mib <= 768L * mib)
  let fd = relation_original_open(@utf8.encode(root + "/backing\u{0}"), 2)
  assert_true(fd >= 0)
  // Explicit test envelope only: no CLI defaults or Common maxima changed.
  let physical = @arena.prepare_installed_arena_host(
    source,
    Bytes::make(32, 17),
    1L,
    768L * mib,
    {
      planning_work: 200000,
      attempts: 128,
      holdings: 64,
      transfer_bytes: 32L * mib,
      retained_bytes: 0L,
      execution_bytes: 768L * mib,
    },
    65536L + outer_addition,
  ).relation_original_value("test arena preparation")
  physical.acquire_fd(fd).relation_original_value("test backing acquisition")
  let backing = physical
    .borrow_backing()
    .relation_original_value("backing borrow")
  physical
  .enter_backing_borrow_scope(backing)
  .relation_original_value("backing entry")
  let domain = fn(bytes, limits) raise {
    match
      physical
      .prepare_domain(backing, fd, bytes, limits)
      .relation_original_value("test domain preparation") {
      @arena.PreparedDomain(value) => {
        physical
        .transfer_domain(value)
        .relation_original_value("test domain transfer")
        value
      }
      @arena.PendingDomain(_, issue) =>
        fail("test domain pending: " + @debug.to_string(issue))
    }
  }
  let read_domain = domain(160L * mib, {
    planning_work: 512,
    attempts: 64,
    holdings: 32,
    transfer_bytes: 8L * mib,
    retained_bytes: 8L * mib + read_addition,
    execution_bytes: 105L * mib + read_addition,
  })
  let sqlite_domain = domain(56L * mib, {
    planning_work: 256,
    attempts: 32,
    holdings: 16,
    transfer_bytes: 8L * mib,
    retained_bytes: 0L,
    execution_bytes: 48L * mib,
  })
  physical
  .leave_backing_borrow_scope(backing)
  .relation_original_value("backing leave")
  physical
  .return_backing_borrow(backing)
  .relation_original_value("backing return")
  physical
  .prepare_domain_read(read_domain)
  .relation_original_value("prepare Read context")
  physical
  .prepare_domain_read(sqlite_domain)
  .relation_original_value("prepare SQLite context")
  let read = match
    physical
    .prepare_domain_original_read(read_domain, {
      bootstrap_retained: mib,
      bootstrap_execution: mib,
      workspace_execution: 8L * mib,
      read_retained: 7L * mib + read_addition,
      read_execution: 96L * mib + read_addition,
    })
    .relation_original_value("prepare original Read") {
    @arena.ReadyOriginalRead(value) => value
    @arena.PendingOriginalRead(_, _) => fail("original Read pending")
  }
  let business_domain : Ref[@arena.InstalledArenaDomain?] = Ref(None)
  let business_execution : Ref[@arena.InstalledArenaRetainedExecution?] = Ref(
    None,
  )
  let runtime = @client.open_native_local_packaged_runtime_in_original_read(
    Some((physical, read)),
    runtime_root,
    source,
    platform,
    digest,
    128,
  ).relation_original_value("actual Runtime member admission")
  let (sqlite_path, crypto_path) = runtime
    .library_paths()
    .relation_original_value("observed component paths")
  let sqlite = match
    physical
    .prepare_sqlite_library(sqlite_domain, sqlite_path, 32L * mib, 128)
    .relation_original_value("original SQLite component") {
    @arena.ReadySqlite(value) => value
    @arena.PendingSqlite(_, issue) =>
      match issue {
        @arena.Domain(issue) =>
          fail("SQLite component pending Domain: " + @debug.to_string(issue))
        @arena.Library(issue) =>
          fail(
            "SQLite component pending Library: " +
            relation_original_sqlite_issue(issue),
          )
      }
  }
  let pair = physical
    .bind_local_host_resources(read, sqlite)
    .relation_original_value("same original pair")
  let consumer = physical
    .prepare_local_host_read_consumer(
      pair,
      mib + read_addition,
      96L * mib + read_addition,
    )
    .relation_original_value("same original consumer")
  let component = physical
    .prepare_local_host_read_crypto_control(pair, read)
    .relation_original_value("outer Crypto control")
  runtime
  .bind_original_host_resources(pair)
  .relation_original_value("Runtime original pair")
  relation_original_run(
    physical, pair, read, runtime, fd, business_domain, business_execution, root,
    crypto_path,
  )
  runtime.close().relation_original_value("original Runtime close")
  physical
  .close_domain_retained_execution(business_execution.val.unwrap())
  .relation_original_value("physical business retirement")
  physical
  .close_crypto_component(component)
  .relation_original_value("physical Crypto control retirement")
  physical
  .close_local_host_resources(pair)
  .relation_original_value("physical Read SQLite pair retirement")
  physical
  .close_domain_after_owner_ack(business_domain.val.unwrap())
  .relation_original_value("business domain close")
  physical
  .close_domain_after_owner_ack(read_domain)
  .relation_original_value("Read domain close")
  physical
  .close_domain_after_owner_ack(sqlite_domain)
  .relation_original_value("SQLite domain close")
  physical.try_close().relation_original_value("physical arena close")
  assert_eq(relation_original_close(fd), 0)
  ignore(consumer)
}

///|
let relation_original_query_contract : String = "{\"version\":\"actql-query-acquisition-contract/0.1\",\"scope\":\"exclusive_finite_relation_scan_filter_select\",\"dependencies\":{\"canonical_value_contract\":{\"path\":\"spec/contracts/actql-protocol-schemas.json\",\"pointer\":\"/schemas/canonical_value_contract\",\"cid\":\"sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1\"},\"consumer_capacity\":{\"path\":\"spec/contracts/actql-consumer-capacity.json\",\"pointer\":\"\",\"cid\":\"sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f\"}},\"schemas\":{\"requirement\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"version\",\"owner\",\"source_ref\",\"source_contract_cid\",\"input_contract_cid\",\"output_contract_cid\",\"request\",\"parameter_values_cid\",\"filter\",\"select\",\"source_validation\",\"source_order_cid\",\"logical_guards\"],\"properties\":{\"version\":{\"const\":\"actql-query-acquisition/0.1\"},\"owner\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"program_source_cid\",\"stage\",\"input\"],\"properties\":{\"program_source_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"stage\":{\"type\":\"string\",\"minLength\":1},\"input\":{\"type\":\"string\",\"minLength\":1},\"run_definition_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"source_ref\":{\"type\":\"string\",\"minLength\":1},\"source_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"input_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"output_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"request\":{\"type\":\"object\"},\"parameter_values_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"filter\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"occurrence\",\"expression_cid\"],\"properties\":{\"occurrence\":{\"type\":\"string\",\"pattern\":\"^/steps/(0|[1-9][0-9]*)/(filter|select)$\"},\"expression_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"select\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"occurrence\",\"fields\"],\"properties\":{\"occurrence\":{\"type\":\"string\",\"pattern\":\"^/steps/(0|[1-9][0-9]*)/(filter|select)$\"},\"fields\":{\"type\":\"array\",\"minItems\":1,\"items\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"input\",\"output\"],\"properties\":{\"input\":{\"type\":\"string\",\"minLength\":1},\"output\":{\"type\":\"string\",\"minLength\":1}}}}}},\"source_validation\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope\",\"fields\"],\"properties\":{\"scope\":{\"const\":\"selected_scan\"},\"fields\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"minLength\":1},\"uniqueItems\":true}}},\"source_order_cid\":{\"anyOf\":[{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},{\"type\":\"null\"}]},\"logical_guards\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"max_rows\",\"max_value_bytes\"],\"properties\":{\"max_rows\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991},\"max_value_bytes\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}}},\"$schema\":\"https://json-schema.org/draft/2020-12/schema\"},\"completed_observation\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"version\",\"requirement_cid\",\"owner\",\"source_ref\",\"source_contract_cid\",\"parameter_values_cid\",\"resolved_request_cid\",\"snapshot\",\"actual_access\",\"coverage\",\"output\",\"retention\"],\"properties\":{\"version\":{\"const\":\"actql-query-observation/0.1\"},\"requirement_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"owner\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"program_source_cid\",\"stage\",\"input\"],\"properties\":{\"program_source_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"stage\":{\"type\":\"string\",\"minLength\":1},\"input\":{\"type\":\"string\",\"minLength\":1},\"run_definition_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"source_ref\":{\"type\":\"string\",\"minLength\":1},\"source_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"parameter_values_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"resolved_request_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"snapshot\":{\"anyOf\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"token_cid\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"token_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},{\"type\":\"null\"}]},\"actual_access\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope_cid\",\"provider_scope_cid\",\"received_rows\",\"received_fields\",\"received_bytes\"],\"properties\":{\"scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"provider_scope_cid\":{\"anyOf\":[{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},{\"type\":\"null\"}]},\"received_rows\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991},\"received_fields\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"minLength\":1},\"uniqueItems\":true},\"received_bytes\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}},\"coverage\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope_cid\",\"complete\",\"source_validation_evidence_cid\",\"filter_evidence_cid\",\"select_evidence_cid\"],\"properties\":{\"scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"complete\":{\"const\":true},\"source_validation_evidence_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"filter_evidence_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"select_evidence_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"output\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"rows_cid\",\"row_count\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"rows_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"row_count\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}},\"retention\":{\"const\":\"process\"}},\"$schema\":\"https://json-schema.org/draft/2020-12/schema\"}},\"semantics\":{\"owner\":\"program_source_cid_is_authority_bearing_program_definition_cid_not_program_semantics_or_source_text_hash\",\"query_time_owner\":\"declared_query_time_dependency_requires_original_admitted_run_definition_cid_in_requirement_and_completed_observation_owner_with_same_nominal_context_and_saved_run_no_resample_no_grant\",\"derivation\":\"checked_exclusive_scan_filter_select_without_backend_cost_or_placement\",\"capture\":\"completed_select_output_before_any_consumer\",\"identity\":\"sha256_of_canonical_json_utf8_entire_body_no_self_cid\",\"request_values\":\"bound_wire_values_no_reinterpretation_of_business_param_or_literal\",\"parameter_identity\":\"existing_typed_parameter_values_projection_of_used_request_and_query_names\",\"source_validation\":\"all_known_fields_of_selected_scan_before_filter_including_rows_excluded_by_filter\",\"demand\":\"existing_checked_expression_demand_without_eager_undemanded_evaluation\",\"native\":\"preserve_mandatory_admission_and_demanded_failures_before_projection\",\"logical_guards\":\"max_rows_on_capture_output_max_value_bytes_on_admitted_records_and_demanded_roots\",\"physical_budget\":\"actual_received_bytes_rows_and_retention_independent_of_logical_output\",\"failure\":\"atomic_no_success_capture_or_consumer_on_failure_or_cancellation\",\"evidence\":\"verify_actual_execution_evidence_not_candidate_coverage_proposals_or_self_cid_only\",\"snapshot\":\"source_specific_no_universal_snapshot_token_or_isolation_requirement\",\"retention\":\"same_process_immutable_completed_observation_not_durable_run_or_recovery\",\"invocation\":\"existing_invocation_rules_retain_actual_observation_identity_not_result_identity_only\"}}"

///|
let relation_original_evidence_contract : String = "{\"version\":\"actql-query-process-evidence-contract/0.1\",\"dependencies\":{\"query_acquisition\":{\"path\":\"spec/contracts/actql-query-acquisition.json\",\"pointer\":\"\",\"cid\":\"sha256:5a95e60847276d02229eba9550dd9808a8a8c2764decd4dad667954f020db7cc\"}},\"schemas\":{\"record\":{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"version\",\"issuer\",\"attempt\",\"requirement_cid\",\"role\",\"snapshot\",\"scan_scope_cid\",\"actual_access\",\"output\"],\"properties\":{\"version\":{\"const\":\"actql-query-process-evidence/0.1\"},\"issuer\":{\"type\":\"string\",\"minLength\":1},\"attempt\":{\"type\":\"string\",\"minLength\":1},\"requirement_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"role\":{\"enum\":[\"source_validation\",\"filter\",\"select\"]},\"snapshot\":{\"anyOf\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"token_cid\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"token_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},{\"type\":\"null\"}]},\"scan_scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"actual_access\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope_cid\",\"provider_scope_cid\",\"received_rows\",\"received_fields\",\"received_bytes\"],\"properties\":{\"scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"provider_scope_cid\":{\"anyOf\":[{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},{\"type\":\"null\"}]},\"received_rows\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991},\"received_fields\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"minLength\":1},\"uniqueItems\":true},\"received_bytes\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}},\"output\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"rows_cid\",\"row_count\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"rows_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"row_count\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}}}}},\"semantics\":{\"preimage\":\"entire_record_canonical_json_utf8_sha256_no_self_cid\",\"authority\":\"authorized_host_private_issuer_and_live_opaque_success_handle_not_wire_or_cid_alone\",\"issuance\":\"after_complete_scan_validation_filter_select_limits_and_immutable_output_retention\",\"attempt\":\"host_allocated_unique_within_unique_process_issuer_never_reused_or_caller_selected\",\"binding\":\"exact_requirement_attempt_snapshot_scan_scope_actual_access_and_retained_output_for_all_three_roles\",\"native\":\"authorized_source_execution_covers_full_selected_scan_not_only_host_received_rows_or_columns\",\"source_order\":\"null_only_in_this_profile_relative_order_is_not_total_order_evidence\",\"lifetime\":\"same_process_no_deserialization_rehydration_or_durable_capture\",\"host_adapter\":\"host_authorized_execution_with_owned_consistent_read_view_full_scan_validation_and_query_not_driver_location_or_sql_success\",\"read_view\":\"private_task_session_transaction_binding_not_snapshot_token_no_cross_attempt_or_read_view_substitution\",\"access_accounting\":\"engine_internal_scan_host_row_receipt_and_retention_are_distinct_auxiliary_row_receipts_are_not_hidden_or_double_counted\",\"receipt_scope\":\"one_logical_received_sequence_only_independent_validation_and_query_receipts_require_an_additional_admitted_contract\",\"scan_failure\":\"invalid_excluded_rows_still_fail_no_global_diagnostic_order_or_total_order_from_validation_traversal\"}}"
