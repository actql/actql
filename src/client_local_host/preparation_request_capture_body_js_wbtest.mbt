///|
// The original Source Program/check/compiler, actual nominal Row acquisition
// and shared Compute Plan run on one Request. Empty providers are an explicit
// component port, not a Host/Account/physical Source acceptance claim.
fn request_capture_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
) raise {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let (parent, child, _, input) = registration_parent_fixture(
    current~,
    text=source_query_original_document,
    environment=Some(environment),
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("original captured Source must finish its supported check")
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
  reserve_request_program_plan(parent, input).unwrap()
  (parent, input, prepared)
}

///|
fn request_capture_plan_fixture(
  prepared : @publication_host.PreparedClientProgram,
  factory? : (@execution.ExecutionCapacity) -> Array[@local.ManagedProvider] = _ => {
    []
  },
) -> (
  ClientInstalledManagedCapturePlan,
  @publication_host.ClientRequestIdentity,
) {
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "original-request-capture-plan",
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let requirement = prepare_local_query_requirement(
    prepared,
    0,
    0,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let acquisition = original_row_acquisition_fixture(requirement)
  let capacity = installed_row_capture_capacity(acquisition).unwrap()
  let plan = prepare_installed_managed_capture_plan(
    prepared,
    request,
    [capacity],
    [4096L],
    [2048L],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  (plan, request)
}

///|
fn request_capture_ledger_fixture(
  run : ClientInstalledManagedRun,
  plan : ClientInstalledManagedCapturePlan,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  prepare_installed_managed_run_ledger(
    run,
    plan.prepared,
    plan.request,
    plan.captures,
    plan.transport_bytes,
    plan.transport_execution_bytes,
    plan.installed_contracts,
    plan.values_body,
    plan.fragment_body,
    plan.ordered_body,
  )
}

///|
test "one actual captured Request ledger handoff observes original external current once" {
  let calls = Ref(0)
  let (parent, input, prepared) = request_capture_fixture(current=() => {
    calls.val += 1
    true
  })
  let (plan, request) = request_capture_plan_fixture(prepared)
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  let read = begin_installed_managed_capture_read(run, 0).unwrap()
  let before = calls.val
  let ledger = request_capture_ledger_fixture(run, plan).unwrap()
  let observed = calls.val - before
  assert_true(physical_equal(ledger, parent.ledger))
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(observed, 1)
}

///|
test "captured Request retains original Plan acquisition sequences and manager custody" {
  let factories = Ref(0)
  let (parent, input, prepared) = request_capture_fixture()
  let (plan, request) = request_capture_plan_fixture(prepared, factory=_ => {
    factories.val += 1
    []
  })
  assert_eq(factories.val, 1)
  assert_eq(plan.sequences.length(), 2)
  assert_eq(plan.compute_sequences.length(), 1)
  let acquisition = prepared_installed_managed_capture_acquisition(plan, 0).unwrap()
  assert_true(prepared_installed_managed_capture_acquisition(plan, 1) is None)
  let before = @resources.ledger_usage(parent.ledger)
  complete_request_capture_preparation(parent, input, plan).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  let manager = borrow_request_program_preparation(parent).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(manager).unwrap(),
      prepared,
    ),
  )
  let copied = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "original-request-capture-plan",
  ).unwrap()
  assert_true(
    begin_request_capture_managed_run(parent, copied) is Err(ForeignOriginal),
  )
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  assert_true(
    parent.phase == Selected &&
    parent.input is None &&
    parent.program_captured is None &&
    parent.program_capacity is None,
  )
  assert_true(
    physical_equal(
      installed_managed_capture_plan(run, prepared, request).unwrap(),
      plan,
    ),
  )
  assert_true(
    installed_managed_capture_plan(run, prepared, copied)
    is Err(ForeignOriginal),
  )
  let read = begin_installed_managed_capture_read(run, 0).unwrap()
  assert_true(physical_equal(read.acquisition.unwrap(), acquisition))
  assert_true(
    physical_equal(read.requirement.unwrap(), plan.captures[0].requirement),
  )
  assert_true(begin_installed_managed_capture_read(run, 0) is Err(AlreadyBound))
  assert_true(
    physical_equal(
      request_capture_ledger_fixture(run, plan).unwrap(),
      parent.ledger,
    ),
  )
  assert_true(
    installed_managed_publication_limits(run, prepared, 1000000) is Some(_),
  )
  assert_eq(factories.val, 1)
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  retire_installed_source_read(read).unwrap()
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(run.captured_preparation is None)
  assert_true(@resources.return_preparation_body_borrow(manager).unwrap())
  retire_installed_managed_run(run).unwrap()
  let usage = @resources.ledger_usage(parent.ledger)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.live_reservations, 0)
}

