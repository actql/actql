///|
// The ordinary CLI JSON spelling captures the whole document as ONE Text value.
// Its structural node inventory belongs to the document, not that outer Text.
// This is the actual Native Request/frame/Run execution component, not Journal,
// ordinary installed packaging, physical FD or separate-process Saved evidence.
test "Native JSON Source Request keeps document nodes separate from capture nodes" {
  let wire = "{\"kind\":\"aql\",\"input\":{\"text\":\"{\\\"version\\\":\\\"actql/0.1\\\",\\\"id\\\":\\\"native-request-ordinary\\\",\\\"stages\\\":[{\\\"id\\\":\\\"main\\\",\\\"inputs\\\":{},\\\"steps\\\":[{\\\"values\\\":{\\\"schema\\\":{\\\"id\\\":{\\\"type\\\":\\\"number\\\",\\\"nullable\\\":false}},\\\"rows\\\":[{\\\"id\\\":311},{\\\"id\\\":312}]},\\\"as\\\":\\\"original\\\"},{\\\"from\\\":\\\"original\\\",\\\"filter\\\":\\\"id > 300\\\",\\\"as\\\":\\\"filtered\\\"},{\\\"from\\\":\\\"filtered\\\",\\\"select\\\":[\\\"id\\\"],\\\"as\\\":\\\"selected\\\"}],\\\"results\\\":{\\\"rows\\\":{\\\"from\\\":\\\"selected\\\",\\\"fields\\\":[\\\"id\\\"]}}}],\\\"results\\\":{\\\"answer\\\":{\\\"from\\\":{\\\"stage\\\":\\\"main\\\",\\\"result\\\":\\\"rows\\\"}}}}\",\"format\":\"json\"},\"parameters\":null}"
  let input = @host.prepare_client_submitted_intent(wire, 65536, 8192, 64).native_request_stage(
    "authored Source intent",
  )
  // Match the SAME existing ordinary policy, rather than the first authored
  // 32MiB component facility that correctly refused its full checker peak.
  let policy = @local.client_local_preparation_initial_limits(
    @local.client_local_resource_policy(),
  ).native_request_stage("ordinary native Request policy")
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
  ).native_request_stage("Native Request stage 19")
  arena.acquire().native_request_stage("Native Request stage 20")
  let backing = arena
    .borrow_backing()
    .native_request_stage("Native Request stage 21")
  arena
  .enter_backing_borrow_scope(backing)
  .native_request_stage("Native Request stage 22")
  let domain = match
    arena
    .prepare_domain_in_process(backing, domain_bytes, policy)
    .native_request_stage("Native Request stage 23") {
    @arena.PreparedDomain(value) => value
    @arena.PendingDomain(_, _) => fail("actual Request domain pending")
  }
  arena.transfer_domain(domain).native_request_stage("Native Request stage 24")
  arena
  .leave_backing_borrow_scope(backing)
  .native_request_stage("Native Request stage 25")
  arena
  .return_backing_borrow(backing)
  .native_request_stage("Native Request stage 26")
  arena
  .prepare_domain_read(domain)
  .native_request_stage("Native Request stage 27")
  let (physical, initial) = match
    arena
    .prepare_domain_retained_request_execution(domain, input, {
      bootstrap_retained: 1048576L,
      bootstrap_execution: 1048576L,
    })
    .native_request_stage("Native Request stage 28") {
    @arena.ReadyRequestExecution(physical, initial) => (physical, initial)
    @arena.PendingRequestExecution(_, _) =>
      fail("actual Request initializer pending")
  }
  let run = submitted_request_native_work(
    arena,
    physical,
    initial,
    input,
    expected_rows=Some(["{\"id\":311}", "{\"id\":312}"]),
  )
  arena
  .close_domain_retained_execution(physical)
  .native_request_stage("Native Request stage 29")
  @local.retire_installed_managed_run(run).native_request_stage(
    "Native Request stage 30",
  )
  arena
  .close_domain_after_owner_ack(domain)
  .native_request_stage("Native Request stage 31")
  arena.try_close().native_request_stage("Native Request stage 32")
}

