///|
// Explicit finite selected-provider component DATA. None of these declarations
// selects the normal CLI profile, installs a Source, or grants an Account.
#borrow(path)
extern "C" fn capture_fixture_open(path : Bytes, flags : Int) -> Int = "open"

///|
extern "C" fn capture_fixture_close(fd : Int) -> Int = "close"

///|
fn capture_fixture_declaration() -> @rows.RowDeclaration {
  @rows.generate_row_declaration(
    "native-file-fixture",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "record",
        fields: [
          { name: "id", value_type: "string", nullable: false, },
          { name: "value", value_type: "number", nullable: false, },
        ],
      },
    ],
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_views: 1,
      max_fields: 2,
    },
  ).unwrap()
}

///|
// Environment sections are ordered by each complete canonical member CID.
// This creates checking inputs, never an expected capture or physical result.
fn capture_fixture_members(bodies : Array[String]) -> Json raise {
  let ordered = bodies.map(wire => {
    let body = @identity.from_json(@json.parse(wire), 100000, 100, 1000000)
    (@identity.cid_value(body, 1000000, 100000, 100), @json.parse(wire))
  })
  ordered.sort_by((left, right) => left.0.compare(right.0))
  Json::array(ordered.map(entry => entry.1))
}

///|
fn capture_fixture_environment(
  declaration : @rows.RowDeclaration,
) -> (String, String) raise {
  let (schemas, capabilities) = @rows.row_declaration_evidence_members(
    declaration,
  )
  let body : Json = {
    "version": "actql-check-environment/0.1",
    "connector_manifest": {
      "version": "actql-connectors/0.1",
      "connectors": [@json.parse(declaration.manifest_entry)],
    },
    "connector_catalogs": [@json.parse(declaration.catalog)],
    "contract_registry": capture_fixture_members(declaration.contracts),
    "source_views": capture_fixture_members(declaration.view_bodies),
    "schema_snapshots": capture_fixture_members(schemas),
    "connector_capabilities": capture_fixture_members(capabilities),
    "command_contracts": [],
    "mapping_contracts": [],
    "model_task_contracts": [],
    "host_policy_profile": {
      "capacity": {
        "version": "actql-capacity-host-policy/0.1",
        "max_aggregate_array_items": 10000,
        "max_artifact_bytes": 10000,
        "max_artifact_rows": 10000,
        "max_effect_items": 10000,
        "max_graph_input_edges": 10000,
        "max_graph_input_nodes": 10000,
        "max_graph_output_rows": 10000,
        "max_graph_paths": 10000,
        "max_infer_items": 10000,
        "max_model_input_tokens_per_item": 10000,
        "max_model_request_bytes_per_item": 10000,
        "max_model_total_duration_ms": 10000,
        "max_nested_value_bytes": 10000,
        "max_nested_value_depth": 10000,
        "max_relation_output_rows": 10000,
        "max_temporal_matches_per_key": 10000,
        "max_temporal_output_rows": 10000,
      },
    },
  }
  let canonical = @identity.from_json(body, 100000, 100, 1000000)
  let cid = @identity.cid_value(canonical, 1000000, 100000, 100)
  let enveloped = @identity.object_with_string_field(
    canonical, "evidence_bundle_cid", cid,
  ).unwrap()
  (@identity.stringify_value(enveloped, 1000000, 100000, 100), cid)
}

///|
fn capture_fixture_logical() -> (
  @rows.RowDeclaration,
  @planning.QueryRequirement,
  @rows.RowAcquisition,
) raise {
  let declaration = capture_fixture_declaration()
  let (wire, cid) = capture_fixture_environment(declaration)
  let environment = @publication_host.admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"native-file-capture","stages":[{"id":"acquire","inputs":{"remote":{"connector":"native-file-fixture","resource":"records"}},"steps":[{"filter":"value > 1"},{"select":["id","value"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","value"]}}},{"id":"compute","inputs":{"input":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"filter":"value > 0"},{"select":["id","value"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","value"]}}}],"results":{"rows":{"from":{"stage":"compute","result":"rows"}}}}
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let contracts = @local.prepare_installed_sequence_contracts(
    capture_fixture_registry,
    capture_fixture_values,
    Some(capture_fixture_fragment),
    None,
  ).unwrap()
  let requirement = @local.prepare_local_query_requirement(
    prepared,
    0,
    0,
    contracts,
    capture_fixture_values,
    Some(capture_fixture_fragment),
    None,
  ).unwrap()
  let acquisition = @rows.prepare_row_acquisition(
    declaration, requirement, capture_fixture_query_contract, capture_fixture_evidence_contract,
  ).unwrap()
  (declaration, requirement, acquisition)
}

///|
fn capture_fixture_limits() -> NativeRelationFileLimits {
  {
    // The current Common mapping admission also traverses the original
    // declaration under these bounds. The physical input itself is 62 bytes.
    page: { max_bytes: 8192, max_nodes: 512, max_depth: 8, max_rows: 2, },
    max_work: 1000000,
    chunk_bytes: 7,
    diagnostic_ceiling: 128,
  }
}

///|
let capture_fixture_retained_bytes : Int64 = 96L * 1024L * 1024L

///|
let capture_fixture_execution_bytes : Int64 = 128L * 1024L * 1024L

///|
// Test-only quote DATA. These totals do not reserve a Ledger, create a physical
// domain, select installed limits or establish successful source execution.
priv struct CaptureFixtureQuote {
  metadata : Int64
  acquisition_retained : Int64
  acquisition_execution : Int64
  provider_retained : Int64
  provider_execution : Int64
  page_scratch : Int64
  total_retained : Int64
  total_execution : Int64
}

///|
fn capture_fixture_quote(
  declaration : @rows.RowDeclaration,
  acquisition : @rows.RowAcquisition,
  selection : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
) -> CaptureFixtureQuote raise {
  let metadata = file_capture_metadata_capacity(selection, limits).unwrap_or_else(() => {
      fail("fixture metadata quote unavailable")
    },
  )
  let contract = @rows.relation_document_projection_contract(
    declaration,
    selection.resource,
    selection.primary_identity,
    limits.page,
  ).unwrap_or_else(() => {
    fail("fixture declaration projection quote unavailable")
  })
  let provider = file_capture_provider_capacity(selection, limits, contract).unwrap_or_else(() => {
      fail("fixture provider quote unavailable")
    },
  )
  let combined = @rows.row_acquisition_provider_capacity(
    acquisition,
    Some(provider),
  ).unwrap_or_else(() => {
    fail("fixture RowAcquisition/provider quote unavailable")
  })
  let page_scratch = limits.page.max_bytes.to_int64()
  let total_retained = @execution.checked_preparation_add_product(
    metadata,
    @execution.execution_capacity_retained_bytes(combined),
    1L,
  ).unwrap_or_else(() => fail("fixture retained quote overflow"))
  let execution_without_scratch = @execution.checked_preparation_add_product(
    metadata,
    @execution.execution_capacity_execution_bytes(combined),
    1L,
  ).unwrap_or_else(() => fail("fixture execution quote overflow"))
  let total_execution = @execution.checked_preparation_add_product(
    execution_without_scratch, page_scratch, 1L,
  ).unwrap_or_else(() => fail("fixture page scratch quote overflow"))
  {
    metadata,
    acquisition_retained: @rows.row_acquisition_retained_capacity(acquisition),
    acquisition_execution: @rows.row_acquisition_execution_capacity(acquisition),
    provider_retained: @execution.execution_capacity_retained_bytes(provider),
    provider_execution: @execution.execution_capacity_execution_bytes(provider),
    page_scratch,
    total_retained,
    total_execution,
  }
}

///|
fn capture_fixture_report_quote(
  label : String,
  quote : CaptureFixtureQuote,
) -> Unit {
  // Fixed fields and Int64 decimal values keep the diagnostic bounded. The
  // label is one of the fixture's authored names, never unbounded file content.
  println(
    "Native file fixture quote \{label}: metadata=\{quote.metadata}, acquisition_R=\{quote.acquisition_retained}, acquisition_E=\{quote.acquisition_execution}, provider_R=\{quote.provider_retained}, provider_E=\{quote.provider_execution}, page_scratch=\{quote.page_scratch}, total_R=\{quote.total_retained}, total_E=\{quote.total_execution}, authored_R=\{capture_fixture_retained_bytes}, authored_E=\{capture_fixture_execution_bytes}; logical bytes only, no physical acquisition",
  )
}

///|
fn capture_fixture_require_geometry(
  declaration : @rows.RowDeclaration,
  acquisition : @rows.RowAcquisition,
  selection : NativeRelationFileSelection,
) -> Unit raise {
  let limits = capture_fixture_limits()
  let mut fits = true
  // All three serial attempts reuse the same original execution. Their peaks
  // are tested independently, not added as if they were concurrent owners.
  for
    name in ["row-source-input", "row-source-malformed", "row-source-oversized"] {
    let quote = capture_fixture_quote(
      declaration,
      acquisition,
      { ..selection, name, },
      limits,
    )
    capture_fixture_report_quote(name, quote)
    if quote.total_retained > capture_fixture_retained_bytes ||
      quote.total_execution > capture_fixture_execution_bytes {
      fits = false
    }
  }
  assert_true(
    fits,
    msg="authored Native fixture allowances do not cover the complete quote; no physical owner was acquired",
  )
}

///|
fn capture_fixture_prepared(
  result : Result[NativeRelationFileCapture, NativeRelationFileFailure],
  stage : String,
) -> NativeRelationFileCapture raise {
  match result {
    Ok(owner) => owner
    Err(failure) => {
      let issue = failure.issue()
      let mut acknowledged = false
      for _ in 0..<10000 {
        match failure.retry_cleanup() {
          Ok(true) => {
            acknowledged = true
            break
          }
          Ok(false) | Err(Row(@rows.InvalidState)) => ()
          Err(_) => break
        }
      }
      let detail = match issue {
        Resource(@resources.RetentionLimit) =>
          "metadata retention allowance refused"
        Resource(@resources.ExecutionLimit) =>
          "metadata execution allowance refused"
        Row(@rows.Physical(@resources.RetentionLimit)) =>
          "RowRun/provider retention allowance refused"
        Row(@rows.Physical(@resources.ExecutionLimit)) =>
          "RowRun/provider execution allowance refused"
        Capacity => "constructor capacity unavailable"
        Mapping(_) => "original declaration mapping refused"
        Execution(_) => "original execution unavailable"
        Resource(_) => "metadata reservation refused"
        Row(_) => "original Row acquisition refused"
        _ => "native file preparation refused"
      }
      // This reports only the original component's explicit cleanup result.
      // The enclosing physical execution/domain has not been retired here.
      fail(
        stage +
        ": " +
        detail +
        "; component_cleanup_acknowledged=\{acknowledged}; physical retirement not established",
      )
    }
  }
}

