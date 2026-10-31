///|
// Existing source-free terminal Serialization purpose, authored independently
// of its compiler output. This fixture opens no provider, Store or public Run.
let request_serialization_document : String =
  #|{"version":"actql/0.1","id":"request-content-compilation","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2},{"id":1}]},"as":"seed"},{"serialize":{"format":"jsonl","fields":["id"],"name":"out.jsonl","preserve_order":true,"bounds":{"max_rows":2,"max_bytes":128}},"as":"attachment"}],"results":{"file":{"from":"attachment","fields":["name","content"]}}}],"results":{"file":{"from":{"stage":"main","result":"file"}}}}

///|
// Real checker/compiler and Local prefix, with an explicit original Resource
// admission. This is not a standard Host, Store or public Content fixture.
fn request_serialization_preparation_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
  ClientInstalledManagedSerializationPreparation,
  @publication_host.ClientRequestIdentity,
) raise {
  let (parent, child, _, input) = registration_parent_fixture(
    text=request_serialization_document,
    current~,
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("authored terminal Serialization check")
  }
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  let holder = borrow_request_content_plan_input(parent, input).unwrap()
  let policy = @publication_host.admit_source_free_result_policy_body(
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563", "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  let component = @publication_host.issue_prepared_client_serialization_plan_graph(
    prepared,
    0,
    1,
    policy,
    2,
    128,
    3,
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let compilation = prepare_request_serialization_compilation(
    parent,
    input,
    component,
    contracts,
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
  ).unwrap()
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "request-serialization", "same-original", "2026-10-31T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "same-request-serialization",
  ).unwrap()
  let (_, execution, measurement) = client_local_execution_limits(max_rows=2)
  let selected = prepare_request_serialization_plan(
    parent,
    input,
    request,
    compiled,
    definition,
    execution,
    measurement,
    None,
  ).unwrap()
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  (parent, input, prepared, selected, request)
}

///|
test "same Request source-free Content adopts one compiler and starts its retained prefix once with one current observation" {
  let calls = Ref(0)
  let during_start : Ref[ClientInstalledManagedRun?] = Ref(None)
  let reentry_fenced = Ref(false)
  let (parent, input, prepared, selected, request) = request_serialization_preparation_fixture(current=() => {
      calls.val += 1
      if during_start.val is Some(run) {
        reentry_fenced.val = retire_installed_managed_run(run)
          is Err(CleanupPending)
      }
      true
    },
  )
  let ledger = parent.ledger
  let spent = parent.program_artifact_work_spent
  assert_true(spent > 0L)
  guard parent.program_compilation is Some(@publication_host.Tasks(compilation)) else {
    fail("retained compiler original")
  }
  assert_true(
    @publication_host.client_compiled_run_matches_tasks(
      selected._observed_compiled,
      prepared,
      compilation,
    ),
  )
  let before = @resources.ledger_usage(ledger)
  complete_request_serialization_preparation(parent, input, selected).unwrap()
  let run = begin_request_content_managed_run(parent, request).unwrap()
  assert_true(run.ledger is Some(original) && physical_equal(original, ledger))
  assert_true(
    run.content is SerializationContent(original) &&
    physical_equal(original, selected),
  )
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts)
  let observed = calls.val
  during_start.val = Some(run)
  let prefix = start_installed_managed_serialization_prefix(
    run, prepared, selected,
  ).unwrap()
  during_start.val = None
  assert_eq(calls.val, observed + 1)
  assert_true(reentry_fenced.val)
  assert_true(physical_equal(prefix.ledger, ledger))
  assert_true(
    run.serialization_prefix is Some(original) &&
    physical_equal(original, prefix),
  )
  let after_start = @resources.ledger_usage(ledger)
  assert_true(
    start_installed_managed_serialization_prefix(run, prepared, selected)
    is Err(AlreadyBound),
  )
  assert_eq(calls.val, observed + 1)
  assert_eq(@resources.ledger_usage(ledger), after_start)
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  let mut output : @execution.CompletedOutput? = None
  let mut polls = 0
  while output is None && polls < 1000 {
    polls += 1
    match advance_client_serialization_prefix(prefix, 1).unwrap() {
      @local.Complete(value, ..) => output = Some(value)
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ => fail("original source-free prefix did not complete")
    }
  }
  let output = output.unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 10000, 1000, 100).unwrap(),
    "{\"id\":2}",
  )
  assert_eq(
    @execution.completed_output_row_wire(output, 1, 10000, 1000, 100).unwrap(),
    "{\"id\":1}",
  )
  assert_true(client_serialization_prefix_work(prefix).unwrap() > 0L)
  assert_true(
    cleanup_installed_managed_serialization_prefix(run, selected).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  let retired = @resources.ledger_usage(ledger)
  assert_eq(retired.live_reservations, 0)
  assert_eq(retired.reserved_retention_bytes, 0L)
  assert_eq(retired.reserved_execution_bytes, 0L)
  assert_eq(retired.attempts, after_start.attempts)
  assert_true(
    start_installed_managed_serialization_prefix(run, prepared, selected)
    is Err(ForeignOriginal),
  )
}

