///|
// Actual existing checked Plan and admitted parent, without starting a RowRun,
// Source reader, provider, dispatch or physical Host.
#cfg(target="js")
test "Effect Source metadata borrows the same Plan inventory while current remains a separate gate" {
  let plan = effect_operation_source_plan_fixture(whole_inputs=true)
  let selected = prepared_installed_effect_source_occurrences(
      plan,
      plan.prepared,
      plan.request,
    )
    .unwrap()
    .unwrap()
  assert_true(physical_equal(selected, plan.direct_occurrences.unwrap()))
  let foreign = effect_operation_source_plan_fixture(whole_inputs=true)
  assert_true(
    prepared_installed_effect_source_occurrences(
      plan,
      foreign.prepared,
      plan.request,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    prepared_installed_effect_source_occurrences(
      plan,
      plan.prepared,
      foreign.request,
    )
    is Err(ForeignOriginal),
  )
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
  let before = @resources.ledger_usage(ledger)
  for slot in 0..<2 {
    assert_eq(
      installed_effect_managed_source_occurrence(
        owner,
        plan.prepared,
        plan.request,
        slot,
      ).unwrap(),
      (0, slot, 0),
    )
  }
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    installed_effect_managed_source_occurrence(
      owner,
      foreign.prepared,
      plan.request,
      0,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    installed_effect_managed_source_occurrence(
      owner,
      plan.prepared,
      plan.request,
      2,
    )
    is Err(ForeignOriginal),
  )
  retire_installed_managed_run(owner).unwrap()
  assert_true(
    check_installed_effect_managed_run(owner, plan.prepared, plan.request)
    is Err(_),
  )
}