///|
// Actual original Native frame/Request/semantic/static compiler and two-stage
// retirement, no Journal/admission/Run/provider/Saved or installed proof.
test "Native static raw Request keeps compiler and original physical retirement" {
  let input = "{\"version\":\"actql/0.1\",\"id\":\"static-native-original\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2}]},\"as\":\"r\"}],\"results\":{\"out\":{\"from\":\"r\",\"fields\":[\"id\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"s\",\"result\":\"out\"}}}}"
  // Match the SAME existing ordinary policy, rather than the first authored
  // 32MiB component facility that correctly refused its full checker peak.
  let policy = @local.client_local_preparation_initial_limits(
    @local.client_local_resource_policy(),
  ).native_request_stage("ordinary native Request policy")
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
  ).native_request_stage("Native Request stage 19")
  arena.acquire().native_request_stage("Native Request stage 20")
  let backing = arena
    .borrow_backing()
    .native_request_stage("Native Request stage 21")
  arena
  .enter_backing_borrow_scope(backing)
  .native_request_stage("Native Request stage 22")
  let domain = match
    arena
    .prepare_domain_in_process(backing, domain_bytes, policy)
    .native_request_stage("Native Request stage 23") {
    @arena.PreparedDomain(value) => value
    @arena.PendingDomain(_, _) => fail("actual Request domain pending")
  }
  arena.transfer_domain(domain).native_request_stage("Native Request stage 24")
  arena
  .leave_backing_borrow_scope(backing)
  .native_request_stage("Native Request stage 25")
  arena
  .return_backing_borrow(backing)
  .native_request_stage("Native Request stage 26")
  arena
  .prepare_domain_read(domain)
  .native_request_stage("Native Request stage 27")
  let (physical, initial) = match
    arena
    .prepare_domain_retained_request_execution(domain, input, {
      bootstrap_retained: 1048576L,
      bootstrap_execution: 1048576L,
    })
    .native_request_stage("Native Request stage 28") {
    @arena.ReadyRequestExecution(physical, initial) => (physical, initial)
    @arena.PendingRequestExecution(_, _) =>
      fail("actual Request initializer pending")
  }

  arena
  .enter_domain_retained_execution(physical)
  .native_request_stage("Static Native original stage 1")
  let parent = @local.begin_backed_request_preparation(
    initial,
    input,
    @local.client_local_resource_policy(),
  ).native_request_stage("Static Native original stage 2")
  let environment = preparation_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).native_request_stage("Static Native original stage 3")
  let checked = @local.prepare_request_native_document_check(
    parent,
    input,
    input,
    @frontend.Json,
    Some(" ".repeat(70000) + "{}"),
    None,
    environment,
    publication,
    static_check=false,
  )
  match checked {
    Err(@local.CheckOutcome(@checked.Rejected(diagnostic))) =>
      fail(
        "Static original check verdict: " +
        @debug.to_string(@checked.diagnostic_category(diagnostic)),
      )
    Err(@local.Preparation(issue)) =>
      fail("Static original preparation: " + @debug.to_string(issue))
    _ => ()
  }
  checked.native_request_stage("Static Native original stage 4")
  let manifests = @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).native_request_stage("Static Native original stage 5")
  let mut view : String? = Some(
    @local.request_native_static_plan_view(
      parent, input, environment, publication, manifests,
    ).native_request_stage("Static Native original stage 6"),
  )
  assert_true(view.unwrap().contains("actql-plan-view/0.1"))
  // The ordinary command copies its reply to original command control before
  // cutting this payload alias. This component consumes then drops its view.
  view = None
  // Logical payload cleanup cannot acknowledge this still-live Native frame.
  assert_true(@local.abort_request_preparation_after_cleanup(parent) is Err(_))
  arena
  .leave_domain_retained_execution(physical)
  .native_request_stage("Static Native original stage 7")
  arena
  .close_domain_retained_execution(physical)
  .native_request_stage("Static Native original stage 8")
  @local.abort_request_preparation_after_cleanup(parent).native_request_stage(
    "Static Native original stage 9",
  )
  arena
  .close_domain_after_owner_ack(domain)
  .native_request_stage("Static Native original stage 10")
  arena.try_close().native_request_stage("Static Native original stage 11")
}

