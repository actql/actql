///|
// Actual original Node Resource and managed Run; prepared input/module setup
// is explicit fixture backing, not an ordinary Host or physical admission.
fn managed_publication_duplicate_fixture(
  prepared : @publication_host.PreparedClientProgram,
) -> ClientInstalledManagedRun {
  let input = [1]
  let initial = request_parent_fixture(input)
  let ledger = @resources.start_node_preparation_admission(initial).unwrap()
  let capacity : @resources.PreparationCapacity[
    Array[Int],
    @publication_host.PreparedClientProgram,
  ] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    1000000L,
    0L,
    max_borrowers=3,
  ).unwrap()
  let plan = request_program_installed_plan(prepared)
  @resources.complete_preparation_capacity(
    capacity, input, prepared, 1000000L, 0L,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "used-publication-slot",
  ).unwrap()
  let run = begin_preparation_owned_installed_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  run.publication_started = true
  run
}

///|
fn managed_publication_actual_compilation(
  prepared : @publication_host.PreparedClientProgram,
) -> (@publication_host.ClientCompiledRun, @publication.PublicationContract) {
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_values_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    1000,
    65536,
    8192,
    64,
  ).unwrap()
  let compiled = @publication_host.issue_client_values_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "managed-publication", "original-run", "2026-10-29T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  (compiled, definition)
}

///|
test "managed Run publication uses the actual generic Request Plan and original Run body role" {
  let text =
    #|{"version":"actql/0.1","id":"managed-publication","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"v"}],"results":{"rows":{"from":"v","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let current = Ref(0)
  let (parent, _, _, input) = registration_parent_fixture(
    text~,
    current=() => {
      current.val += 1
      true
    },
    computation_limits=Some(
      (
        @publication_host.client_standard_program_preparation_limits(),
        @publication_host.client_standard_effect_computation_limits(),
      ),
    ),
  )
  finish_request_computation_preparation(parent, input).unwrap()
  let prepared = parent.compiled_program.unwrap()
  reserve_request_program_plan(parent, input).unwrap()
  let plan = request_program_installed_plan(prepared)
  complete_request_program_preparation(parent, input, plan).unwrap()
  let manager = borrow_request_program_preparation(parent).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "managed-original",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  let (compiled, definition) = managed_publication_actual_compilation(prepared)
  let before = current.val
  let (_, invocation) = issue_program_publication_invocation(
    run, prepared, compiled, definition, "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
    65536, 8192, 64,
  ).unwrap()
  assert_eq(current.val, before)
  assert_true(physical_equal(run.publication_definition.unwrap(), definition))
  assert_true(physical_equal(run.publication_invocation.unwrap(), invocation))
  assert_true(
    issue_program_publication_invocation(
      run, prepared, compiled, definition, "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
      65536, 8192, 64,
    )
    is Err(WrongPhase),
  )
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      true,
    )
    .unwrap()
    .unwrap()
  let execution = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
    true
  }).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":1}"])
  assert_true(execution.close())
  let publication = reserve_program_publication(run, prepared).unwrap()
  assert_true(physical_equal(run.publication.unwrap(), publication))
  let role = managed_run_publication_body(run, prepared).unwrap()
  assert_true(physical_equal(publication.holder, role))
  assert_false(physical_equal(publication.holder, manager))
  assert_true(reserve_program_publication(run, prepared) is Err(WrongPhase))
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(publication.original is None && publication.retiring)
  assert_true(
    run.publication is None &&
    run.publication_definition is None &&
    run.publication_invocation is None,
  )
  assert_true(@resources.return_preparation_body_borrow(manager).unwrap())
  retire_installed_managed_run(run).unwrap()
  let usage = @resources.ledger_usage(parent.ledger)
  assert_eq(usage.live_reservations, 0)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.attempts, 1)
}

///|
// Distinct actual two-Stage Tasks compilation. The retained original artifact
// supplies its semantic issuer; no Values fallback or second compiler runs.
test "managed source-free Tasks bind original invocation before execution and publication reservation" {
  let text =
    #|{"version":"actql/0.1","id":"managed-tasks-publication","stages":[{"id":"first","inputs":{},"steps":[{"as":"v","values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":7}]}}],"results":{"rows":{"from":"v","fields":["id"]}}},{"id":"second","inputs":{"x":{"result":{"stage":"first","result":"rows"}}},"steps":[{"as":"out","select":["id"]}],"results":{"rows":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"second","result":"rows"}}}}
  let (parent, child, _, input) = registration_parent_fixture(text~)
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("original Tasks Program must check")
  }
  let compiled_prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let prepared = continue_request_program_preparation(parent, input).unwrap()
  assert_true(physical_equal(prepared, compiled_prepared))
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let plan = parent.program_source_free.unwrap()
  guard plan.compilation is Some(@publication_host.Tasks(artifact)) else {
    fail("the actual installed Plan must retain Tasks compilation")
  }
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    artifact,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "managed-tasks", "original-tasks", "2026-10-30T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "original-tasks",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  let (_, invocation) = issue_program_publication_invocation(
    run, prepared, compiled, definition, "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
    65536, 8192, 64,
  ).unwrap()
  assert_true(physical_equal(run.publication_definition.unwrap(), definition))
  assert_true(physical_equal(run.publication_invocation.unwrap(), invocation))
  assert_true(
    issue_program_publication_invocation(
      run, prepared, compiled, definition, "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
      65536, 8192, 64,
    )
    is Err(WrongPhase),
  )
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      true,
    )
    .unwrap()
    .unwrap()
  let execution = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
    true
  }).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":7}"])
  assert_true(execution.close())
  let publication = reserve_program_publication(run, prepared).unwrap()
  assert_true(physical_equal(run.publication.unwrap(), publication))
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
