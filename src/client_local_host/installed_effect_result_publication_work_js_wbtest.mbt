///|
// Genuine checked/adopted Effect originals and completed managed rows. The
// explicit component Resource fixture is not ordinary Account/Store approval.
fn effect_result_work_start(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  owner : ClientInstalledManagedRun,
  captured : @strategy.CapturedEffectRunDAG,
  execution : LocalValuesExecution,
  order_work? : Int? = None,
) -> (
  @execution.ManagedPublicationBridge[Int],
  @publication_host.CapturedClientResultTransformation,
) {
  let original = installed_effect_managed_publication_limits(
    owner, prepared, request, plan, 10000000,
  ).unwrap()
  let limits = match order_work {
    Some(work) => { ..original, max_result_order_work: work, }
    None => original
  }
  let (bridge, output) = execution
    .prepare_publication_bridge(
      plan.capacity_plan.imports.row,
      plan.capacity_plan.metadata.bridge_entries,
      plan.capacity_plan.metadata.name_bytes,
      limits,
    )
    .unwrap()
  let transformation = @publication_host.start_captured_managed_result_publication_export(
    @strategy.captured_effect_run_dag(captured),
    0,
    execution.completed,
    bridge,
    output,
    limits,
  ).unwrap()
  (bridge, transformation)
}

///|
fn effect_result_work_remaining(owner : ClientInstalledManagedRun) -> Int64 {
  let receipt = owner.effect_operation_controls.unwrap().dependency_work.unwrap()
  @resources.resume_preparation_phase_work_continuation64(receipt).unwrap()
  let remaining = @resources.remaining_preparation_phase_work_continuation64(
    receipt,
  ).unwrap()
  @resources.return_preparation_phase_work_continuation64(receipt).unwrap()
  remaining
}