///|
test "captured Request refuses foreign equal input inventory and changed selected Plan DATA" {
  let (parent, input, prepared) = request_capture_fixture()
  let (other, _, foreign) = request_capture_fixture()
  let (plan, request) = request_capture_plan_fixture(prepared)
  let (foreign_plan, _) = request_capture_plan_fixture(foreign)
  let factories = Ref(0)
  assert_true(
    prepare_installed_managed_capture_plan(
      prepared,
      request,
      foreign_plan.captures,
      plan.transport_bytes,
      plan.transport_execution_bytes,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      retained_output=true,
      provider_factory=_ => {
        factories.val += 1
        []
      },
    )
    is Err(ForeignOriginal),
  )
  assert_eq(factories.val, 0)
  assert_true(
    complete_request_capture_preparation(parent, input, foreign_plan)
    is Err(WrongPhase),
  )
  assert_true(parent.program_captured is None && !parent.program_body_attempted)
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  let read = begin_installed_managed_capture_read(run, 0).unwrap()
  assert_true(
    prepare_installed_managed_run_ledger(
      run,
      prepared,
      request,
      foreign_plan.captures,
      plan.transport_bytes,
      plan.transport_execution_bytes,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    prepare_installed_managed_run_ledger(
      run,
      prepared,
      request,
      plan.captures,
      [4097L],
      plan.transport_execution_bytes,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    prepare_installed_managed_run_ledger(
      run,
      prepared,
      request,
      plan.captures,
      plan.transport_bytes,
      plan.transport_execution_bytes,
      foreign_plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    open_installed_managed_capture_host(run, prepared, request, [])
    is Err(Managed(ForeignOriginal)),
  )
  assert_false(run.source_free_opening)
  assert_true(run.source_free_captured is None)
  assert_true(
    physical_equal(
      request_capture_ledger_fixture(run, plan).unwrap(),
      parent.ledger,
    ),
  )
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(run).unwrap()
  abort_request_preparation_after_cleanup(other).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(other.ledger).live_reservations, 0)
}

///|
test "captured Request ledger current reentry cannot return a retired original" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, input, prepared) = request_capture_fixture(current=() => {
    if action.val is Some(run) {
      action.val = None
      run()
    }
    true
  })
  let (plan, request) = request_capture_plan_fixture(prepared)
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  let read = begin_installed_managed_capture_read(run, 0).unwrap()
  action.val = Some(() => {
    retire_installed_source_read(read).unwrap()
    retire_installed_managed_run(run).unwrap()
  })
  assert_true(request_capture_ledger_fixture(run, plan) is Err(_))
  assert_true(run.ledger is None && run.captured_preparation is None)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "captured Request opens its same accounted capture with retained configuration once" {
  let factories = Ref(0)
  let (parent, input, prepared) = request_capture_fixture()
  let (plan, request) = request_capture_plan_fixture(prepared, factory=_ => {
    factories.val += 1
    []
  })
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  let read = begin_installed_managed_capture_read(run, 0).unwrap()
  let ledger = request_capture_ledger_fixture(run, plan).unwrap()
  let acquisition = prepared_installed_managed_capture_acquisition(plan, 0).unwrap()
  let rows = start_installed_source_read_rows(
    read,
    acquisition,
    "same-request-source",
    _ => true,
    4096L,
    2048L,
  ).unwrap()
  @row_source_host.begin_row_run(rows, 2048, 2, 2).unwrap()
  let bytes = @utf8.encode("[{\"id\":3,\"amount\":7}]")
  let charged = @row_source_host.charge_row_run_page(rows, bytes).unwrap()
  assert_eq(
    @row_source_host.accept_charged_row_run_page(rows, charged, bytes).unwrap(),
    1,
  )
  @row_source_host.finish_row_run(rows).unwrap()
  @row_source_host.begin_row_capture(rows).unwrap()
  let mut complete = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(rows, 256).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let capture = @row_source_host.capture_row_run(rows).unwrap()
  let source = @row_source_host.row_capture_source(capture).unwrap()
  let (_, dag, sequences) = open_installed_managed_capture_host(
    run,
    prepared,
    request,
    [source],
  ).unwrap()
  assert_true(physical_equal(@strategy.captured_dag_ledger(dag), ledger))
  assert_true(
    physical_equal(
      installed_managed_publication_dag(run, prepared).unwrap(),
      dag,
    ),
  )
  assert_true(physical_equal(sequences, plan.sequences))
  assert_eq(factories.val, 1)
  assert_true(
    open_installed_managed_capture_host(run, prepared, request, [source])
    is Err(Managed(AlreadyBound)),
  )
  ignore(reject_client_local_run(dag))
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(run).unwrap()
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.live_reservations, 0)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.attempts, 1)
  assert_true(usage.transferred_bytes > 0L)
}

