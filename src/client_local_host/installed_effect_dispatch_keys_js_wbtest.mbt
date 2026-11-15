///|
// Actual checked Plan and existing adopted numeric control Owner. This proves
// same-token growth/refusal/current/cleanup, not a normal File/Journal send.
test "new command correlation cohort grows the same control before text construction" {
  let (prepared, request, plan, owner, ledger) = native_control_fixture()
  let control = owner.effect_operation_controls.unwrap()
  let quote = installed_effect_command_dispatch_key_capacity(2L, 64, 8).unwrap()
  let one = installed_effect_command_dispatch_key_capacity(1L, 64, 8).unwrap()
  let text = @execution.preparation_representation_cost({
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 73L,
    owned_wire_bytes: 0L,
  }).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(one), text)
  assert_eq(@execution.execution_capacity_retained_bytes(quote), 2L * text)
  assert_eq(
    @execution.execution_capacity_execution_bytes(quote) -
    @execution.execution_capacity_retained_bytes(quote),
    @execution.execution_capacity_execution_bytes(one) -
    @execution.execution_capacity_retained_bytes(one),
  )
  let (capacity, idle) = installed_effect_control_capacity(
    Some(control),
    plan,
    dependency_capacity=Some(quote),
  ).unwrap()
  let target = if control.construction_deferred {
    idle +
    @execution.execution_capacity_execution_bytes(quote) -
    @execution.execution_capacity_retained_bytes(quote)
  } else {
    @execution.execution_capacity_execution_bytes(capacity)
  }
  let usage = @resources.ledger_usage(ledger)
  let delta = target - usage.reserved_execution_bytes
  assert_true(delta > 0L)
  let remaining = @resources.ledger_limits(ledger).execution_bytes -
    usage.reserved_execution_bytes
  let pressure = @resources.reserve_capacity(ledger, 0L, remaining - delta + 1L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let preparation = owner.preparation.unwrap()
  guard preparation is PlannedEffectManaged(admission, _) else {
    fail("wrong original fixture")
  }
  assert_true(
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, quote,
    )
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(control.dependency_capacity is None)
  @resources.settle_capacity(ledger, pressure).unwrap()
  let before = @resources.ledger_usage(ledger)
  retain_installed_effect_dependency_capacity(
    owner, preparation, admission, plan, ledger, control, quote,
  ).unwrap()
  let held = @resources.ledger_usage(ledger)
  assert_eq(
    held.reserved_retention_bytes - before.reserved_retention_bytes,
    2L * text,
  )
  assert_eq(held.attempts, before.attempts)
  assert_true(physical_equal(control, owner.effect_operation_controls.unwrap()))
  // A second real construction cohort must retain its own two Strings.
  retain_installed_effect_dependency_capacity(
    owner, preparation, admission, plan, ledger, control, quote,
  ).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes -
    held.reserved_retention_bytes,
    2L * text,
  )
  require_installed_effect_operation_plan(owner, prepared, request).unwrap()
  |> ignore
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}