///|
test "source-free Content refuses changed originals and retains an unreturned or pending prefix until its actual ACK" {
  let (parent, input, prepared, selected, request) = request_serialization_preparation_fixture()
  let changed = {
    ..selected,
    request: @publication_host.prepare_source_free_client_request_identity(
      prepared,
      "sha256:" + "a".repeat(64),
      "other-request",
    ).unwrap(),
  }
  let before = request_preparation_accounting(parent)
  assert_true(
    complete_request_serialization_preparation(parent, input, changed)
    is Err(ForeignOriginal),
  )
  assert_eq(request_preparation_accounting(parent), before)
  complete_request_serialization_preparation(parent, input, selected).unwrap()
  let run = begin_request_content_managed_run(parent, request).unwrap()
  assert_true(
    start_installed_managed_serialization_prefix(run, prepared, changed)
    is Err(ForeignOriginal),
  )
  // An unreturned constructor has no physical stop proof. Keep its original
  // reservation and block Run retirement until the SAME child actually ACKs.
  let reservation = @resources.reserve_attempt(parent.ledger, 0L, 7L, 5L).unwrap()
  let prefix : ClientSerializationPrefix = {
    child: None,
    ledger: parent.ledger,
    reservation,
    child_cleaned: false,
    released: false,
  }
  run.serialization_prefix = Some(prefix)
  assert_false(
    cleanup_installed_managed_serialization_prefix(run, selected).unwrap(),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.reservation_open(reservation))
  let closes = Ref(0)
  prefix.child = Some(
    @local.managed_provider_execution(
      _ => Ok(@local.managed_provider_continue(1L, 1L)),
      () => true,
      () => true,
      () => {
        closes.val += 1
        Ok(closes.val > 1)
      },
    ),
  )
  assert_false(
    cleanup_installed_managed_serialization_prefix(run, selected).unwrap(),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(
    cleanup_installed_managed_serialization_prefix(run, selected).unwrap(),
  )
  assert_eq(closes.val, 2)
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "source-free Serialization compilation remains on original Request capacity and compiler output" {
  let (parent, child, _, input) = registration_parent_fixture(
    text=request_serialization_document,
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("authored source-free Serialization check")
  }
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  let holder = borrow_request_content_plan_input(parent, input).unwrap()
  let policy = @publication_host.admit_source_free_result_policy_body(
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563", "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  let component = @publication_host.issue_prepared_client_serialization_plan_graph(
    prepared,
    0,
    1,
    policy,
    2,
    128,
    3,
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let ledger = parent.ledger
  let capacity = parent.program_capacity.unwrap()
  let compilation = prepare_request_serialization_compilation(
    parent,
    input,
    component,
    contracts,
    manifests~,
    compilation_limits~,
  ).unwrap()
  assert_true(physical_equal(parent.ledger, ledger))
  assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
  guard parent.program_compilation is Some(@publication_host.Tasks(original)) else {
    fail("same retained Serialization TaskCompilation")
  }
  assert_true(physical_equal(original, compilation))
  assert_true(
    physical_equal(
      @publication_host.client_task_compilation_serialization(compilation).unwrap(),
      component,
    ),
  )
  assert_true(parent.phase == ContentPlanReserved)
  assert_true(parent.program_artifact_work_spent > 0L)
  let spent = parent.program_artifact_work_spent
  assert_true(
    prepare_request_serialization_compilation(
      parent,
      input,
      component,
      contracts,
      manifests~,
      compilation_limits~,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}
