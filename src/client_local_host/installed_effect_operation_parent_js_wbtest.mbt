///|
// Existing ordinary managed Root with explicit no-I/O current/cleanup ports.
// This is a source-component connection, not an installed artifact, physical
// backing, Account/Effect grant or successful provider operation.
extern "js" fn effect_parent_test_original(
  loader : PublicationTestLoader,
  plan : ClientInstalledEffectManagedPlan,
  quote : Array[Int64],
  current : () -> Unit,
) -> @resources.OriginalNodeManagedRunReference =
  #|(loader,plan,quote,current) => loader('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs').retainOrdinaryManagedRun(plan,{planningWork:Number(quote[0]),attempts:Number(quote[1]),holdings:Number(quote[2]),transferBytes:quote[3],retainedBytes:quote[4],executionBytes:quote[5]},current,()=>false)

///|
fn effect_parent_test_admission(
  plan : ClientInstalledEffectManagedPlan,
  quote : Array[Int64],
  current? : () -> Unit = () => (),
) -> @resources.NodeManagedRunAdmission[ClientInstalledEffectManagedPlan] {
  let original = effect_parent_test_original(
    publication_test_loader(publication_test_url()),
    plan,
    quote,
    current,
  )
  @resources.prepare_node_managed_run_admission(original, plan).unwrap()
}

///|
test "actual managed supplier binds one original Effect plan and same Ledger through prepare and retirement" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let admission = effect_parent_test_admission(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let run = begin_prepared_installed_effect_managed_run(
    admission, prepared, request, plan,
  ).unwrap()
  assert_true(
    physical_equal(installed_effect_managed_operation_plan(run).unwrap(), plan),
  )
  let ledger = prepare_installed_effect_managed_run_ledger(
    run,
    prepared,
    request,
    [],
    [],
    [],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_eq(@resources.ledger_limits(ledger), plan.limits)
  let copied_request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "effect-operation-plan",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  assert_true(copied_request == request)
  assert_true(
    check_installed_effect_managed_run(run, prepared, copied_request)
    is Err(ForeignOriginal),
  )
  assert_true(
    prepare_installed_effect_managed_run_ledger(
      run,
      prepared,
      copied_request,
      [],
      [],
      [],
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is Err(ForeignOriginal),
  )
  let foreign_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_true(
    prepare_installed_effect_managed_run_ledger(
      run,
      prepared,
      request,
      [],
      [],
      [],
      foreign_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    physical_equal(
      prepare_installed_effect_managed_run_ledger(
        run,
        prepared,
        request,
        [],
        [],
        [],
        contracts,
        source_query_original_values,
        Some(source_query_original_fragment),
        None,
      ).unwrap(),
      ledger,
    ),
  )
  retire_installed_managed_run(run).unwrap()
  assert_true(run.preparation is None)
  assert_true(require_installed_managed_run(run) is Err(Retired))
  assert_true(@resources.cleanup_node_managed_run_admission(admission) is Ok(_))
}

///|
test "admission for an equal-quote different Effect plan cannot begin this plan" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let foreign = effect_operation_plan_fixture(prepared, request, contracts)
  assert_eq(
    prepared_installed_effect_managed_requirements(plan),
    prepared_installed_effect_managed_requirements(foreign),
  )
  let admission = effect_parent_test_admission(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  assert_true(
    begin_prepared_installed_effect_managed_run(
      admission, prepared, request, foreign,
    )
    is Err(Resource(ForeignOriginal)),
  )
  // Refusing the foreign plan did not start/consume a different original.
  let run = begin_prepared_installed_effect_managed_run(
    admission, prepared, request, plan,
  ).unwrap()
  retire_installed_managed_run(run).unwrap()
}

///|
test "one-short admitted envelope refuses the same Effect plan and retains its original cleanup" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  for field in [1, 3, 4, 5] {
    let quote = prepared_installed_effect_managed_requirements(plan)
    quote[field] -= 1L
    let admission = effect_parent_test_admission(plan, quote)
    assert_true(
      begin_prepared_installed_effect_managed_run(
        admission, prepared, request, plan,
      )
      is Err(InsufficientCapacity),
    )
    @resources.cleanup_node_managed_run_admission(admission).unwrap()
    @resources.cleanup_node_managed_run_admission(admission).unwrap()
  }
}

///|
test "same Effect parent retains pending operation budget and never refunds consumed Starts" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let admission = effect_parent_test_admission(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let run = begin_prepared_installed_effect_managed_run(
    admission, prepared, request, plan,
  ).unwrap()
  let ledger = prepare_installed_effect_managed_run_ledger(
    run,
    prepared,
    request,
    [],
    [],
    [],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  // One explicit resource use/cleanup port; no real send or ACK is implied.
  let use = @resources.reserve_attempt(ledger, 13L, 300L, 500L).unwrap()
  @resources.consume_reserved_attempt(ledger, use).unwrap()
  assert_true(retire_installed_managed_run(run) is Err(Resource(Unavailable)))
  assert_true(
    physical_equal(installed_effect_managed_operation_plan(run).unwrap(), plan),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  @resources.settle_reservation(ledger, use).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_true(run.preparation is None)
}

///|
test "planned Source parent consumes only the original quoted acquisition and capacity" {
  let plan = effect_operation_source_plan_fixture()
  let admission = effect_parent_test_admission(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let run = begin_prepared_installed_effect_managed_run(
    admission,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  let (declaration, requirement, acquisition, capacity) = prepared_installed_effect_managed_source(
    plan, 0,
  ).unwrap()
  let read = begin_installed_managed_run_source_read(run, 0).unwrap()
  attach_installed_source_read_acquisition(
    read, declaration, requirement, acquisition, 0, 0,
  ).unwrap()
  let ledger = prepare_installed_effect_managed_run_ledger(
    run,
    plan.prepared,
    plan.request,
    [capacity],
    plan.transport_bytes,
    plan.transport_execution_bytes,
    plan.installed_contracts,
    plan.values_body,
    plan.fragment_body,
    plan.ordered_body,
  ).unwrap()
  let copied = { ..capacity, }
  assert_true(
    prepare_installed_effect_managed_run_ledger(
      run,
      plan.prepared,
      plan.request,
      [copied],
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
    physical_equal(require_installed_managed_run(run).unwrap(), ledger),
  )
  // No Source start occurred; retire only these original unstarted aliases.
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(run).unwrap()
}

///|
test "physical extent membership retains original identity without another current callback" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let current_calls = Ref(0)
  let admission = effect_parent_test_admission(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => current_calls.val += 1,
  )
  let run = begin_prepared_installed_effect_managed_run(
    admission, prepared, request, plan,
  ).unwrap()
  let physical = prepared_installed_effect_managed_operation(
    plan, 0, true, 0, "operation",
  ).unwrap()
  let pure = prepared_installed_effect_managed_operation(
    plan, 0, true, 2, "operation",
  ).unwrap()
  let before = current_calls.val
  check_installed_effect_operation_extent(run, physical).unwrap()
  assert_true(
    check_installed_effect_operation_extent(run, pure) is Err(Unsupported),
  )
  let copied = { ..physical, }
  assert_true(
    check_installed_effect_operation_extent(run, copied) is Err(ForeignOriginal),
  )
  assert_eq(current_calls.val, before)
  retire_installed_managed_run(run).unwrap()
  assert_true(
    check_installed_effect_operation_extent(run, physical)
    is Err(ForeignOriginal),
  )
}