///|
fn capture_fixture_work(
  arena : @arena.InstalledArenaHost,
  execution : @arena.InstalledArenaRetainedExecution,
  declaration : @rows.RowDeclaration,
  foreign : @rows.RowDeclaration,
  requirement : @planning.QueryRequirement,
  acquisition : @rows.RowAcquisition,
  selection : NativeRelationFileSelection,
) -> Unit raise {
  arena.enter_domain_retained_execution(execution).unwrap()
  // Cleanup metadata never becomes an entry point into a currently entered Read.
  assert_true(
    arena.observe_domain_retained_execution_cleanup(execution) is Err(_),
  )
  let ledger = arena.borrow_domain_retained_execution_ledger(execution).unwrap()
  let limits = capture_fixture_limits()
  let before = @resources.ledger_usage(ledger)
  assert_eq(before.transferred_bytes, 0L)
  assert_eq(before.reserved_attempts, 0)
  assert_eq(before.reserved_transfer_bytes, 0L)
  assert_eq(before.reserved_retention_bytes, 0L)
  assert_eq(before.reserved_execution_bytes, 0L)
  // Equal logical declaration bytes never replace the admitted original.
  assert_eq(foreign.catalog_cid, declaration.catalog_cid)
  let refused = prepare_native_relation_file_capture(
    arena, execution, foreign, requirement, acquisition, "native-file-foreign", selection,
    limits,
  )
  guard refused is Err(failure) else {
    fail("foreign declaration unexpectedly acquired a native reader")
  }
  assert_true(failure.issue() is Row(@rows.ForeignDeclaration))
  assert_true(failure.retry_cleanup().unwrap())
  assert_eq(@resources.ledger_usage(ledger), before)
  let owner = capture_fixture_prepared(
    prepare_native_relation_file_capture(
      arena, execution, declaration, requirement, acquisition, "native-file-original",
      selection, limits,
    ),
    "positive file prepare",
  )
  assert_true(owner.capture() is Err(Unavailable))
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
  let mut completed = false
  let mut charged_before_admission = false
  for _ in 0..<10000 {
    if owner.advance(32).unwrap() {
      completed = true
      break
    }
    if owner.phase is Received {
      assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 62L)
      charged_before_admission = true
    }
  }
  assert_true(completed)
  assert_true(charged_before_admission)
  // This is the exact original document, including its envelope, charged once.
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 62L)
  let capture = owner.capture().unwrap()
  assert_true(physical_equal(owner.capture().unwrap(), capture))
  let captured_usage = @resources.ledger_usage(ledger)
  arena.leave_domain_retained_execution(execution).unwrap()
  // A completed capture is not borrowable outside its original entered scope.
  // Do not advance here: that would intentionally record a sticky failure.
  assert_true(owner.capture() is Err(Unavailable))
  arena.enter_domain_retained_execution(execution).unwrap()
  assert_true(
    physical_equal(
      ledger,
      arena.borrow_domain_retained_execution_ledger(execution).unwrap(),
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), captured_usage)
  assert_true(owner.advance(32).unwrap())
  assert_true(physical_equal(owner.capture().unwrap(), capture))
  let source = @rows.row_capture_source(capture).unwrap()
  let original = @rows.row_capture_original_read(capture).unwrap()
  assert_true(@query.captured_source_available(source))
  assert_eq(@query.captured_source_row_count(source), Some(1))
  assert_true(@execution.supplied_relation_read_available(original))
  assert_eq(@execution.supplied_relation_read_row_count(original), 2)
  assert_true(
    @execution.supplied_relation_read_cell(original, 0, 0)
    is Some(@admitted.Text("first")),
  )
  assert_true(
    @execution.supplied_relation_read_cell(original, 1, 0)
    is Some(@admitted.Text("second")),
  )
  assert_true(
    @execution.supplied_relation_read_cell(original, 0, 1)
    is Some(@admitted.Number(1)),
  )
  assert_true(
    @execution.supplied_relation_read_cell(original, 1, 1)
    is Some(@admitted.Number(2)),
  )
  let mut closed = false
  for _ in 0..<10000 {
    match owner.close() {
      Ok(true) => {
        closed = true
        break
      }
      Ok(false) | Err(Row(@rows.InvalidState)) => ()
      Err(_) => fail("native relation file cleanup failed")
    }
  }
  assert_true(closed)
  assert_true(owner.close().unwrap())
  assert_true(owner.capture() is Err(Unavailable))
  assert_true(@rows.row_capture_source(capture) is Err(_))
  assert_true(@rows.row_capture_original_read(capture) is None)
  assert_false(@query.captured_source_available(source))
  assert_false(@execution.supplied_relation_read_available(original))
  let retired = @resources.ledger_usage(ledger)
  assert_eq(retired.transferred_bytes, 62L)
  assert_eq(retired.held_bytes, 0L)
  assert_eq(retired.reserved_transfer_bytes, 0L)
  assert_eq(retired.reserved_retention_bytes, 0L)
  assert_eq(retired.reserved_execution_bytes, 0L)
  arena.leave_domain_retained_execution(execution).unwrap()
  // No owner, capture, original read or child-allocated usage snapshot escapes.
}

///|
fn capture_fixture_partial_work(
  arena : @arena.InstalledArenaHost,
  execution : @arena.InstalledArenaRetainedExecution,
  declaration : @rows.RowDeclaration,
  requirement : @planning.QueryRequirement,
  acquisition : @rows.RowAcquisition,
  selection : NativeRelationFileSelection,
) -> Unit raise {
  arena.enter_domain_retained_execution(execution).unwrap()
  let ledger = arena.borrow_domain_retained_execution_ledger(execution).unwrap()
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 72L)
  assert_eq(@resources.ledger_usage(ledger).attempts, 3)
  let owner = capture_fixture_prepared(
    prepare_native_relation_file_capture(
      arena,
      execution,
      declaration,
      requirement,
      acquisition,
      "native-file-partial",
      selection,
      capture_fixture_limits(),
    ),
    "partial file prepare",
  )
  // Opening receives no body. One actual Reader chunk spends seven bytes
  // immediately, before EOF or parsing can produce a completed Source.
  assert_false(owner.advance(32).unwrap())
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 72L)
  assert_eq(@resources.ledger_usage(ledger).attempts, 4)
  assert_false(owner.advance(32).unwrap())
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 79L)
  assert_true(owner.capture() is Err(Unavailable))
  let mut closed = false
  for _ in 0..<10000 {
    match owner.close() {
      Ok(true) => {
        closed = true
        break
      }
      Ok(false) | Err(Row(@rows.InvalidState)) => ()
      Err(_) => fail("partial native file cleanup failed")
    }
  }
  assert_true(closed)
  assert_true(owner.close().unwrap())
  assert_true(owner.capture() is Err(Unavailable))
  let retired = @resources.ledger_usage(ledger)
  assert_eq(retired.transferred_bytes, 79L)
  assert_eq(retired.attempts, 4)
  assert_eq(retired.held_bytes, 0L)
  assert_eq(retired.reserved_transfer_bytes, 0L)
  assert_eq(retired.reserved_retention_bytes, 0L)
  assert_eq(retired.reserved_execution_bytes, 0L)
  arena.leave_domain_retained_execution(execution).unwrap()
}

///|
fn capture_fixture_malformed_work(
  arena : @arena.InstalledArenaHost,
  execution : @arena.InstalledArenaRetainedExecution,
  declaration : @rows.RowDeclaration,
  requirement : @planning.QueryRequirement,
  acquisition : @rows.RowAcquisition,
  selection : NativeRelationFileSelection,
) -> Unit raise {
  // Serial reentry keeps the successful acquisition's original cumulative
  // Ledger. No second physical execution, allowance or source is fabricated.
  arena.enter_domain_retained_execution(execution).unwrap()
  let ledger = arena.borrow_domain_retained_execution_ledger(execution).unwrap()
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 62L)
  let owner = capture_fixture_prepared(
    prepare_native_relation_file_capture(
      arena,
      execution,
      declaration,
      requirement,
      acquisition,
      "native-file-malformed",
      selection,
      capture_fixture_limits(),
    ),
    "malformed file prepare",
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 62L)
  let mut first : NativeRelationFileFailure? = None
  for _ in 0..<10000 {
    match owner.advance(32) {
      Ok(false) => ()
      Ok(true) => fail("malformed native file unexpectedly completed capture")
      Err(failure) => {
        first = Some(failure)
        break
      }
    }
  }
  let failure = first.unwrap()
  assert_true(failure.issue() is Document(_))
  // The 10 received malformed bytes are charged before parsing rejects them.
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 72L)
  assert_true(owner.capture() is Err(Unavailable))
  let failed = @resources.ledger_usage(ledger)
  guard owner.advance(32) is Err(repeated) else {
    fail("failed native file resumed normal work")
  }
  assert_true(physical_equal(repeated, failure))
  assert_eq(@resources.ledger_usage(ledger), failed)
  let mut closed = false
  for _ in 0..<10000 {
    match failure.retry_cleanup() {
      Ok(true) => {
        closed = true
        break
      }
      Ok(false) | Err(Row(@rows.InvalidState)) => ()
      Err(_) => fail("malformed native file cleanup failed")
    }
  }
  assert_true(closed)
  assert_true(failure.retry_cleanup().unwrap())
  assert_true(owner.capture() is Err(Unavailable))
  let retired = @resources.ledger_usage(ledger)
  assert_eq(retired.transferred_bytes, 72L)
  assert_eq(retired.held_bytes, 0L)
  assert_eq(retired.reserved_transfer_bytes, 0L)
  assert_eq(retired.reserved_retention_bytes, 0L)
  assert_eq(retired.reserved_execution_bytes, 0L)
  arena.leave_domain_retained_execution(execution).unwrap()
  // Failure/owner aliases also die before the outer physical context closes.
}