///|
// Exact public numeric Program DATA, tested through the existing Native
// Request/Source/managed-Run component. No Journal, installed ABI, durable Run,
// first public close or separate-process Saved acceptance is inferred.
test "Native default JSON Source prepares100000 rows under an explicit finite Host policy" {
  let rows = []
  for index in 0..<100000 {
    rows.push("{\"v0\":" + index.to_string() + "}")
  }
  let document = "{\"version\":\"actql/0.1\",\"id\":\"numeric-scale\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"v\",\"values\":{\"schema\":{\"v0\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
    rows.join(",") +
    "]}}],\"results\":{\"rows\":{\"from\":\"v\",\"fields\":[\"v0\"]}}}],\"results\":{\"answer0\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  assert_true(document.length() > 1048576)
  let writer = @encode.writer(document.length() * 6 + 1024, 4, 2)
  @encode.string_value(writer, document)
  let wire = "{\"kind\":\"aql\",\"input\":{\"text\":" +
    @encode.finish(writer) +
    ",\"format\":\"json\"},\"parameters\":null}"
  let input = @host.prepare_client_submitted_intent(
    wire,
    wire.length() * 3,
    8192,
    64,
  ).native_request_stage("original100k Source intent")
  // Match the SAME existing ordinary policy, rather than the first authored
  // 32MiB component facility that correctly refused its full checker peak.
  let policy = @local.client_local_preparation_initial_limits(
    @local.client_local_resource_policy(),
  ).native_request_stage("ordinary native Request policy")
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
  ).native_request_stage("Native Request stage 19")
  arena.acquire().native_request_stage("Native Request stage 20")
  let backing = arena
    .borrow_backing()
    .native_request_stage("Native Request stage 21")
  arena
  .enter_backing_borrow_scope(backing)
  .native_request_stage("Native Request stage 22")
  let domain = match
    arena
    .prepare_domain_in_process(backing, domain_bytes, policy)
    .native_request_stage("Native Request stage 23") {
    @arena.PreparedDomain(value) => value
    @arena.PendingDomain(_, _) => fail("actual Request domain pending")
  }
  arena.transfer_domain(domain).native_request_stage("Native Request stage 24")
  arena
  .leave_backing_borrow_scope(backing)
  .native_request_stage("Native Request stage 25")
  arena
  .return_backing_borrow(backing)
  .native_request_stage("Native Request stage 26")
  arena
  .prepare_domain_read(domain)
  .native_request_stage("Native Request stage 27")
  let (physical, initial) = match
    arena
    .prepare_domain_retained_request_execution(domain, input, {
      bootstrap_retained: 1048576L,
      bootstrap_execution: 1048576L,
    })
    .native_request_stage("Native Request stage 28") {
    @arena.ReadyRequestExecution(physical, initial) => (physical, initial)
    @arena.PendingRequestExecution(_, _) =>
      fail("actual Request initializer pending")
  }
  let run = submitted_request_native_work(
    arena,
    physical,
    initial,
    input,
    expected_rows=Some(rows),
    selected_environment=Some(native_numeric_operator_environment()),
  )
  arena
  .close_domain_retained_execution(physical)
  .native_request_stage("Native Request stage 29")
  @local.retire_installed_managed_run(run).native_request_stage(
    "Native Request stage 30",
  )
  arena
  .close_domain_after_owner_ack(domain)
  .native_request_stage("Native Request stage 31")
  arena.try_close().native_request_stage("Native Request stage 32")
}

