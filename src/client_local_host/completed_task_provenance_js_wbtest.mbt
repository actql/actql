///|
// Numeric observation of this exact compiled component only. No value rows,
// callbacks, identities or opaque records leave the owned test instance.
extern "js" fn completion_reclamation_mask(
  run : @strategy.CapturedDAG,
  task : Int,
) -> Int =
  #|(run, task) => (run.lifetimes[task].completion !== undefined ? 1 : 0) |
  #| (run.outputs[task] === undefined ? 2 : 0) |
  #| (run.executions[task] === undefined ? 4 : 0) |
  #| (!run.lifetimes[task].live ? 8 : 0)

///|
extern "js" fn completed_consumed_producer(
  run : @strategy.CapturedDAG,
  task : Int,
) -> Int =
  #|(run, task) => Number.isSafeInteger(run.lifetimes[task].completion?.producer) ? run.lifetimes[task].completion.producer : -2

///|
test "Effect completed edges survive body reclamation under the same original control token" {
  let (prepared, request, contracts) = effect_operation_plan_inputs(suffix=true)
  let plan = effect_operation_plan_fixture(
    prepared,
    request,
    contracts,
    stage=2,
  )
  let count = @strategy.graph_task_count(plan.graph)
  assert_true(count >= 3)
  let (input, initial, ledger, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  retain_installed_effect_operation_controls_before_construction(
    owner, prepared, request, plan,
  ).unwrap()
  |> ignore
  let token = owner.effect_operation_controls.unwrap().reservation
  let (funded, idle) = installed_effect_control_capacity(
    owner.effect_operation_controls,
    plan,
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(funded)
  assert_true(
    @resources.capacity_reservation_matches(ledger, token, retained, idle),
  )
  let (host, captured, _) = open_installed_effect_managed_host(
      owner,
      effect_parent_bound_run(prepared),
      [],
    )
    .unwrap()
    .unwrap()
  let run = @strategy.captured_effect_run_dag(captured)
  let execution = execute_retained_effect_local_tasks_guarded(
    host,
    captured,
    1,
    100000,
    () => true,
  ).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":1}"])
  for task in 1..<count {
    assert_true(@strategy.captured_task_completed(run, task))
    assert_eq(completed_consumed_producer(run, task), task - 1)
  }
  // Only retire the finished predecessor. The final Result still has its
  // full live/current owner; an alias may keep execution cleanup pending.
  if (execution.tasks.unwrap().0)(1) is Some((operations, _)) {
    (operations.close)()
    for _ in 0..<10000 {
      @strategy.close_captured_task_output(run, 1)
      if (operations.cleanup_refresh)() && (operations.execution_stopped)() {
        break
      }
    }
  }
  @strategy.close_captured_task_output(run, 1)
  @strategy.refresh_captured_retention(run)
  assert_true((completion_reclamation_mask(run, 1) & 11) == 11)
  assert_eq(completed_consumed_producer(run, 1), 0)
  assert_eq(execution.rows().unwrap(), ["{\"id\":1}"])
  assert_true(@resources.capacity_reservation_open(token))
  // Retire the remaining actual aliases before stopping this Run. The outer
  // execution can still own input cleanup; do not invent its physical ACK.
  for task = count - 1; task >= 1; task = task - 1 {
    if (execution.tasks.unwrap().0)(task) is Some((operations, _)) {
      (operations.close)()
      for _ in 0..<10000 {
        @strategy.close_captured_task_output(run, task)
        if (operations.cleanup_refresh)() && (operations.execution_stopped)() {
          break
        }
      }
    }
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  assert_true((completion_reclamation_mask(run, 1) & 11) == 11)
  assert_true(@resources.capacity_reservation_open(token))
  assert_true(execution.close())
  // Stop revokes new artifact issuance and removes only historical DATA.
  assert_eq(completion_reclamation_mask(run, 1), 14)
  assert_true(@resources.capacity_reservation_open(token))
  retire_installed_managed_run(owner).unwrap()
  assert_false(@resources.capacity_reservation_open(token))
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "pure captured tasks keep their original constructor and no historical Effect records" {
  let value = captured_tasks_fixture()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(value.setup),
  )
  let execution = execute_captured_local_tasks_guarded(
    value.setup,
    value.capture,
    value.requirements,
    1,
    100000,
    () => true,
  ).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":2}"])
  for task in 0..<3 {
    assert_eq(completion_reclamation_mask(run, task) & 1, 0)
  }
  assert_true(execution.close())
  captured_tasks_close_source(value)
}

///|
test "dynamic and fixed Effect controls fund completion DATA once before constructor entry" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let fixed = effect_operation_plan_fixture(prepared, request, contracts)
  let dynamic = effect_operation_source_plan_fixture()
  for plan in [fixed, dynamic] {
    let tasks = @strategy.graph_task_count(plan.graph).to_int64()
    // Independently authored bounded constructor vector:5H7R4W per task.
    let bytes = @execution.preparation_representation_cost({
      record_headers: 5L * tasks,
      reference_slots: 7L * tasks,
      scalar_words: 4L * tasks,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).unwrap()
    assert_eq(bytes, 168L * tasks)
    let (before, idle) = installed_effect_control_capacity(None, plan).unwrap()
    assert_true(@execution.execution_capacity_retained_bytes(before) >= bytes)
    assert_true(idle >= bytes)
    if plan.closed_rows is None {
      // Preserve the existing checked multiplicity refusal for a zero-row
      // dynamic quote; this Source change does not introduce empty-row policy.
      assert_true(
        installed_effect_control_capacity(None, plan, captured_rows=Some(0))
        is None,
      )
      for rows in [1] {
        let actual = installed_effect_control_capacity(
          None,
          plan,
          captured_rows=Some(rows),
        )
        if actual is None {
          fail(
            "dynamic control absent rows=\{rows} ceiling=\{plan.rows} tasks=\{tasks}",
          )
        }
        let (actual, _) = actual.unwrap()
        let (selected, _) = installed_effect_control_capacity_for_rows(
          plan, rows,
        ).unwrap()
        assert_eq(
          @execution.execution_capacity_retained_bytes(actual),
          @execution.execution_capacity_retained_bytes(selected),
        )
      }
    }
    let quote = prepared_installed_effect_managed_requirements(plan)
    let (input, initial, ledger, capacity) = effect_parent_test_preparation(
      plan, quote,
    )
    let owner = begin_preparation_owned_installed_effect_managed_run(
      initial,
      input,
      capacity,
      plan.prepared,
      plan.request,
      plan,
    ).unwrap()
    let limits = @resources.ledger_limits(ledger)
    let usage = @resources.ledger_usage(ledger)
    let required = @execution.execution_capacity_retained_bytes(before)
    let block = @resources.reserve_capacity(
      ledger,
      limits.retained_bytes -
      usage.reserved_retention_bytes -
      usage.held_bytes -
      required +
      1L,
      0L,
    ).unwrap()
    assert_true(
      retain_installed_effect_operation_controls_before_construction(
        owner,
        plan.prepared,
        plan.request,
        plan,
      )
      is Err(_),
    )
    assert_true(owner.effect_operation_controls is None)
    @resources.settle_capacity(ledger, block).unwrap()
    retain_installed_effect_operation_controls_before_construction(
      owner,
      plan.prepared,
      plan.request,
      plan,
    ).unwrap()
    |> ignore
    let token = owner.effect_operation_controls.unwrap().reservation
    assert_true(@resources.capacity_reservation_open(token))
    retire_installed_managed_run(owner).unwrap()
    assert_false(@resources.capacity_reservation_open(token))
  }
}