///|
fn capture_fixture_oversized_work(
  arena : @arena.InstalledArenaHost,
  execution : @arena.InstalledArenaRetainedExecution,
  declaration : @rows.RowDeclaration,
  requirement : @planning.QueryRequirement,
  acquisition : @rows.RowAcquisition,
  selection : NativeRelationFileSelection,
) -> Unit raise {
  arena.enter_domain_retained_execution(execution).unwrap()
  let ledger = arena.borrow_domain_retained_execution_ledger(execution).unwrap()
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 72L)
  let owner = capture_fixture_prepared(
    prepare_native_relation_file_capture(
      arena,
      execution,
      declaration,
      requirement,
      acquisition,
      "native-file-oversized",
      selection,
      capture_fixture_limits(),
    ),
    "oversized file prepare",
  )
  // Observation sees the original 8193-byte extent before any Reader body.
  guard owner.advance(32) is Err(failure) else {
    fail("oversized native file unexpectedly began reading")
  }
  assert_true(failure.issue() is FileLimit)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 72L)
  // The real Root observation is an attempt even though no body was read.
  assert_eq(@resources.ledger_usage(ledger).attempts, 3)
  assert_true(owner.capture() is Err(Unavailable))
  guard owner.advance(32) is Err(repeated) else {
    fail("oversized native file resumed normal work")
  }
  assert_true(physical_equal(repeated, failure))
  let mut closed = false
  for _ in 0..<10000 {
    match failure.retry_cleanup() {
      Ok(true) => {
        closed = true
        break
      }
      Ok(false) | Err(Row(@rows.InvalidState)) => ()
      Err(_) => fail("oversized native file cleanup failed")
    }
  }
  assert_true(closed)
  assert_true(failure.retry_cleanup().unwrap())
  let retired = @resources.ledger_usage(ledger)
  assert_eq(retired.transferred_bytes, 72L)
  assert_eq(retired.held_bytes, 0L)
  assert_eq(retired.reserved_transfer_bytes, 0L)
  assert_eq(retired.reserved_retention_bytes, 0L)
  assert_eq(retired.reserved_execution_bytes, 0L)
  arena.leave_domain_retained_execution(execution).unwrap()
}

///|
fn capture_fixture_retirement_issue(
  issue : @arena.InstalledArenaRetainedExecutionIssue,
) -> String {
  match issue {
    @arena.Domain(issue) => "Domain(" + @debug.to_string(issue) + ")"
    @arena.Child(issue) => "Child(" + @debug.to_string(issue) + ")"
    @arena.Initialization(_) => "Initialization"
  }
}

///|
// This original Read observation allocates only in outer test control.
// Occupancy and scope are diagnostics, never retirement ACKs.
fn capture_fixture_report_inventory(
  arena : @arena.InstalledArenaHost,
  execution : @arena.InstalledArenaRetainedExecution,
  label : String,
) -> Unit {
  match arena.observe_domain_retained_execution_cleanup(execution) {
    Ok(inventory) =>
      println(
        "Native file fixture \{label}: users=\{inventory.users}, active=\{inventory.active}, " +
        "generic_extents=\{inventory.generic_live_extents}, managed_pages=\{inventory.managed_live_pages}, " +
        "managed_blocks=\{inventory.managed_live_blocks}, requested_bytes=\{inventory.managed_requested_bytes}, " +
        "pending_extents=\{inventory.pending_extents}, closing=\{inventory.closing}",
      )
    Err(issue) =>
      println(
        "Native file fixture \{label}: inventory refused: " +
        capture_fixture_retirement_issue(issue),
      )
  }
}

///|
test "finite Native relation file preserves original capture and retires physical custody" {
  let (declaration, requirement, acquisition) = capture_fixture_logical()
  let foreign = capture_fixture_declaration()
  let directory = @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap()
  // The external scoped-test namespace creates these exclusive fixture files
  // before this process. This test neither creates nor mutates their contents.
  let selection : NativeRelationFileSelection = {
    directory,
    name: "row-source-input",
    resource: "records",
    items_path: ["items"],
    key_path: None,
    primary_identity: "id",
  }
  let malformed_selection = { ..selection, name: "row-source-malformed", }
  let oversized_selection = { ..selection, name: "row-source-oversized", }
  capture_fixture_require_geometry(declaration, acquisition, selection)
  let backing_path = @utf8.encode(directory + "/row-source-backing\u{0000}")
  let parent_bytes = 384L * 1024L * 1024L
  let fd = capture_fixture_open(backing_path, 2)
  assert_true(fd >= 0)
  let arena = @arena.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    parent_bytes,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 65536L,
      retained_bytes: 0L,
      execution_bytes: parent_bytes,
    },
    65536L,
  ).unwrap()
  arena.acquire_fd(fd).unwrap()
  let backing = arena.borrow_backing().unwrap()
  arena.enter_backing_borrow_scope(backing).unwrap()
  let domain = match
    arena
    .prepare_domain(backing, fd, 256L * 1024L * 1024L, {
      planning_work: 8,
      attempts: 4,
      holdings: 2,
      transfer_bytes: 16384L,
      retained_bytes: capture_fixture_retained_bytes,
      execution_bytes: capture_fixture_execution_bytes,
    })
    .unwrap() {
    @arena.PreparedDomain(domain) => domain
    @arena.PendingDomain(_, _) => fail("finite native file domain is partial")
  }
  arena.transfer_domain(domain).unwrap()
  arena.leave_backing_borrow_scope(backing).unwrap()
  arena.return_backing_borrow(backing).unwrap()
  arena.prepare_domain_read(domain).unwrap()
  let execution = match
    arena.prepare_domain_retained_execution(domain).unwrap() {
    @arena.ReadyRetainedExecution(execution) => execution
    @arena.PendingRetainedExecution(_, _) =>
      fail("finite native file retained execution is partial")
  }
  assert_true(
    arena.observe_domain_retained_execution_cleanup(execution) is Ok(_),
  )
  capture_fixture_report_inventory(arena, execution, "before source attempts")
  // A real prepared execution is not a current entered scope. Refusal occurs
  // before reservation or filesystem acquisition; the first entered usage
  // snapshot in capture_fixture_work verifies that no reservation was created.
  guard prepare_native_relation_file_capture(
      arena,
      execution,
      declaration,
      requirement,
      acquisition,
      "native-file-unentered",
      selection,
      capture_fixture_limits(),
    )
    is Err(unentered) else {
    fail("unentered native execution unexpectedly acquired a file capture")
  }
  assert_true(unentered.issue() is Execution(_))
  assert_true(unentered.retry_cleanup().unwrap())
  capture_fixture_work(
    arena, execution, declaration, foreign, requirement, acquisition, selection,
  )
  capture_fixture_report_inventory(arena, execution, "after positive capture")
  capture_fixture_malformed_work(
    arena, execution, declaration, requirement, acquisition, malformed_selection,
  )
  capture_fixture_report_inventory(arena, execution, "after malformed input")
  capture_fixture_oversized_work(
    arena, execution, declaration, requirement, acquisition, oversized_selection,
  )
  capture_fixture_report_inventory(arena, execution, "after oversized input")
  capture_fixture_partial_work(
    arena, execution, declaration, requirement, acquisition, selection,
  )
  // Only after the nested work released every Read-owned alias may the actual
  // C context retire, its original child report settle, and the FD be closed.
  capture_fixture_report_inventory(arena, execution, "before physical close")
  match arena.observe_domain_retained_execution_scope(execution) {
    Ok(scope) =>
      println(
        "Native file fixture scope before physical close: " +
        @debug.to_string(scope),
      )
    Err(issue) =>
      println(
        "Native file fixture scope observation refused: " +
        capture_fixture_retirement_issue(issue),
      )
  }
  match arena.close_domain_retained_execution(execution) {
    Ok(_) => ()
    Err(issue) => {
      let detail = capture_fixture_retirement_issue(issue)
      capture_fixture_report_inventory(
        arena, execution, "physical close refused",
      )
      match arena.observe_domain_retained_execution_cleanup_scope(execution) {
        Ok(scope) =>
          println(
            "Native file fixture cleanup scope after refusal: " +
            @debug.to_string(scope),
          )
        Err(observation) =>
          println(
            "Native file fixture cleanup scope observation refused: " +
            capture_fixture_retirement_issue(observation),
          )
      }
      // Keep the original execution/domain/FD unacknowledged on refusal. No
      // forced release, new scope or process exit is substituted for cleanup.
      fail(
        "original Native retained execution close refused: " +
        detail +
        "; physical retirement not acknowledged",
      )
    }
  }
  // A completed physical close cannot be observed as another current owner.
  assert_true(
    arena.observe_domain_retained_execution_cleanup(execution) is Err(_),
  )
  arena.close_domain_after_owner_ack(domain).unwrap()
  arena.try_close().unwrap()
  assert_eq(capture_fixture_close(fd), 0)
  // The external namespace owner removes the fixture files after this process.
}