///|
// Operator-selected checking DATA only. These finite capacities do not change
// packaged defaults, grant execution, or supply the actual parent backing.
fn native_numeric_operator_environment() -> @checked.CheckEnvironment {
  @host.admit_client_check_environment(
    "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],\"evidence_bundle_cid\":\"sha256:3c8dcc4906651fdf61107b90e25cc5207093b2655d38d5b448d7937951266396\",\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1000,\"max_artifact_bytes\":16777216,\"max_artifact_rows\":100000,\"max_effect_items\":1000,\"max_graph_input_edges\":1000,\"max_graph_input_nodes\":1000,\"max_graph_output_rows\":1000,\"max_graph_paths\":1000,\"max_infer_items\":1000,\"max_model_input_tokens_per_item\":1000,\"max_model_request_bytes_per_item\":1000,\"max_model_total_duration_ms\":1000,\"max_nested_value_bytes\":1000,\"max_nested_value_depth\":1000,\"max_relation_output_rows\":100000,\"max_temporal_matches_per_key\":1000,\"max_temporal_output_rows\":1000,\"version\":\"actql-capacity-host-policy/0.1\"}},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}",
    "sha256:3c8dcc4906651fdf61107b90e25cc5207093b2655d38d5b448d7937951266396",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
// Same installed Native submitted-Source caller, original physical frame and
// retirement; no packaged installation, Journal or Saved acceptance.
test "Native ordinary Source shares retained lexical work and original result convention" {
  let document = "SELECT 7 AS n" + " ".repeat(1000000)
  let writer = @encode.writer(document.length() * 3 + 128, 4, 2)
  @encode.string_value(writer, document)
  let wire = "{\"kind\":\"aql\",\"input\":{\"text\":" +
    @encode.finish(writer) +
    ",\"format\":\"sql\"},\"parameters\":null}"
  let input = @host.prepare_client_submitted_intent(
    wire,
    wire.length() * 3,
    8192,
    64,
  ).native_request_stage("authored retained lexical Source intent")
  // Match the SAME existing ordinary policy, rather than the first authored
  // 32MiB component facility that correctly refused its full checker peak.
  let policy = @local.client_local_preparation_initial_limits(
    @local.client_local_resource_policy(),
  ).native_request_stage("ordinary native Request policy")
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
  ).native_request_stage("Native Request stage 19")
  arena.acquire().native_request_stage("Native Request stage 20")
  let backing = arena
    .borrow_backing()
    .native_request_stage("Native Request stage 21")
  arena
  .enter_backing_borrow_scope(backing)
  .native_request_stage("Native Request stage 22")
  let domain = match
    arena
    .prepare_domain_in_process(backing, domain_bytes, policy)
    .native_request_stage("Native Request stage 23") {
    @arena.PreparedDomain(value) => value
    @arena.PendingDomain(_, _) => fail("actual Request domain pending")
  }
  arena.transfer_domain(domain).native_request_stage("Native Request stage 24")
  arena
  .leave_backing_borrow_scope(backing)
  .native_request_stage("Native Request stage 25")
  arena
  .return_backing_borrow(backing)
  .native_request_stage("Native Request stage 26")
  arena
  .prepare_domain_read(domain)
  .native_request_stage("Native Request stage 27")
  let (physical, initial) = match
    arena
    .prepare_domain_retained_request_execution(domain, input, {
      bootstrap_retained: 1048576L,
      bootstrap_execution: 1048576L,
    })
    .native_request_stage("Native Request stage 28") {
    @arena.ReadyRequestExecution(physical, initial) => (physical, initial)
    @arena.PendingRequestExecution(_, _) =>
      fail("actual Request initializer pending")
  }
  let run = submitted_request_native_work(
    arena,
    physical,
    initial,
    input,
    expected_rows=Some(["{\"n\":7}"]),
  )
  arena
  .close_domain_retained_execution(physical)
  .native_request_stage("Native Request stage 29")
  @local.retire_installed_managed_run(run).native_request_stage(
    "Native Request stage 30",
  )
  arena
  .close_domain_after_owner_ack(domain)
  .native_request_stage("Native Request stage 31")
  arena.try_close().native_request_stage("Native Request stage 32")
}

///|
// Same original retained Native Request/frame and real static checker.
// No submitted business Run, Journal, normal package or Saved acceptance.
test "Native static direct11 checks its same raw Request without compiling" {
  let input = "SELECT 0 AS n" +
    Array::makei(10, i => " UNION ALL SELECT " + (i + 1).to_string() + " AS n").join(
      "",
    )
  // Match the SAME existing ordinary policy, rather than the first authored
  // 32MiB component facility that correctly refused its full checker peak.
  let policy = @local.client_local_preparation_initial_limits(
    @local.client_local_resource_policy(),
  ).native_request_stage("ordinary native Request policy")
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
  ).native_request_stage("Native Request stage 19")
  arena.acquire().native_request_stage("Native Request stage 20")
  let backing = arena
    .borrow_backing()
    .native_request_stage("Native Request stage 21")
  arena
  .enter_backing_borrow_scope(backing)
  .native_request_stage("Native Request stage 22")
  let domain = match
    arena
    .prepare_domain_in_process(backing, domain_bytes, policy)
    .native_request_stage("Native Request stage 23") {
    @arena.PreparedDomain(value) => value
    @arena.PendingDomain(_, _) => fail("actual Request domain pending")
  }
  arena.transfer_domain(domain).native_request_stage("Native Request stage 24")
  arena
  .leave_backing_borrow_scope(backing)
  .native_request_stage("Native Request stage 25")
  arena
  .return_backing_borrow(backing)
  .native_request_stage("Native Request stage 26")
  arena
  .prepare_domain_read(domain)
  .native_request_stage("Native Request stage 27")
  let (physical, initial) = match
    arena
    .prepare_domain_retained_request_execution(domain, input, {
      bootstrap_retained: 1048576L,
      bootstrap_execution: 1048576L,
    })
    .native_request_stage("Native Request stage 28") {
    @arena.ReadyRequestExecution(physical, initial) => (physical, initial)
    @arena.PendingRequestExecution(_, _) =>
      fail("actual Request initializer pending")
  }

  arena
  .enter_domain_retained_execution(physical)
  .native_request_stage("Static Native original stage 1")
  let parent = @local.begin_backed_request_preparation(
    initial,
    input,
    @local.client_local_resource_policy(),
  ).native_request_stage("Static Native original stage 2")
  let environment = preparation_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).native_request_stage("Static Native original stage 3")
  // This is the ordinary static RAW-document entrance. No submitted intent,
  // captured Snapshot or business Run is prepared by this case.
  @local.reserve_request_native_intake_wire(parent, input, input.length()).native_request_stage(
    "Static Native original raw intake",
  )
  let checked = @local.prepare_request_native_document_check(
    parent,
    input,
    input,
    @frontend.Sql,
    None,
    None,
    environment,
    publication,
  )
  match checked {
    Err(@local.CheckOutcome(@checked.Rejected(diagnostic))) =>
      fail(
        "Static original check verdict: " +
        @debug.to_string(@checked.diagnostic_category(diagnostic)),
      )
    Err(@local.Preparation(issue)) =>
      fail("Static original preparation: " + @debug.to_string(issue))
    _ => ()
  }
  checked.native_request_stage("Static Native original stage 4")
  assert_eq(@local.request_preparation_work_calls(parent), (1L, 1L, 1L, 0L))
  // Logical payload cleanup cannot acknowledge this still-live Native frame.
  assert_true(@local.abort_request_preparation_after_cleanup(parent) is Err(_))
  arena
  .leave_domain_retained_execution(physical)
  .native_request_stage("Static Native original stage 7")
  arena
  .close_domain_retained_execution(physical)
  .native_request_stage("Static Native original stage 8")
  @local.abort_request_preparation_after_cleanup(parent).native_request_stage(
    "Static Native original stage 9",
  )
  assert_eq(@local.request_preparation_work_calls(parent), (1L, 1L, 1L, 0L))
  arena
  .close_domain_after_owner_ack(domain)
  .native_request_stage("Static Native original stage 10")
  arena.try_close().native_request_stage("Static Native original stage 11")
}
