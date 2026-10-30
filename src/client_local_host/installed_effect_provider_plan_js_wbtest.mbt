///|
test "provider Source reader borrows only its same original planned Ledger and capture" {
  let provider = @execution.execution_capacity(1111L, 2222L).unwrap()
  let plan = effect_operation_source_plan_fixture(provider=Some(provider))
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    capacity,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  let (declaration, requirement, acquisition, capacity) = prepared_installed_effect_managed_source(
    plan, 0,
  ).unwrap()
  let read = begin_installed_managed_run_source_read(owner, 0).unwrap()
  attach_installed_source_read_acquisition(
    read, declaration, requirement, acquisition, 0, 0,
  ).unwrap()
  let ledger = prepare_installed_effect_managed_run_ledger(
    owner,
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
  assert_true(
    physical_equal(ledger, require_installed_managed_run(owner).unwrap()),
  )
  let copied = installed_provider_row_capture_capacity(
    acquisition,
    Some(provider),
  ).unwrap()
  assert_false(physical_equal(copied, capacity))
  assert_true(
    prepare_installed_effect_managed_run_ledger(
      owner,
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
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "provider Source Plan refuses the original one-short envelope before any physical Start" {
  let provider = @execution.execution_capacity(1111L, 2222L).unwrap()
  let plan = effect_operation_source_plan_fixture(provider=Some(provider))
  for field in [4, 5] {
    let quote = prepared_installed_effect_managed_requirements(plan)
    quote[field] -= 1L
    let (input, initial, _, capacity) = effect_preparation_test_capacity(
      plan, quote,
    )
    assert_true(
      begin_preparation_owned_installed_effect_managed_run(
        initial,
        input,
        capacity,
        plan.prepared,
        plan.request,
        plan,
      )
      is Err(InsufficientCapacity),
    )
    assert_true(@resources.retire_preparation_capacity(capacity).unwrap())
    @resources.cleanup_node_preparation_admission(initial).unwrap()
  }
}

///|
test "provider Source handoff attaches the same original planned read once before a caller can substitute it" {
  let provider = @execution.execution_capacity(1111L, 2222L).unwrap()
  let plan = effect_operation_source_plan_fixture(provider=Some(provider))
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    capacity,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  let foreign = effect_operation_source_plan_fixture(provider=Some(provider))
  assert_true(
    begin_installed_effect_managed_source_read(
      owner,
      foreign.declarations[0],
      0,
    )
    is Err(ForeignOriginal),
  )
  assert_true(owner.reads[0] is None)
  let (read, requirement, acquisition, capacity) = begin_installed_effect_managed_source_read(
    owner,
    plan.declarations[0],
    0,
  ).unwrap()
  assert_true(physical_equal(read, owner.reads[0].unwrap()))
  assert_true(
    read.requirement is Some(original) && physical_equal(original, requirement),
  )
  assert_true(
    read.acquisition is Some(original) && physical_equal(original, acquisition),
  )
  assert_true(physical_equal(capacity, plan.captures[0]))
  assert_true(
    begin_installed_effect_managed_source_read(owner, plan.declarations[0], 0)
    is Err(AlreadyBound),
  )
  assert_true(
    physical_equal(
      prepare_installed_effect_managed_run_ledger(
        owner,
        plan.prepared,
        plan.request,
        [capacity],
        plan.transport_bytes,
        plan.transport_execution_bytes,
        plan.installed_contracts,
        plan.values_body,
        plan.fragment_body,
        plan.ordered_body,
      ).unwrap(),
      require_installed_managed_run(owner).unwrap(),
    ),
  )
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_true(
    begin_installed_effect_managed_source_read(owner, plan.declarations[0], 0)
    is Err(Unsupported),
  )
}