///|
// Independent contract fixture DATA copied unchanged from
// client_local_host/resident_source_query_regression_wbtest.mbt and
// client_local_host/original_row_contracts_wbtest.mbt. No product result is used
// as a capture expectation, and no private package fixture function is called.
let capture_fixture_registry : String =
  #|{"REL.select":{"inputs":["relation"],"output":"relation"},"REL.where":{"inputs":["relation"],"output":"relation"},"REL.assert_all":{"inputs":["relation"],"output":"relation"},"REL.assert_unique":{"inputs":["relation"],"output":"relation"},"REL.derive":{"inputs":["relation"],"output":"relation","execution_extensions":{"ordered_bindings":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/REL.derive.ordered","cid":"sha256:00a8fa5a08e8d02ef2e2864deb77be1b6a637d0f7f78d7cfa7b5ec9555573b29"}}},"REL.orderByStable":{"inputs":["relation"],"output":"relation"},"REL.limit":{"inputs":["relation"],"output":"relation"},"REL.topk":{"inputs":["relation"],"output":"relation"},"REL.window.fixed":{"inputs":["relation"],"output":"relation"},"REL.window.sliding":{"inputs":["relation"],"output":"relation"},"REL.window.project":{"inputs":["relation"],"output":"relation"},"REL.window.lag":{"inputs":["relation"],"output":"relation"},"REL.watermark":{"inputs":["relation"],"output":"relation"},"REL.pivot":{"inputs":["relation"],"output":"relation"},"REL.unpivot":{"inputs":["relation"],"output":"relation"},"REL.unnest":{"inputs":["relation"],"output":"relation"},"REL.dedupeRows":{"inputs":["relation"],"output":"relation"},"REL.json.pick":{"inputs":["relation"],"output":"relation"},"REL.join":{"inputs":["relation","relation"],"output":"relation"},"REL.groupBy":{"inputs":["relation"],"output":"relation"},"REL.distinct":{"inputs":["relation"],"output":"relation"},"REL.unionAll":{"inputs":["relation","relation"],"output":"relation"},"REL.except_rows":{"inputs":["relation","relation"],"output":"relation"},"REL.intersect_rows":{"inputs":["relation","relation"],"output":"relation"},"REL.cross_join":{"inputs":["relation","relation"],"output":"relation"},"REL.topk_partitioned":{"inputs":["relation"],"output":"relation"},"REL.analytic":{"inputs":["relation"],"output":"relation"},"SGA.normalize":{"inputs":["graph"],"output":"graph"},"SGA.reachable":{"input_alternatives":[["graph"],["graph","relation"]],"output":"relation"},"SGA.bounds_check":{"inputs":["graph"],"output":"relation"},"SGA.degree_metrics":{"inputs":["graph"],"output":"relation"},"SGA.apply_delta":{"inputs":["graph","relation"],"output":"graph"},"SGA.diff":{"inputs":["graph","graph"],"output":"relation"},"SGA.graft":{"inputs":["graph","graph"],"output":"graph"},"SGA.union_structural":{"finite_inputs":{"repeated_input":"graph","minimum_inputs":2},"output":"graph"},"SGA.diff_structural":{"inputs":["graph","graph"],"output":"graph"},"SGA.match_nodes":{"inputs":["graph"],"output":"relation"},"SGA.match_edges":{"inputs":["graph"],"output":"relation"},"SGA.traverse":{"input_alternatives":[["graph"],["graph","relation"]],"output":"relation"},"SGA.shortest_path":{"input_alternatives":[["graph"],["graph","relation"],["graph","relation","relation"]],"output":"relation"},"SGA.components":{"inputs":["graph"],"output":"relation"},"SGA.subgraph":{"input_alternatives":[["graph"],["graph","relation"]],"output":"graph"},"SGA.equal":{"inputs":["graph","graph"],"output":"relation"},"SGA.mean_structural":{"finite_inputs":{"repeated_input":"graph","minimum_inputs":1},"output":"graph"},"TEA.window.fixed_label":{"inputs":["event_stream"],"output":"event_stream"},"TEA.window.sliding_assign":{"inputs":["event_stream"],"output":"event_stream"},"TEA.watermark.label":{"inputs":["event_stream"],"output":"event_stream"},"TEA.window.session_assign":{"inputs":["event_stream"],"output":"event_stream"},"TEA.dedupe":{"inputs":["event_stream"],"output":"event_stream"},"TEA.join.asof":{"inputs":["event_stream","relation"],"output":"relation"},"TEA.sequence.match":{"inputs":["event_stream"],"output":"relation"},"TEA.time_series":{"inputs":[],"output":"relation"},"TEA.join.interval":{"inputs":["relation","relation"],"output":"relation"},"VEC.normalize_l2":{"inputs":["vector_set"],"output":"vector_set"},"VEC.score_sort":{"inputs":["vector_set"],"output":"vector_set"},"VEC.knn_join":{"inputs":["vector_set","vector_set"],"output":"relation"},"VEC.pool":{"inputs":["vector_set"],"output":"vector_set"},"VEC.merge_rankings":{"policy_inputs":{"max":{"inputs":["relation","relation"]},"weighted_sum":{"inputs":["relation","relation"]},"rrf":{"repeated_input":"relation","minimum_inputs":2}},"output":"relation"},"BRIDGE.graph.to_edge_rows":{"inputs":["graph"],"output":"relation"},"BRIDGE.graph.to_node_rows":{"inputs":["graph"],"output":"relation"},"BRIDGE.rows.to_graph":{"finite_inputs":{"repeated_input":"relation","minimum_inputs":0},"output":"graph","execution_contract":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/BRIDGE.rows.to_graph","cid":"sha256:0979999a64bb47f7fcb0d113c0bbcab592ad0a268b548a8776f8fac4fd6f6d84"}},"BRIDGE.events.to_rows":{"inputs":["event_stream"],"output":"relation"},"BRIDGE.rows.to_events":{"inputs":["relation"],"output":"event_stream"},"BRIDGE.vectors.to_rows":{"inputs":["vector_set"],"output":"relation"},"BRIDGE.rows.to_vectors":{"inputs":["relation"],"output":"vector_set"},"EFFECT.plan":{"inputs":["relation"],"output":"relation"},"REL.values":{"inputs":[],"output":"relation","execution_contract":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/REL.values","cid":"sha256:96c7925a693801dcb3bce9f3e2da9b4fd9ed39e517af90cbac0e1adbee5ad2ae"}},"ACTQL.expression_fragment/0.1":{"inputs":["relation"],"output":"relation","execution_contract":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/ACTQL.expression_fragment~10.1","cid":"sha256:ced7ee00f232f8d5bcfde44dfc769d9d6ae02c8386e54db7d844d43f922bac90"}},"TEA.calendar.bucket":{"inputs":["relation"],"output":"relation","execution_contract":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/TEA.calendar.bucket","cid":"sha256:8cbb70e4edcd1dd29deee777b44b3f09b9cee337b5495944ca895fa3065b6227"}},"TEA.calendar.series":{"inputs":[],"output":"relation","execution_contract":{"file":"spec/contracts/actql-aoa.json","pointer":"/execution_contracts/TEA.calendar.series","cid":"sha256:8070a5fa9b6177df0d407b474a2b34aff2ecde9cf9c5b726191f7bd908a4dc83"}}}

///|
let capture_fixture_values : String =
  #|{"version":"actql-rel-values-execution/0.1","operation":"REL.values","inputs":[],"output":"relation","dependencies":{"canonical_value_contract":{"path":"spec/contracts/actql-protocol-schemas.json","pointer":"/schemas/canonical_value_contract","cid":"sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1"}},"params_schema":{"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://smooth.dev/schemas/actql/rel-values-params-0.1.json","type":"object","additionalProperties":false,"required":["schema","rows"],"properties":{"schema":{"type":"object","minProperties":1,"propertyNames":{"pattern":"^(?!__cid$)(?!__actql_)(?![\\s\\S]*\\.)(?=[\\s\\S]*\\S)[\\s\\S]+$"},"additionalProperties":{"$ref":"#/$defs/value_contract"}},"rows":{"type":"array","items":{"type":"object","additionalProperties":{"$ref":"#/$defs/wire_value"}}}},"$defs":{"value_contract":{"oneOf":[{"type":"object","additionalProperties":false,"required":["type","nullable","precision","scale"],"properties":{"type":{"const":"decimal"},"nullable":{"type":"boolean"},"precision":{"type":"integer","minimum":1,"maximum":38},"scale":{"type":"integer","minimum":0,"maximum":38}},"allOf":[{"if":{"properties":{"precision":{"const":1}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":1}}}},{"if":{"properties":{"precision":{"const":2}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":2}}}},{"if":{"properties":{"precision":{"const":3}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":3}}}},{"if":{"properties":{"precision":{"const":4}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":4}}}},{"if":{"properties":{"precision":{"const":5}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":5}}}},{"if":{"properties":{"precision":{"const":6}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":6}}}},{"if":{"properties":{"precision":{"const":7}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":7}}}},{"if":{"properties":{"precision":{"const":8}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":8}}}},{"if":{"properties":{"precision":{"const":9}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":9}}}},{"if":{"properties":{"precision":{"const":10}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":10}}}},{"if":{"properties":{"precision":{"const":11}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":11}}}},{"if":{"properties":{"precision":{"const":12}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":12}}}},{"if":{"properties":{"precision":{"const":13}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":13}}}},{"if":{"properties":{"precision":{"const":14}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":14}}}},{"if":{"properties":{"precision":{"const":15}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":15}}}},{"if":{"properties":{"precision":{"const":16}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":16}}}},{"if":{"properties":{"precision":{"const":17}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":17}}}},{"if":{"properties":{"precision":{"const":18}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":18}}}},{"if":{"properties":{"precision":{"const":19}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":19}}}},{"if":{"properties":{"precision":{"const":20}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":20}}}},{"if":{"properties":{"precision":{"const":21}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":21}}}},{"if":{"properties":{"precision":{"const":22}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":22}}}},{"if":{"properties":{"precision":{"const":23}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":23}}}},{"if":{"properties":{"precision":{"const":24}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":24}}}},{"if":{"properties":{"precision":{"const":25}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":25}}}},{"if":{"properties":{"precision":{"const":26}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":26}}}},{"if":{"properties":{"precision":{"const":27}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":27}}}},{"if":{"properties":{"precision":{"const":28}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":28}}}},{"if":{"properties":{"precision":{"const":29}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":29}}}},{"if":{"properties":{"precision":{"const":30}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":30}}}},{"if":{"properties":{"precision":{"const":31}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":31}}}},{"if":{"properties":{"precision":{"const":32}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":32}}}},{"if":{"properties":{"precision":{"const":33}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":33}}}},{"if":{"properties":{"precision":{"const":34}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":34}}}},{"if":{"properties":{"precision":{"const":35}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":35}}}},{"if":{"properties":{"precision":{"const":36}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":36}}}},{"if":{"properties":{"precision":{"const":37}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":37}}}},{"if":{"properties":{"precision":{"const":38}},"required":["precision"]},"then":{"properties":{"scale":{"maximum":38}}}}]},{"type":"object","additionalProperties":false,"required":["type","nullable"],"properties":{"type":{"const":"string"},"nullable":{"type":"boolean"},"min_length":{"type":"integer","minimum":0,"maximum":9007199254740991},"max_codepoints":{"type":"integer","minimum":0,"maximum":9007199254740991},"max_utf8_bytes":{"type":"integer","minimum":0,"maximum":9007199254740991},"enum":{"type":"array","items":{"type":"string"}}}},{"type":"object","additionalProperties":false,"required":["type","nullable"],"properties":{"type":{"enum":["number","boolean","timestamp","date"]},"nullable":{"type":"boolean"}}},{"type":"object","additionalProperties":false,"required":["type","nullable","items"],"properties":{"type":{"const":"array"},"nullable":{"type":"boolean"},"items":{"$ref":"#/$defs/value_contract"},"max_items":{"type":"integer","minimum":0,"maximum":9007199254740991}}},{"type":"object","additionalProperties":false,"required":["type","nullable","additional_properties","fields"],"properties":{"type":{"const":"object"},"nullable":{"type":"boolean"},"additional_properties":{"const":false},"fields":{"type":"object","propertyNames":{"pattern":"^(?!__cid$)(?!__actql_)(?![\\s\\S]*\\.)(?=[\\s\\S]*\\S)[\\s\\S]+$"},"additionalProperties":{"$ref":"#/$defs/value_contract"}}}},{"type":"object","additionalProperties":false,"required":["type","nullable","dimensions","element_type"],"properties":{"type":{"const":"vector"},"nullable":{"type":"boolean"},"dimensions":{"type":"integer","minimum":1},"element_type":{"const":"f32"}}},{"type":"object","required":["type","nullable"],"additionalProperties":false,"properties":{"type":{"const":"int64"},"nullable":{"type":"boolean"}}}]},"wire_value":{"oneOf":[{"type":["null","boolean","number","string"]},{"type":"array","items":{"$ref":"#/$defs/wire_value"}},{"type":"object","additionalProperties":{"$ref":"#/$defs/wire_value"}}]}}},"semantics":{"schema_form":"nonempty_field_map_of_complete_checked_constructible_contracts","cells":"bound_typed_wire_values_without_cell_wrappers","quotation":"remove_exact_singleton_literal_once_before_execution_params","parameter_resolution":"resolve_only_authored_cell_root_holes_before_execution_params","business_objects":"never_reinterpret_param_or_literal_members","row_fields":"exact_declared_set_including_nullable_fields","values":"recursive_declared_type_admission_without_cast_repair_or_rounding","strings":"preserve_well_formed_unicode_scalar_sequence_without_NFC_or_line_break_repair","object_member_names":"NFC_then_LF_reject_noncanonical_names_and_collisions","string_extents":"retained_unicode_scalars_and_UTF8_bytes","text_enumeration":"exact_original_vector_membership_intersected_with_retained_extents_preserve_nullable_and_empty_duplicates_order_no_constraint_stripping_or_authority","decimal":"canonical_fixed_scale_string_under_declared_precision_and_scale","int64":"canonical_signed_decimal_String_in_full_signed64_range_distinct_logical_type_no_JSON_Number_or_implicit_coercion","empty_rows":"retain_declared_schema","row_order":"retain_occurrence_order","row_multiplicity":"retain_all_occurrences","object_key_order":"canonical_utf16_order_not_row_order","publication":"validate_all_rows_and_resolved_limits_before_publication","recursive_resources":{"selected_root_types":["array","object","vector"],"bytes":"sum_canonical_typed_wire_cell_bytes_across_all_occurrences_including_null_without_double_counting_nested_containers","byte_exclusions":["scalar_typed_cells","row_keys","row_wrappers","rows_wrapper","schema"],"host_byte_ceiling":"max_nested_value_bytes","depth":"declared_cell_type_scalar_0_vector_1_array_1_plus_items_object_1_plus_max_fields","depth_excludes":["row_wrapper","rows_wrapper"],"host_depth_ceiling":"max_nested_value_depth","empty_or_null":"type_depth_still_checked_zero_selected_cells_have_zero_bytes","failure":"atomic_before_any_consumer_without_truncation"},"unsupported_backend":"reject_runnable_plan_without_exact_registered_contract_support"}}