///|
test "captured QueryTime requirement preserves the same invocation original without default substitution" {
  let (parent, input, prepared) = request_capture_fixture()
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_task_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "captured-query-time", "original", "2026-10-29T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let (created, _) = @publication.run_definition_lifetime(definition).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "captured-query-time",
  ).unwrap()
  let original = @publication_host.prepare_client_query_time(
    prepared, request, created,
  ).unwrap()
  @publication_host.bind_client_query_evaluation_time(
    original, prepared, compiled, definition, request,
  ).unwrap()
  |> ignore
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let requirement = prepare_local_query_requirement_at_query_time(
    prepared,
    0,
    0,
    original,
    request,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_true(
    @publication_host.client_query_requirement_matches_original_query_time(
      prepared,
      0,
      0,
      requirement,
      Some(original),
      request,
    ),
  )
  assert_false(
    @publication_host.client_query_requirement_matches_original_query_time(
      prepared,
      0,
      0,
      requirement,
      None,
      request,
    ),
  )
  assert_false(
    @publication_host.client_query_requirement_matches_original_query_time(
      prepared,
      1,
      0,
      requirement,
      Some(original),
      request,
    ),
  )
  let copied = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "captured-query-time",
  ).unwrap()
  assert_false(
    @publication_host.client_query_requirement_matches_original_query_time(
      prepared,
      0,
      0,
      requirement,
      Some(original),
      copied,
    ),
  )
  let other = @publication_host.prepare_client_query_time(
    prepared, request, created,
  ).unwrap()
  @publication_host.bind_client_query_evaluation_time(
    other, prepared, compiled, definition, request,
  ).unwrap()
  |> ignore
  assert_false(
    @publication_host.client_query_requirement_matches_original_query_time(
      prepared,
      0,
      0,
      requirement,
      Some(other),
      request,
    ),
  )
  let capacity = installed_row_capture_capacity(
    original_row_acquisition_fixture(requirement),
  ).unwrap()
  let plan = prepare_installed_managed_capture_plan(
    prepared,
    request,
    [capacity],
    [4096L],
    [2048L],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    query_time=Some(original),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  assert_true(physical_equal(plan._observed_query_time.unwrap(), original))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  ignore(input)
}

///|
test "captured Request retains the same accounted compilation for publication without recompiling" {
  let (parent, input, prepared) = request_capture_fixture()
  let holder = borrow_request_program_plan_input(parent, input).unwrap()
  let (plan, request) = request_capture_plan_fixture(prepared)
  assert_true(plan.compilation is None)
  prepare_request_capture_module_body(
    parent,
    input,
    plan,
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    provider_factory=_ => [],
  ).unwrap()
  let compilation = plan.compilation.unwrap()
  let spent = parent.program_artifact_work_spent
  assert_eq(spent, parent.program_artifact_plan_encoding_nodes.val)
  assert_true(spent > 0L)
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  assert_true(physical_equal(run.captured_preparation.unwrap(), plan))
  for _ in 0..<3 {
    assert_true(
      physical_equal(
        installed_managed_run_compilation_original(run, prepared).unwrap(),
        compilation,
      ),
    )
  }
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(installed_managed_run_compilation_original(run, prepared) is None)
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