///|
test "Effect Result progress and later dependency pin spend one original receipt" {
  // resource-case-id: effect_result_original_work_receipt
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture()
  prepare_installed_effect_result_publication_work(
    owner, prepared, request, plan, captured,
  ).unwrap()
  let receipt = owner.effect_operation_controls.unwrap().dependency_work.unwrap()
  assert_true(
    prepare_installed_effect_result_publication_work(
      owner, prepared, request, plan, captured,
    )
    is Err(AlreadyBound),
  )
  let (bridge, transformation) = effect_result_work_start(
    prepared, request, plan, owner, captured, execution,
  )
  let before = effect_result_work_remaining(owner)
  let mut total = 0
  let mut ready = false
  for _ in 0..<10000 {
    let (done, work) = advance_installed_effect_result_publication(
      owner, prepared, request, plan, captured, transformation, 1,
    ).unwrap()
    assert_true(work >= 0 && work <= 1)
    total += work
    if done {
      ready = true
      break
    }
  }
  assert_true(ready && total > 0)
  assert_eq(before - effect_result_work_remaining(owner), total.to_int64())
  let exported = transformation.finish().unwrap()
  exported.cancel()
  @execution.close_managed_publication_bridge(bridge)
  let after_result = effect_result_work_remaining(owner)
  let inputs = pin_installed_effect_sources(
    owner, prepared, request, plan, captured, 64,
  ).unwrap()
  assert_true(
    physical_equal(
      receipt,
      owner.effect_operation_controls.unwrap().dependency_work.unwrap(),
    ),
  )
  assert_true(effect_result_work_remaining(owner) < after_result)
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "Effect Result rejects foreign Plan Run and cancelled original without spending work" {
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture()
  let (
    other_prepared,
    other_request,
    other_plan,
    other_owner,
    other_ledger,
    other_captured,
    other_execution,
  ) = dependency_original_fixture()
  prepare_installed_effect_result_publication_work(
    owner, prepared, request, plan, captured,
  ).unwrap()
  let (bridge, transformation) = effect_result_work_start(
    prepared, request, plan, owner, captured, execution,
  )
  let before = effect_result_work_remaining(owner)
  assert_true(
    advance_installed_effect_result_publication(
      owner, prepared, request, other_plan, captured, transformation, 1,
    )
    is Err(Operation(ForeignOriginal)),
  )
  assert_true(
    advance_installed_effect_result_publication(
      owner, prepared, request, plan, other_captured, transformation, 1,
    )
    is Err(Operation(ForeignOriginal)),
  )
  assert_eq(effect_result_work_remaining(owner), before)
  transformation.cancel()
  assert_true(
    advance_installed_effect_result_publication(
      owner, prepared, request, plan, captured, transformation, 1,
    )
    is Err(Operation(ForeignOriginal)),
  )
  assert_eq(effect_result_work_remaining(owner), before)
  @execution.close_managed_publication_bridge(bridge)
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_true(
    advance_installed_effect_result_publication(
      owner, prepared, request, plan, captured, transformation, 1,
    )
    is Err(Operation(_)),
  )
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  ignore(other_prepared)
  ignore(other_request)
  ignore(other_plan)
  assert_true(other_execution.close())
  retire_installed_managed_run(other_owner).unwrap()
  assert_eq(@resources.ledger_usage(other_ledger).live_reservations, 0)
}

///|
test "failed Result poll keeps observed work before transform refusal and cleanup" {
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture()
  prepare_installed_effect_result_publication_work(
    owner, prepared, request, plan, captured,
  ).unwrap()
  let (bridge, transformation) = effect_result_work_start(
    prepared,
    request,
    plan,
    owner,
    captured,
    execution,
    order_work=Some(0),
  )
  let before = effect_result_work_remaining(owner)
  assert_true(
    advance_installed_effect_result_publication(
      owner, prepared, request, plan, captured, transformation, 256,
    )
    is Err(Transform(_)),
  )
  assert_true(effect_result_work_remaining(owner) < before)
  transformation.cancel()
  @execution.close_managed_publication_bridge(bridge)
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "Result grants only remaining original work and refuses without another transition" {
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture()
  prepare_installed_effect_result_publication_work(
    owner, prepared, request, plan, captured,
  ).unwrap()
  let (bridge, transformation) = effect_result_work_start(
    prepared, request, plan, owner, captured, execution,
  )
  let receipt = owner.effect_operation_controls.unwrap().dependency_work.unwrap()
  @resources.resume_preparation_phase_work_continuation64(receipt).unwrap()
  let remaining = @resources.remaining_preparation_phase_work_continuation64(
    receipt,
  ).unwrap()
  @resources.spend_preparation_phase_work_continuation64(
    receipt,
    remaining - 1L,
  ).unwrap()
  @resources.return_preparation_phase_work_continuation64(receipt).unwrap()
  let (done, work) = advance_installed_effect_result_publication(
    owner, prepared, request, plan, captured, transformation, 256,
  ).unwrap()
  assert_false(done)
  assert_eq(work, 1)
  assert_eq(effect_result_work_remaining(owner), 0L)
  assert_true(
    advance_installed_effect_result_publication(
      owner, prepared, request, plan, captured, transformation, 256,
    )
    is Err(Operation(Ledger(PlanningLimit))),
  )
  assert_eq(effect_result_work_remaining(owner), 0L)
  transformation.cancel()
  @execution.close_managed_publication_bridge(bridge)
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "Result work upfront one-byte-short refusal issues no receipt and preserves original cleanup" {
  // resource-case-id: effect_result_one_short_cleanup
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture()
  let control = owner.effect_operation_controls.unwrap()
  let capacity = installed_effect_result_publication_work_capacity().unwrap()
  let (target, _) = installed_effect_control_capacity(
    Some(control),
    plan,
    dependency_capacity=Some(capacity),
  ).unwrap()
  let (_, idle) = installed_effect_control_capacity(Some(control), plan).unwrap()
  let delta = target.execution_bytes - idle
  assert_true(delta > 0L)
  let remaining = @resources.ledger_limits(ledger).execution_bytes -
    @resources.ledger_usage(ledger).reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, remaining - delta + 1L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    prepare_installed_effect_result_publication_work(
      owner, prepared, request, plan, captured,
    )
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    control.dependency_work is None && control.dependency_capacity is None,
  )
  @resources.settle_capacity(ledger, pressure).unwrap()
  prepare_installed_effect_result_publication_work(
    owner, prepared, request, plan, captured,
  ).unwrap()
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "Result current callback cannot reenter the same original meter" {
  let reenter : Ref[(() -> Unit)?] = Ref(None)
  let refused = Ref(false)
  let (prepared, request, plan, owner, ledger, captured, execution) = dependency_original_fixture(current=() => {
      if reenter.val is Some(callback) {
        reenter.val = None
        callback()
      }
    },
  )
  prepare_installed_effect_result_publication_work(
    owner, prepared, request, plan, captured,
  ).unwrap()
  let receipt = owner.effect_operation_controls.unwrap().dependency_work.unwrap()
  let (bridge, transformation) = effect_result_work_start(
    prepared, request, plan, owner, captured, execution,
  )
  let before = effect_result_work_remaining(owner)
  reenter.val = Some(() => {
    refused.val = advance_installed_effect_result_publication(
        owner, prepared, request, plan, captured, transformation, 1,
      )
      is Err(Operation(AlreadyBound))
  })
  let (_, work) = advance_installed_effect_result_publication(
    owner, prepared, request, plan, captured, transformation, 1,
  ).unwrap()
  assert_true(refused.val)
  assert_eq(before - effect_result_work_remaining(owner), work.to_int64())
  assert_true(
    physical_equal(
      receipt,
      owner.effect_operation_controls.unwrap().dependency_work.unwrap(),
    ),
  )
  transformation.cancel()
  @execution.close_managed_publication_bridge(bridge)
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}