///|
let capture_fixture_fragment : String =
  #|{"version":"actql-expression-fragment-execution/0.1","operation":"ACTQL.expression_fragment/0.1","inputs":["relation"],"output":"relation","dependencies":{"expression_contract":{"file":"spec/contracts/actql-expressions.json","pointer":"","cid":"sha256:2849a6667980fc51ed51a04879470a97068fd08e358d784262602a09b22dacda"},"fragment_schema":{"file":"spec/contracts/actql-expressions.json","pointer":"/schemas/fragment","cid":"sha256:be96b6072058cb165d5350a2575403a4fe35bafc229e669ca296aacc0ca79cdf"}},"params_schema":{"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"urn:actql:expression-fragment-params:0.1","type":"object","additionalProperties":false,"required":["fragment"],"properties":{"fragment":{"$ref":"urn:actql:expression-fragment:0.1"}}},"semantics":{"schema_resolution":"resolve_fragment_schema_from_exact_pinned_dependency_without_network_lookup","local_source":"exactly_one_request_pipeline_source_named_input","admission":"regenerate_and_compare_sealed_fragment_under_pinned_expression_contract_before_evaluation","fragment_identity":"hash_complete_canonical_fragment_excluding_only_root_fragment_cid","retained_material":"retain_opcode_and_complete_fragment_in_canonical_composition","inner_graph":"not_a_standalone_execution_artifact","carrier_projection":"validation_witness_only_never_hashed_executed_or_used_as_type_evidence","obligations":"enforce_fragment_input_root_output_limits_demands_and_runtime_checks","backend":"reject_execution_without_support_for_exact_contract_and_all_used_extensions","authority":"registration_does_not_establish_program_completion_or_execution_permission"}}

///|
let capture_fixture_query_contract : String = "{\"version\":\"actql-query-acquisition-contract/0.1\",\"scope\":\"exclusive_finite_relation_scan_filter_select\",\"dependencies\":{\"canonical_value_contract\":{\"path\":\"spec/contracts/actql-protocol-schemas.json\",\"pointer\":\"/schemas/canonical_value_contract\",\"cid\":\"sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1\"},\"consumer_capacity\":{\"path\":\"spec/contracts/actql-consumer-capacity.json\",\"pointer\":\"\",\"cid\":\"sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f\"}},\"schemas\":{\"requirement\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"version\",\"owner\",\"source_ref\",\"source_contract_cid\",\"input_contract_cid\",\"output_contract_cid\",\"request\",\"parameter_values_cid\",\"filter\",\"select\",\"source_validation\",\"source_order_cid\",\"logical_guards\"],\"properties\":{\"version\":{\"const\":\"actql-query-acquisition/0.1\"},\"owner\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"program_source_cid\",\"stage\",\"input\"],\"properties\":{\"program_source_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"stage\":{\"type\":\"string\",\"minLength\":1},\"input\":{\"type\":\"string\",\"minLength\":1},\"run_definition_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"source_ref\":{\"type\":\"string\",\"minLength\":1},\"source_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"input_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"output_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"request\":{\"type\":\"object\"},\"parameter_values_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"filter\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"occurrence\",\"expression_cid\"],\"properties\":{\"occurrence\":{\"type\":\"string\",\"pattern\":\"^/steps/(0|[1-9][0-9]*)/(filter|select)$\"},\"expression_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"select\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"occurrence\",\"fields\"],\"properties\":{\"occurrence\":{\"type\":\"string\",\"pattern\":\"^/steps/(0|[1-9][0-9]*)/(filter|select)$\"},\"fields\":{\"type\":\"array\",\"minItems\":1,\"items\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"input\",\"output\"],\"properties\":{\"input\":{\"type\":\"string\",\"minLength\":1},\"output\":{\"type\":\"string\",\"minLength\":1}}}}}},\"source_validation\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope\",\"fields\"],\"properties\":{\"scope\":{\"const\":\"selected_scan\"},\"fields\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"minLength\":1},\"uniqueItems\":true}}},\"source_order_cid\":{\"anyOf\":[{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},{\"type\":\"null\"}]},\"logical_guards\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"max_rows\",\"max_value_bytes\"],\"properties\":{\"max_rows\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991},\"max_value_bytes\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}}},\"$schema\":\"https://json-schema.org/draft/2020-12/schema\"},\"completed_observation\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"version\",\"requirement_cid\",\"owner\",\"source_ref\",\"source_contract_cid\",\"parameter_values_cid\",\"resolved_request_cid\",\"snapshot\",\"actual_access\",\"coverage\",\"output\",\"retention\"],\"properties\":{\"version\":{\"const\":\"actql-query-observation/0.1\"},\"requirement_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"owner\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"program_source_cid\",\"stage\",\"input\"],\"properties\":{\"program_source_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"stage\":{\"type\":\"string\",\"minLength\":1},\"input\":{\"type\":\"string\",\"minLength\":1},\"run_definition_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"source_ref\":{\"type\":\"string\",\"minLength\":1},\"source_contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"parameter_values_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"resolved_request_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"snapshot\":{\"anyOf\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"token_cid\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"token_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},{\"type\":\"null\"}]},\"actual_access\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope_cid\",\"provider_scope_cid\",\"received_rows\",\"received_fields\",\"received_bytes\"],\"properties\":{\"scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"provider_scope_cid\":{\"anyOf\":[{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},{\"type\":\"null\"}]},\"received_rows\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991},\"received_fields\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"minLength\":1},\"uniqueItems\":true},\"received_bytes\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}},\"coverage\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope_cid\",\"complete\",\"source_validation_evidence_cid\",\"filter_evidence_cid\",\"select_evidence_cid\"],\"properties\":{\"scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"complete\":{\"const\":true},\"source_validation_evidence_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"filter_evidence_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"select_evidence_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},\"output\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"rows_cid\",\"row_count\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"rows_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"row_count\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}},\"retention\":{\"const\":\"process\"}},\"$schema\":\"https://json-schema.org/draft/2020-12/schema\"}},\"semantics\":{\"owner\":\"program_source_cid_is_authority_bearing_program_definition_cid_not_program_semantics_or_source_text_hash\",\"query_time_owner\":\"declared_query_time_dependency_requires_original_admitted_run_definition_cid_in_requirement_and_completed_observation_owner_with_same_nominal_context_and_saved_run_no_resample_no_grant\",\"derivation\":\"checked_exclusive_scan_filter_select_without_backend_cost_or_placement\",\"capture\":\"completed_select_output_before_any_consumer\",\"identity\":\"sha256_of_canonical_json_utf8_entire_body_no_self_cid\",\"request_values\":\"bound_wire_values_no_reinterpretation_of_business_param_or_literal\",\"parameter_identity\":\"existing_typed_parameter_values_projection_of_used_request_and_query_names\",\"source_validation\":\"all_known_fields_of_selected_scan_before_filter_including_rows_excluded_by_filter\",\"demand\":\"existing_checked_expression_demand_without_eager_undemanded_evaluation\",\"native\":\"preserve_mandatory_admission_and_demanded_failures_before_projection\",\"logical_guards\":\"max_rows_on_capture_output_max_value_bytes_on_admitted_records_and_demanded_roots\",\"physical_budget\":\"actual_received_bytes_rows_and_retention_independent_of_logical_output\",\"failure\":\"atomic_no_success_capture_or_consumer_on_failure_or_cancellation\",\"evidence\":\"verify_actual_execution_evidence_not_candidate_coverage_proposals_or_self_cid_only\",\"snapshot\":\"source_specific_no_universal_snapshot_token_or_isolation_requirement\",\"retention\":\"same_process_immutable_completed_observation_not_durable_run_or_recovery\",\"invocation\":\"existing_invocation_rules_retain_actual_observation_identity_not_result_identity_only\"}}"

