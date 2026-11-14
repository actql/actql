///|
// Actual checked Values/Effect/Plan and adopted same-Run numeric resources.
// The existing fixture uses in-memory physical ports and Allow DATA; this is
// Core funding/current evidence, not ordinary Account/Journal/STORE acceptance.
fn dependency_original_fixture(
  current? : () -> Unit = () => (),
  selected_environment? : @checked.CheckEnvironment? = None,
) -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledEffectManagedPlan,
  ClientInstalledManagedRun,
  @resources.Ledger,
  @strategy.CapturedEffectRunDAG,
  LocalValuesExecution,
) raise {
  let (prepared, request, plan, owner, ledger) = native_control_fixture(
    current~,
    selected_environment~,
  )
  let (host, captured, _) = open_installed_effect_managed_host(
      owner,
      effect_parent_bound_run(prepared),
      [],
    )
    .unwrap()
    .unwrap()
  let execution = execute_retained_effect_local_tasks_guarded(
    host,
    captured,
    1,
    100000,
    () => true,
  ).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":1}", "{\"id\":2}"])
  (prepared, request, plan, owner, ledger, captured, execution)
}

///|
test "same original dependency pin and static bodies retain measured numeric prefix with bounded current" {
  let calls = Ref(0)
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture(current=() => {
      calls.val += 1
    },
  )
  let before = @resources.ledger_usage(ledger)
  let inputs = pin_installed_effect_sources(
    owner, prepared, request, plan, captured, 64,
  ).unwrap()
  let pinned = @resources.ledger_usage(ledger)
  assert_true(pinned.reserved_retention_bytes > before.reserved_retention_bytes)
  let original = owner.effect_operation_controls.unwrap()
  assert_true(original.dependency_work is Some(_))
  let current = calls.val
  let planning = pinned.planning_work
  let bodies = prepare_installed_effect_dependency_bodies(
    owner, prepared, request, plan, inputs, 0, 1000000, 100000, 64,
  ).unwrap()
  assert_eq(bodies.length(), 6)
  assert_true(calls.val > current && calls.val - current <= 20)
  assert_eq(@resources.ledger_usage(ledger).planning_work, planning)
  assert_true(
    physical_equal(original, owner.effect_operation_controls.unwrap()),
  )
  let held = @resources.ledger_usage(ledger)
  assert_true(held.reserved_retention_bytes > pinned.reserved_retention_bytes)
  assert_eq(held.attempts, before.attempts)
  assert_eq(held.transferred_bytes, before.transferred_bytes)
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_true(owner.effect_operation_controls is None)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "dependency initial one-byte-short grow refuses before Work or pin construction" {
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture()
  let control = owner.effect_operation_controls.unwrap()
  let fixed = installed_effect_dependency_fixed_capacity(
    0,
    @strategy.captured_effect_dependency_unit_count(captured),
    64,
  ).unwrap()
  let (capacity, _) = installed_effect_control_capacity(
    Some(control),
    plan,
    dependency_capacity=Some(fixed),
  ).unwrap()
  let target = @execution.execution_capacity_execution_bytes(capacity)
  let (_, idle) = installed_effect_control_capacity(Some(control), plan).unwrap()
  let delta = target - idle
  assert_true(delta > 0L)
  let remaining = @resources.ledger_limits(ledger).execution_bytes -
    @resources.ledger_usage(ledger).reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, remaining - delta + 1L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    pin_installed_effect_sources(owner, prepared, request, plan, captured, 64)
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_false(control.dependency_started)
  assert_true(
    control.dependency_work is None && control.dependency_inputs is None,
  )
  @resources.settle_capacity(ledger, pressure).unwrap()
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "dependency original refuses copied owner and foreign retained inputs before metadata allocation" {
  let calls = Ref(0)
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture(current=() => {
      calls.val += 1
    },
  )
  let (
    foreign_prepared,
    foreign_request,
    foreign_plan,
    foreign,
    _,
    foreign_capture,
    foreign_execution,
  ) = dependency_original_fixture()
  let foreign_inputs = pin_installed_effect_sources(
    foreign, foreign_prepared, foreign_request, foreign_plan, foreign_capture, 64,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let current = calls.val
  assert_true(
    pin_installed_effect_sources(
      { ..owner, },
      prepared,
      request,
      plan,
      captured,
      64,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    prepare_installed_effect_dependency_bodies(
      owner, prepared, request, plan, foreign_inputs, 0, 1000000, 100000, 64,
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(calls.val, current)
  assert_true(@strategy.release_captured_effect_inputs(foreign_inputs))
  assert_true(foreign_execution.close())
  retire_installed_managed_run(foreign).unwrap()
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
}
