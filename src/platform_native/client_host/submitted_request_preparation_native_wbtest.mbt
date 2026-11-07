///|
fn[T, E] Result::native_request_stage(
  self : Result[T, E],
  stage : String,
) -> T raise {
  match self {
    Ok(value) => value
    Err(_) => fail(stage)
  }
}

///|
fn[T] Option::native_request_stage(self : T?, stage : String) -> T raise {
  match self {
    Some(value) => value
    None => fail(stage)
  }
}

///|
// The actual Native Initialization/Request/Run constructors, with an authored
// finite physical test facility. This is not a normal CLI installation or a
// Journal/Account/publication/FD acknowledgement supplied by a test double.
fn submitted_request_native_work(
  arena : @arena.InstalledArenaHost,
  physical : @arena.InstalledArenaRetainedExecution,
  initial : @resources.BackedPreparationAdmission[@host.ClientSubmittedIntent],
  input : @host.ClientSubmittedIntent,
  expected_rows? : Array[String]? = None,
) -> @local.ClientInstalledManagedRun raise {
  arena
  .enter_domain_retained_execution(physical)
  .native_request_stage("Native Request stage 1")
  let parent = @local.begin_backed_request_preparation(
    initial,
    input,
    @local.client_local_resource_policy(),
  ).native_request_stage("Native Request stage 2")
  let environment = preparation_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).native_request_stage("Native Request stage 3")
  let (preparation, holder) = match
    prepare_native_client_submitted_request(
      parent, input, environment, publication,
    ) {
    Ok(value) => value
    Err(RequestPreparation(_)) => fail("Native Request input preparation")
    Err(Request(Preparation(Capacity(Resource(ExecutionLimit))))) =>
      fail("Native Request capacity ExecutionLimit")
    Err(Request(Preparation(Capacity(Resource(RetentionLimit))))) =>
      fail("Native Request capacity RetentionLimit")
    Err(Request(Preparation(Capacity(_)))) =>
      fail("Native Request capacity other")
    Err(Request(Preparation(ProgramJson(_)))) =>
      fail("Native Request ProgramJson")
    Err(Request(Preparation(ProgramCheck(Capacity(Resource(ExecutionLimit)))))) =>
      fail("Native Request check capacity ExecutionLimit")
    Err(Request(Preparation(ProgramCheck(Capacity(Resource(RetentionLimit)))))) =>
      fail("Native Request check capacity RetentionLimit")
    Err(Request(Preparation(ProgramCheck(Capacity(_))))) =>
      fail("Native Request check capacity other")
    Err(Request(Preparation(ProgramCheck(Check(_))))) =>
      fail("Native Request check construction")
    Err(Request(Preparation(ProgramCheck(Compilation(_))))) =>
      fail("Native Request check compilation")
    Err(Request(Preparation(ProgramCheck(Catalog(_))))) =>
      fail("Native Request check Catalog")
    Err(Request(Preparation(ProgramCheck(Prelude(_))))) =>
      fail("Native Request check Prelude")
    Err(Request(Preparation(ProgramCheck(ChangedInputs)))) =>
      fail("Native Request check ChangedInputs")
    Err(Request(Preparation(ProgramCheck(WrongPhase)))) =>
      fail("Native Request check WrongPhase")
    Err(Request(Preparation(ProgramCheck(_)))) =>
      fail("Native Request ProgramCheck other")
    Err(Request(Preparation(Policy))) => fail("Native Request Policy")
    Err(Request(Preparation(WrongPhase))) => fail("Native Request WrongPhase")
    Err(Request(Preparation(_))) => fail("Native Request other preparation")
    Err(Request(CheckOutcome(_))) => fail("Native Request check outcome")
    Err(Request(_)) => fail("Native Request other terminal")
    Err(_) => fail("Native Request source transport refused")
  }
  guard native_client_submitted_preparation(preparation)
    is Computation(prepared) else {
    fail("original Native Request did not produce Pure computation")
  }
  assert_eq(
    native_client_submitted_preparation_intent_cid(preparation),
    @host.client_submitted_intent_cid(input),
  )
  let assets = @host.client_local_product_assets()
  let contracts = @local.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).native_request_stage("Native Request stage 5")
  let manifests = @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).native_request_stage("Native Request stage 6")
  let limits = @local.request_program_compilation_limits(parent, input).native_request_stage(
    "Native Request stage 7",
  )
  @local.prepare_request_program_module_body(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits=limits,
    retained_output=false,
    provider_factory=_ => [],
  ).native_request_stage("Native Request stage 8")
  let request = @host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "native-backed-original-request",
  ).native_request_stage("Native Request stage 9")
  let run = @local.begin_request_program_managed_run(parent, request).native_request_stage(
    "Native Request stage 10",
  )
  assert_true(
    @local.installed_managed_run_compilation_original(run, prepared) is Some(_),
  )
  let ledger = arena
    .borrow_domain_retained_execution_ledger(physical)
    .native_request_stage("Native Request stage 11")
  let setup = @local.open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      false,
      backing=Some(ledger),
    )
    .native_request_stage("Native Request stage 12")
    .native_request_stage("Native Request stage 13")
  let execution = @local.execute_source_free_local_tasks_guarded(
    setup,
    64,
    1000000,
    () => true,
  ).native_request_stage("Native Request stage 14")
  let rows = execution.rows().native_request_stage("Native Request stage 15")
  match expected_rows {
    Some(expected) => assert_eq(rows, expected)
    None => {
      assert_eq(rows.length(), 104)
      let mut bytes = 0
      for index in 0..<104 {
        let expected = "{\"id\":" +
          index.to_string() +
          ",\"payload\":\"" +
          "a".repeat(1000) +
          "\"}"
        assert_eq(rows[index], expected)
        bytes += @utf8.encode(rows[index]).length()
      }
      assert_true(bytes > 65536)
    }
  }
  let attempts = @resources.ledger_usage(ledger).attempts
  assert_true(execution.close())
  return_native_client_submitted_request_body(holder).native_request_stage(
    "Native Request stage 16",
  )
  |> ignore
  // Core logical cleanup cannot acknowledge the real Native context itself.
  assert_true(@local.retire_installed_managed_run(run) is Err(_))
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(ledger).attempts, attempts)
  arena
  .leave_domain_retained_execution(physical)
  .native_request_stage("Native Request stage 17")
  run
}

///|
test "actual Native Request executes more than100 rows and64KiB on its original backed frame" {
  let rows = []
  for index in 0..<104 {
    rows.push(
      "{\"id\":" +
      index.to_string() +
      ",\"payload\":\"" +
      "a".repeat(1000) +
      "\"}",
    )
  }
  let document = "{\"version\":\"actql/0.1\",\"id\":\"native-backed\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[" +
    rows.join(",") +
    "]},\"as\":\"r\"}],\"results\":{\"rows\":{\"from\":\"r\",\"fields\":[\"id\",\"payload\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"s\",\"result\":\"rows\"}}}}"
  let wire = "{\"kind\":\"program\",\"input\":" +
    document +
    ",\"parameters\":null}"
  // This is already admitted original transport DATA, not a new grant or the
  // CLI's legacy65KiB gate. The Request observes its actual Source geometry.
  let input = @host.prepare_client_submitted_intent(
    wire,
    wire.length() * 3,
    10000,
    64,
  ).native_request_stage("Native Request stage 18")
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
  let run = submitted_request_native_work(arena, physical, initial, input)
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