///|
let capture_fixture_evidence_contract : String = "{\"version\":\"actql-query-process-evidence-contract/0.1\",\"dependencies\":{\"query_acquisition\":{\"path\":\"spec/contracts/actql-query-acquisition.json\",\"pointer\":\"\",\"cid\":\"sha256:5a95e60847276d02229eba9550dd9808a8a8c2764decd4dad667954f020db7cc\"}},\"schemas\":{\"record\":{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"version\",\"issuer\",\"attempt\",\"requirement_cid\",\"role\",\"snapshot\",\"scan_scope_cid\",\"actual_access\",\"output\"],\"properties\":{\"version\":{\"const\":\"actql-query-process-evidence/0.1\"},\"issuer\":{\"type\":\"string\",\"minLength\":1},\"attempt\":{\"type\":\"string\",\"minLength\":1},\"requirement_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"role\":{\"enum\":[\"source_validation\",\"filter\",\"select\"]},\"snapshot\":{\"anyOf\":[{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"token_cid\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"token_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"}}},{\"type\":\"null\"}]},\"scan_scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"actual_access\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"scope_cid\",\"provider_scope_cid\",\"received_rows\",\"received_fields\",\"received_bytes\"],\"properties\":{\"scope_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"provider_scope_cid\":{\"anyOf\":[{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},{\"type\":\"null\"}]},\"received_rows\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991},\"received_fields\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"minLength\":1},\"uniqueItems\":true},\"received_bytes\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}},\"output\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"contract_cid\",\"rows_cid\",\"row_count\"],\"properties\":{\"contract_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"rows_cid\":{\"type\":\"string\",\"pattern\":\"^sha256:[0-9a-f]{64}$\"},\"row_count\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740991}}}}}},\"semantics\":{\"preimage\":\"entire_record_canonical_json_utf8_sha256_no_self_cid\",\"authority\":\"authorized_host_private_issuer_and_live_opaque_success_handle_not_wire_or_cid_alone\",\"issuance\":\"after_complete_scan_validation_filter_select_limits_and_immutable_output_retention\",\"attempt\":\"host_allocated_unique_within_unique_process_issuer_never_reused_or_caller_selected\",\"binding\":\"exact_requirement_attempt_snapshot_scan_scope_actual_access_and_retained_output_for_all_three_roles\",\"native\":\"authorized_source_execution_covers_full_selected_scan_not_only_host_received_rows_or_columns\",\"source_order\":\"null_only_in_this_profile_relative_order_is_not_total_order_evidence\",\"lifetime\":\"same_process_no_deserialization_rehydration_or_durable_capture\",\"host_adapter\":\"host_authorized_execution_with_owned_consistent_read_view_full_scan_validation_and_query_not_driver_location_or_sql_success\",\"read_view\":\"private_task_session_transaction_binding_not_snapshot_token_no_cross_attempt_or_read_view_substitution\",\"access_accounting\":\"engine_internal_scan_host_row_receipt_and_retention_are_distinct_auxiliary_row_receipts_are_not_hidden_or_double_counted\",\"receipt_scope\":\"one_logical_received_sequence_only_independent_validation_and_query_receipts_require_an_additional_admitted_contract\",\"scan_failure\":\"invalid_excluded_rows_still_fail_no_global_diagnostic_order_or_total_order_from_validation_traversal\"}}"

///|
fn capture_fixture_whole_logical() -> (
  @rows.RowDeclaration,
  @rows.RowInputAcquisition,
) raise {
  let declaration = capture_fixture_declaration()
  let (wire, cid) = capture_fixture_environment(declaration)
  let environment = @publication_host.admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"native-file-capture","stages":[{"id":"acquire","inputs":{"remote":{"connector":"native-file-fixture","resource":"records"}},"steps":[{"select":["id","value"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","value"]}}},{"id":"compute","inputs":{"input":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"filter":"value > 0"},{"select":["id","value"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","value"]}}}],"results":{"rows":{"from":{"stage":"compute","result":"rows"}}}}
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let contracts = @local.prepare_installed_sequence_contracts(
    capture_fixture_registry,
    capture_fixture_values,
    Some(capture_fixture_fragment),
    None,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "native-whole-source-file",
  ).unwrap()
  let selected = @local.select_installed_source_input(prepared, request, 0, 0).unwrap()
  guard selected is @sourceviews.WholeInputRoute(original) else {
    fail("unfiltered Source must retain its whole-input original")
  }
  let page = capture_fixture_limits().page
  let capacity = @local.prepare_installed_whole_source_capacity(
    prepared,
    original,
    declaration,
    contracts,
    {
      max_rows: 2,
      page,
      retention: {
        max_nodes: 512,
        max_text_bytes: 8192,
        max_depth: 8,
        max_work: 1000000,
      },
      wire: {
        max_columns: 2,
        max_order_work: 10000,
        max_bytes: 8192,
        max_nodes: 512,
        max_depth: 8,
      },
    },
    None,
  ).unwrap()
  (declaration, @local.installed_whole_source_acquisition(capacity))
}

///|
fn capture_fixture_whole_work(
  arena : @arena.InstalledArenaHost,
  execution : @arena.InstalledArenaRetainedExecution,
  declaration : @rows.RowDeclaration,
  foreign : @rows.RowDeclaration,
  acquisition : @rows.RowInputAcquisition,
  selection : NativeRelationFileSelection,
) -> Unit raise {
  arena.enter_domain_retained_execution(execution).unwrap()
  // Cleanup metadata never becomes an entry point into a currently entered Read.
  assert_true(
    arena.observe_domain_retained_execution_cleanup(execution) is Err(_),
  )
  let ledger = arena.borrow_domain_retained_execution_ledger(execution).unwrap()
  let limits = capture_fixture_limits()
  let before = @resources.ledger_usage(ledger)
  assert_eq(before.transferred_bytes, 0L)
  assert_eq(before.reserved_attempts, 0)
  assert_eq(before.reserved_transfer_bytes, 0L)
  assert_eq(before.reserved_retention_bytes, 0L)
  assert_eq(before.reserved_execution_bytes, 0L)
  // Equal logical declaration bytes never replace the admitted original.
  assert_eq(foreign.catalog_cid, declaration.catalog_cid)
  let refused = prepare_native_relation_file_input_capture(
    arena, execution, foreign, acquisition, "native-file-foreign", selection, limits,
  )
  guard refused is Err(failure) else {
    fail("foreign declaration unexpectedly acquired a native reader")
  }
  assert_true(failure.issue() is Row(@rows.ForeignDeclaration))
  assert_true(failure.retry_cleanup().unwrap())
  assert_eq(@resources.ledger_usage(ledger), before)
  let owner = capture_fixture_prepared(
    prepare_native_relation_file_input_capture(
      arena, execution, declaration, acquisition, "native-file-original", selection,
      limits,
    ),
    "positive file prepare",
  )
  assert_true(owner.capture() is Err(Unavailable))
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
  let mut completed = false
  let mut charged_before_admission = false
  for _ in 0..<10000 {
    if owner.advance(32).unwrap() {
      completed = true
      break
    }
    if owner.phase is Received {
      assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 62L)
      charged_before_admission = true
    }
  }
  assert_true(completed)
  assert_true(charged_before_admission)
  // This is the exact original document, including its envelope, charged once.
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 62L)
  let capture = owner.capture().unwrap()
  assert_true(physical_equal(owner.capture().unwrap(), capture))
  let captured_usage = @resources.ledger_usage(ledger)
  arena.leave_domain_retained_execution(execution).unwrap()
  // A completed capture is not borrowable outside its original entered scope.
  // Do not advance here: that would intentionally record a sticky failure.
  assert_true(owner.capture() is Err(Unavailable))
  arena.enter_domain_retained_execution(execution).unwrap()
  assert_true(
    physical_equal(
      ledger,
      arena.borrow_domain_retained_execution_ledger(execution).unwrap(),
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), captured_usage)
  assert_true(owner.advance(32).unwrap())
  assert_true(physical_equal(owner.capture().unwrap(), capture))
  let source = @rows.row_capture_source(capture).unwrap()
  let original = @rows.row_capture_original_read(capture).unwrap()
  assert_true(@query.captured_source_available(source))
  assert_eq(@query.captured_source_row_count(source), Some(2))
  assert_true(@execution.supplied_relation_read_available(original))
  assert_eq(@execution.supplied_relation_read_row_count(original), 2)
  assert_true(
    @execution.supplied_relation_read_cell(original, 0, 0)
    is Some(@admitted.Text("first")),
  )
  assert_true(
    @execution.supplied_relation_read_cell(original, 1, 0)
    is Some(@admitted.Text("second")),
  )
  assert_true(
    @execution.supplied_relation_read_cell(original, 0, 1)
    is Some(@admitted.Number(1)),
  )
  assert_true(
    @execution.supplied_relation_read_cell(original, 1, 1)
    is Some(@admitted.Number(2)),
  )
  let mut closed = false
  for _ in 0..<10000 {
    match owner.close() {
      Ok(true) => {
        closed = true
        break
      }
      Ok(false) | Err(Row(@rows.InvalidState)) => ()
      Err(_) => fail("native relation file cleanup failed")
    }
  }
  assert_true(closed)
  assert_true(owner.close().unwrap())
  assert_true(owner.capture() is Err(Unavailable))
  assert_true(@rows.row_capture_source(capture) is Err(_))
  assert_true(@rows.row_capture_original_read(capture) is None)
  assert_false(@query.captured_source_available(source))
  assert_false(@execution.supplied_relation_read_available(original))
  let retired = @resources.ledger_usage(ledger)
  assert_eq(retired.transferred_bytes, 62L)
  assert_eq(retired.held_bytes, 0L)
  assert_eq(retired.reserved_transfer_bytes, 0L)
  assert_eq(retired.reserved_retention_bytes, 0L)
  assert_eq(retired.reserved_execution_bytes, 0L)
  arena.leave_domain_retained_execution(execution).unwrap()
  // No owner, capture, original read or child-allocated usage snapshot escapes.
}

