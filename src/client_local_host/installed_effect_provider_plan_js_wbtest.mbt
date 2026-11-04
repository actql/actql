///|
test "base Source handoff retains the same Plan acquisition and checked input selection" {
  let plan = effect_operation_source_plan_fixture()
  let selection = select_installed_effect_source_input(
    plan.prepared,
    plan.request,
    0,
    0,
  ).unwrap()
  guard selection is @sourceviews.QueryRoute(query) else {
    fail("expected checked Query input")
  }
  let (_, requirement, _, _) = prepared_installed_effect_managed_source(plan, 0).unwrap()
  assert_eq(
    @planning.query_acquisition_source_evidence_facts(query).unwrap().source_ref,
    @planning.query_requirement_source(requirement).0,
  )
  let (input, initial, _, parent) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    parent,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  let (read, requirement, acquisition, capacity) = begin_installed_effect_managed_source_read(
    owner,
    plan.declarations[0],
    0,
  ).unwrap()
  assert_true(physical_equal(capacity, plan.captures[0]))
  assert_true(capacity.provider is None)
  assert_true(
    capacity.acquisition is Some(original) &&
    physical_equal(original, acquisition),
  )
  assert_true(
    read.requirement is Some(original) && physical_equal(original, requirement),
  )
  assert_true(
    begin_installed_effect_managed_source_read(owner, plan.declarations[0], 0)
    is Err(AlreadyBound),
  )
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
}

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
test "provider Source reader refuses a one-byte-short reservation before any physical Start" {
  let provider = @execution.execution_capacity(1111L, 2222L).unwrap()
  let plan = effect_operation_source_plan_fixture(provider=Some(provider))
  for retention in [true, false] {
    let (input, initial, ledger, capacity) = effect_parent_test_preparation(
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
    let (read, _, acquisition, selected) = begin_installed_effect_managed_source_read(
      owner,
      plan.declarations[0],
      0,
    ).unwrap()
    assert_true(physical_equal(selected, plan.captures[0]))
    // The original acquisition owns its base reader. Its selected provider
    // adds the independently authored1111R/2222E before constructing a RowRun.
    let retained = @row_source_host.row_acquisition_retained_capacity(
        acquisition,
      ) +
      1111L
    let executing = @row_source_host.row_acquisition_execution_capacity(
        acquisition,
      ) +
      2222L
    let limits = @resources.ledger_limits(ledger)
    let usage = @resources.ledger_usage(ledger)
    let blocker = @resources.reserve_capacity(
      ledger,
      if retention {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes -
        retained +
        1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - usage.reserved_execution_bytes - executing + 1L
      },
    ).unwrap()
    let before = @resources.ledger_usage(ledger)
    let starts = Ref(0)
    let result = start_installed_source_read_provider_rows(
      read,
      acquisition,
      Some(provider),
      "provider-source-one-short",
      _ => {
        starts.val += 1
        true
      },
      plan.transport_bytes[0],
      0L,
    )
    if retention {
      assert_true(result is Err(Acquisition(Physical(RetentionLimit))))
    } else {
      assert_true(result is Err(Acquisition(Physical(ExecutionLimit))))
    }
    assert_eq(starts.val, 0)
    assert_true(read.run is None)
    assert_eq(@resources.ledger_usage(ledger), before)
    retire_installed_source_read(read).unwrap()
    assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
    @resources.settle_capacity(ledger, blocker).unwrap()
    retire_installed_managed_run(owner).unwrap()
    assert_eq(@resources.ledger_usage(ledger).attempts, usage.attempts)
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
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