///|
test "finite Native whole Source file captures original input and retires same physical owner" {
  let (declaration, acquisition) = capture_fixture_whole_logical()
  let foreign = capture_fixture_declaration()
  let directory = @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap()
  // The external scoped-test namespace creates these exclusive fixture files
  // before this process. This test neither creates nor mutates their contents.
  let selection : NativeRelationFileSelection = {
    directory,
    name: "row-source-input",
    resource: "records",
    items_path: ["items"],
    key_path: None,
    primary_identity: "id",
  }
  let backing_path = @utf8.encode(directory + "/row-source-backing\u{0000}")
  let parent_bytes = 384L * 1024L * 1024L
  let fd = capture_fixture_open(backing_path, 2)
  assert_true(fd >= 0)
  let arena = @arena.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    parent_bytes,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 65536L,
      retained_bytes: 0L,
      execution_bytes: parent_bytes,
    },
    65536L,
  ).unwrap()
  arena.acquire_fd(fd).unwrap()
  let backing = arena.borrow_backing().unwrap()
  arena.enter_backing_borrow_scope(backing).unwrap()
  let domain = match
    arena
    .prepare_domain(backing, fd, 256L * 1024L * 1024L, {
      planning_work: 8,
      attempts: 4,
      holdings: 2,
      transfer_bytes: 16384L,
      retained_bytes: capture_fixture_retained_bytes,
      execution_bytes: capture_fixture_execution_bytes,
    })
    .unwrap() {
    @arena.PreparedDomain(domain) => domain
    @arena.PendingDomain(_, _) => fail("finite native file domain is partial")
  }
  arena.transfer_domain(domain).unwrap()
  arena.leave_backing_borrow_scope(backing).unwrap()
  arena.return_backing_borrow(backing).unwrap()
  arena.prepare_domain_read(domain).unwrap()
  let execution = match
    arena.prepare_domain_retained_execution(domain).unwrap() {
    @arena.ReadyRetainedExecution(execution) => execution
    @arena.PendingRetainedExecution(_, _) =>
      fail("finite native file retained execution is partial")
  }
  capture_fixture_whole_work(
    arena, execution, declaration, foreign, acquisition, selection,
  )
  arena.close_domain_retained_execution(execution).unwrap()
  arena.close_domain_after_owner_ack(domain).unwrap()
  arena.try_close().unwrap()
  assert_eq(capture_fixture_close(fd), 0)
}

///|
fn[T, E] Result::managed_capture_stage(
  self : Result[T, E],
  stage : String,
) -> T raise {
  match self {
    Ok(value) => value
    Err(_) => fail(stage)
  }
}

///|
fn[T] Option::managed_capture_stage(self : T?, stage : String) -> T raise {
  match self {
    Some(value) => value
    None => fail(stage)
  }
}

///|
// The finite physical fixture backs the existing Request policy, not a normal
// Source profile or an Account. Actual input acquisition remains file-bounded.
fn managed_capture_fixture_facility(
  input : Array[Int],
) -> (
  @arena.InstalledArenaHost,
  @arena.InstalledArenaDomain,
  @arena.InstalledArenaRetainedExecution,
  @resources.BackedPreparationAdmission[Array[Int]],
) raise {
  let policy = @local.client_local_preparation_initial_limits(
    @local.client_local_resource_policy(),
  ).managed_capture_stage("original stage 14")
  let policy = {
    ..policy,
    attempts: 32,
    holdings: 32,
    transfer_bytes: 32000000L,
  }
  let payload = policy.retained_bytes + policy.execution_bytes
  let mut domain_bytes = payload
  for _ in 0..<16 {
    let required = @bootstrap.execution_domain_necessary_bytes(
      domain_bytes, payload,
    )
    assert_true(required > 0L)
    if required <= domain_bytes {
      break
    }
    domain_bytes = required
  }
  let bytes = domain_bytes * 2L
  let arena = @arena.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    bytes,
    {
      planning_work: 100000,
      attempts: 100000,
      holdings: 100000,
      transfer_bytes: 100000000000L,
      retained_bytes: 0L,
      execution_bytes: bytes,
    },
    65536L,
  ).managed_capture_stage("original stage 48")
  arena.acquire().managed_capture_stage("original stage 49")
  let backing = arena
    .borrow_backing()
    .managed_capture_stage("original stage 50")
  arena
  .enter_backing_borrow_scope(backing)
  .managed_capture_stage("original stage 51")
  let domain = match
    arena
    .prepare_domain_in_process(backing, domain_bytes, policy)
    .managed_capture_stage("original stage 53") {
    @arena.PreparedDomain(value) => value
    @arena.PendingDomain(_, _) => fail("actual Request domain pending")
  }
  arena.transfer_domain(domain).managed_capture_stage("original stage 57")
  arena
  .leave_backing_borrow_scope(backing)
  .managed_capture_stage("original stage 58")
  arena
  .return_backing_borrow(backing)
  .managed_capture_stage("original stage 59")
  arena.prepare_domain_read(domain).managed_capture_stage("original stage 60")
  let (physical, initial) = match
    arena
    .prepare_domain_retained_request_execution(domain, input, {
      bootstrap_retained: 1048576L,
      bootstrap_execution: 1048576L,
    })
    .managed_capture_stage("original stage 67") {
    @arena.ReadyRequestExecution(physical, initial) => (physical, initial)
    @arena.PendingRequestExecution(_, _) =>
      fail("actual Request initializer pending")
  }
  (arena, domain, physical, initial)
}

///|
// All child-allocated Program/compiler/Plan/Source aliases leave this frame
// before the physical execution is retired. The existing Run retains cleanup.
fn managed_capture_fixture_work(
  arena : @arena.InstalledArenaHost,
  physical : @arena.InstalledArenaRetainedExecution,
  initial : @resources.BackedPreparationAdmission[Array[Int]],
  input : Array[Int],
  selection : NativeRelationFileSelection,
  declaration : @rows.RowDeclaration,
  provider : @execution.ExecutionCapacity,
  environment : @checked.CheckEnvironment,
  contracts : @local.ClientInstalledSequenceContracts,
  manifests : @publication_host.ClientCompilationManifests,
) -> @local.ClientInstalledManagedRun raise {
  let parent = @local.begin_backed_request_preparation(
    initial,
    input,
    @local.client_local_resource_policy(),
  ).managed_capture_stage("same initial Request inside its caller frame")
  let ledger = arena
    .borrow_domain_retained_execution_ledger(physical)
    .managed_capture_stage("original stage 85")
  let document =
    #|{"version":"actql/0.1","id":"native-file-capture","stages":[{"id":"acquire","inputs":{"remote":{"connector":"native-file-fixture","resource":"records"}},"steps":[{"select":["id","value"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","value"]}}},{"id":"compute","inputs":{"input":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"filter":"value > 0"},{"select":["id","value"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","value"]}}}],"results":{"rows":{"from":{"stage":"compute","result":"rows"}}}}
  let limits = @publication_host.client_standard_program_preparation_limits()
  let source = @local.prepare_request_program_json_preparation(
    parent,
    input,
    document,
    limits.checking.input,
  ).managed_capture_stage("original stage 102")
  let mut ready = false
  for _ in 0..<(document.length() + 1) {
    match
      @local.advance_program_json_preparation(source, 64).managed_capture_stage(
        "original stage 105",
      ) {
      @source.JsonSourceContinue(..) => ()
      @source.JsonSourceReady(_, ..) => {
        ready = true
        break
      }
      @source.JsonSourceFailed(_, ..) => fail("original Source refused")
    }
  }
  assert_true(ready)
  @local.finish_program_json_preparation(source).managed_capture_stage(
    "original stage 115",
  )
  @local.construct_program_json_preparation(source).managed_capture_stage(
    "original stage 116",
  )
  @local.reconcile_program_json_preparation_structure(source).managed_capture_stage(
    "original stage 117",
  )
  let check = @local.prepare_request_program_check_preparation(
    parent,
    input,
    environment,
    None,
    [],
    limits.checking,
  ).managed_capture_stage("original stage 125")
  @local.prepare_program_check_input(check).managed_capture_stage(
    "original stage 126",
  )
  @local.prepare_program_check_prelude(check).managed_capture_stage(
    "original stage 127",
  )
  |> ignore
  @local.prepare_program_check_registry(check).managed_capture_stage(
    "original stage 128",
  )
  |> ignore
  @local.prepare_program_check_contents(check).managed_capture_stage(
    "original stage 129",
  )
  |> ignore
  @local.prepare_program_check_references(check).managed_capture_stage(
    "original stage 130",
  )
  |> ignore
  @local.prepare_program_check_policies(check).managed_capture_stage(
    "original stage 131",
  )
  |> ignore
  @local.prepare_program_check_values(check).managed_capture_stage(
    "original stage 132",
  )
  |> ignore
  @local.prepare_program_check_views(check).managed_capture_stage(
    "original stage 133",
  )
  |> ignore
  @local.prepare_program_check_carriers(check).managed_capture_stage(
    "original stage 134",
  )
  |> ignore
  @local.prepare_program_check_requests(check).managed_capture_stage(
    "original stage 135",
  )
  |> ignore
  @local.reconcile_program_check_requests(check).managed_capture_stage(
    "original stage 136",
  )
  guard @local.finish_program_check_preparation(check).managed_capture_stage(
      "original stage 137",
    )
    is @checked.Checked(_) else {
    fail("whole Source Request must check")
  }
  let prepared = @local.compile_program_check_preparation(check, limits).managed_capture_stage(
    "original stage 141",
  )
  assert_true(
    physical_equal(
      @local.continue_request_program_preparation(parent, input).managed_capture_stage(
        "original stage 144",
      ),
      prepared,
    ),
  )
  @local.reserve_request_program_plan(parent, input).managed_capture_stage(
    "original stage 148",
  )
  // Logical Request identity must survive physical payload retirement. Its
  // immutable CIDs and the later lightweight Run controls belong to the
  // caller's outer lifetime, not to an allocation inside the Source Read.
  arena
  .leave_domain_retained_execution(physical)
  .managed_capture_stage("leave payload before logical identity")
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "native-managed-whole-source",
  ).managed_capture_stage("original stage 153")
  arena
  .enter_domain_retained_execution(physical)
  .managed_capture_stage("same payload after original identity")
  guard @local.select_installed_source_input(prepared, request, 0, 0).managed_capture_stage(
      "original stage 160",
    )
    is @sourceviews.WholeInputRoute(original) else {
    fail("whole Source original missing")
  }
  let file_limits = capture_fixture_limits()
  let selected = @local.prepare_installed_whole_source_capacity(
    prepared,
    original,
    declaration,
    contracts,
    {
      max_rows: 2,
      page: file_limits.page,
      retention: {
        max_nodes: 512,
        max_text_bytes: 8192,
        max_depth: 8,
        max_work: 1000000,
      },
      wire: {
        max_columns: 2,
        max_order_work: 10000,
        max_bytes: 8192,
        max_nodes: 512,
        max_depth: 8,
      },
    },
    Some(provider),
  ).managed_capture_stage("original stage 198")
  let plan = @local.prepare_installed_managed_whole_source_plan(
    prepared,
    request,
    selected,
    8192L,
    8192L,
    contracts,
    capture_fixture_values,
    Some(capture_fixture_fragment),
    None,
    retained_output=true,
    provider_factory=_ => [],
  ).managed_capture_stage("original stage 211")
  @local.prepare_request_capture_module_body(
    parent,
    input,
    plan,
    manifests~,
    // This fixture enters the existing explicit Program checker, rather than
    // the combined computation checker that retains its selected codec getter.
    // Use that checker's original standard explicit compilation profile.
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    provider_factory=_ => [],
  ).managed_capture_stage("original stage 226")
  // The Run's lightweight retirement controls outlive this payload Read.
  // Construct them in the original outer control, under the SAME initial
  // owner/current; then reenter the original payload for actual Source I/O.
  // Retained Program/Plan data remains on this same unfinished domain.
  arena
  .leave_domain_retained_execution(physical)
  .managed_capture_stage("payload leaves before control adoption")
  let owner = @local.begin_request_capture_managed_run(parent, request).managed_capture_stage(
    "original Request adoption in outer control",
  )
  arena
  .enter_domain_retained_execution(physical)
  .managed_capture_stage("original payload reentry after adoption")
  // Runtime constructor workspace starts only AFTER original Request
  // adoption closes its preparation-only inventory. The external fixture
  // selected the original immutable provider quote before entering this Read.
  let inventory = native_relation_file_caller_preparation_inventory(
    selection, file_limits,
  ).managed_capture_stage("Native constructor inventory")
  let bytes = @execution.preparation_representation_cost(inventory).managed_capture_stage(
    "Native constructor cost",
  )
  let caller = @resources.reserve_capacity(ledger, bytes, bytes).managed_capture_stage(
    "Native constructor reservation",
  )
  let (read, _, acquisition, same_selected) = @local.begin_installed_managed_whole_source_read(
    owner, prepared, request, declaration,
  ).managed_capture_stage("original stage 230")
  assert_true(physical_equal(same_selected, selected))
  assert_true(
    @local.installed_whole_source_read_capacity_matches(
      read, selected, acquisition, provider,
    ),
  )
  let foreign_provider = native_relation_file_provider_capacity(
    declaration, selection, file_limits,
  ).managed_capture_stage("original stage 239")
  assert_false(
    @local.installed_whole_source_read_capacity_matches(
      read, selected, acquisition, foreign_provider,
    ),
  )
  let unchanged = @resources.ledger_usage(ledger)
  let refused = prepare_native_managed_relation_file_input_capture(
    arena, physical, declaration, read, selected, foreign_provider, "foreign-provider",
    selection, file_limits,
  )
  guard refused is Err(failure) else {
    fail("copied provider unexpectedly read a file")
  }
  assert_true(failure.issue() is ForeignOriginal)
  assert_true(
    failure
    .retry_cleanup()
    .managed_capture_stage("foreign provider has no child"),
  )
  assert_eq(@resources.ledger_usage(ledger), unchanged)
  let before = unchanged.transferred_bytes
  let capture_owner = capture_fixture_prepared(
    prepare_native_managed_relation_file_input_capture(
      arena, physical, declaration, read, selected, provider, "native-managed-original",
      selection, file_limits,
    ),
    "same Plan file prepare",
  )
  let mut completed = false
  for _ in 0..<10000 {
    if capture_owner.advance(32).managed_capture_stage("original stage 255") {
      completed = true
      break
    }
  }
  assert_true(completed)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes - before, 62L)
  let capture = capture_owner
    .capture()
    .managed_capture_stage("original stage 262")
  let captured = @rows.row_capture_source(capture).managed_capture_stage(
    "original stage 263",
  )
  let original_read = @rows.row_capture_original_read(capture).managed_capture_stage(
    "original stage 264",
  )
  assert_eq(@query.captured_source_row_count(captured), Some(2))
  assert_true(
    @execution.supplied_relation_read_cell(original_read, 0, 0)
    is Some(@admitted.Text("first")),
  )
  assert_true(
    @execution.supplied_relation_read_cell(original_read, 1, 0)
    is Some(@admitted.Text("second")),
  )
  assert_true(
    @execution.supplied_relation_read_cell(original_read, 0, 1)
    is Some(@admitted.Number(1)),
  )
  assert_true(
    @execution.supplied_relation_read_cell(original_read, 1, 1)
    is Some(@admitted.Number(2)),
  )
  let (_, dag, _) = @local.open_installed_managed_capture_host(
    owner,
    prepared,
    request,
    [captured],
  ).managed_capture_stage("original stage 287")
  @rows.check_row_input_compute_binding(capture, dag, 0).managed_capture_stage(
    "original stage 288",
  )
  assert_false(@strategy.captured_task_completed(dag, 0))
  assert_eq(@strategy.next_captured_task(dag), Some(0))
  arena
  .leave_domain_retained_execution(physical)
  .managed_capture_stage("original stage 291")
  assert_true(capture_owner.capture() is Err(Unavailable))
  arena
  .enter_domain_retained_execution(physical)
  .managed_capture_stage("original stage 293")
  assert_true(
    physical_equal(
      ledger,
      arena
      .borrow_domain_retained_execution_ledger(physical)
      .managed_capture_stage("original stage 297"),
    ),
  )
  // This fixture leaves Compute pending, so stop its original DAG before
  // retiring the Source it borrows. Stop is not a physical cleanup ACK.
  @strategy.stop_captured_dag(dag)
  let mut closed = false
  for _ in 0..<10000 {
    match capture_owner.close() {
      Ok(true) => {
        closed = true
        break
      }
      Ok(false) | Err(ManagedRead(@local.Acquisition(@rows.InvalidState))) => ()
      Err(_) => fail("same Plan Source cleanup failed")
    }
  }
  assert_true(closed)
  assert_true(@rows.row_capture_source(capture) is Err(_))
  assert_false(@execution.supplied_relation_read_available(original_read))
  // Source-native cleanup completed in its original entered Read. Final
  // accounting/retirement snapshots belong to the outer cleanup lifetime,
  // so they cannot keep their own retired payload allocation alive.
  arena
  .leave_domain_retained_execution(physical)
  .managed_capture_stage("actual Source Read leaves before parent cleanup")
  @resources.settle_capacity(ledger, caller).managed_capture_stage(
    "original stage 314",
  )
  // The original Run owns physical-parent retirement; logical cleanup
  // cannot claim the Native domain ACK that still belongs to the issuer.
  @local.quiesce_installed_managed_run(owner).managed_capture_stage(
    "all original reads quiescent",
  )
  assert_true(@local.retire_installed_managed_run(owner) is Err(_))
  let retired = @resources.ledger_usage(ledger)
  if retired.live_reservations != 0 {
    fail(
      "logical Run cleanup retains resources: " +
      @debug.to_string(
        (
          retired.live_reservations,
          retired.holdings,
          retired.reserved_retention_bytes,
          retired.reserved_execution_bytes,
        ),
      ),
    )
  }
  assert_true(@local.installed_preparation_payload_severed(owner, request))
  owner
}

///|
test "Native whole Source reader consumes the same Request Plan and physical Ledger" {
  let selection : NativeRelationFileSelection = {
    directory: @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").managed_capture_stage(
      "original stage 333",
    ),
    name: "row-source-input",
    resource: "records",
    items_path: ["items"],
    key_path: None,
    primary_identity: "id",
  }
  // Test-owned fixture setup retains declaration/provider DATA outside the
  // child, like the external directory and input bytes. This is not normal
  // Host first-entry backing or a runtime permission claim.
  let declaration = capture_fixture_declaration()
  let provider = native_relation_file_provider_capacity(
    declaration,
    selection,
    capture_fixture_limits(),
  ).managed_capture_stage("external fixture original provider")
  // Installation contracts and the published environment are retained inputs,
  // prepared once outside the Run's physical payload, as in the normal caller.
  let (wire, cid) = capture_fixture_environment(declaration)
  let environment = @publication_host.admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).managed_capture_stage("original stage 93")
  let contracts = @local.prepare_installed_sequence_contracts(
    capture_fixture_registry,
    capture_fixture_values,
    Some(capture_fixture_fragment),
    None,
  ).managed_capture_stage("original stage 159")
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).managed_capture_stage("original stage 218")
  let input = [1]
  let (arena, domain, physical, initial) = managed_capture_fixture_facility(
    input,
  )
  arena
  .enter_domain_retained_execution(physical)
  .managed_capture_stage("original stage 340")
  let owner = managed_capture_fixture_work(
    arena, physical, initial, input, selection, declaration, provider, environment,
    contracts, manifests,
  )
  match arena.close_domain_retained_execution(physical) {
    Ok(_) => ()
    Err(@arena.Domain(issue)) =>
      fail("Native retirement Domain: " + @debug.to_string(issue))
    Err(@arena.Child(issue)) =>
      fail("Native retirement Child: " + @debug.to_string(issue))
    Err(@arena.Initialization(@bootstrap.Domain(issue))) => {
      let observation = arena
        .observe_domain_retained_execution_cleanup(physical)
        .managed_capture_stage("original Native cleanup observation")
      fail(
        "Native retirement InitializationDomain: " +
        @debug.to_string(issue) +
        " observation=" +
        @debug.to_string(
          (
            observation.users,
            observation.active,
            observation.generic_live_extents,
            observation.managed_live_blocks,
            observation.managed_requested_bytes,
            observation.minimum_managed_request,
            observation.maximum_managed_request,
          ),
        ),
      )
    }
    Err(@arena.Initialization(@bootstrap.Child(issue))) =>
      fail("Native retirement InitializationChild: " + @debug.to_string(issue))
    Err(@arena.Initialization(@bootstrap.Inventory(_))) =>
      fail("Native retirement InitializationInventory")
    Err(@arena.Initialization(@bootstrap.Quiescence(_))) =>
      fail("Native retirement InitializationQuiescence")
  }
  @local.retire_installed_managed_run(owner).managed_capture_stage(
    "original stage 346",
  )
  arena
  .close_domain_after_owner_ack(domain)
  .managed_capture_stage("original stage 347")
  arena.try_close().managed_capture_stage("original stage 348")
}
