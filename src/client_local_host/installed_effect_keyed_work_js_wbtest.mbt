///|
#cfg(target="js")
test "keyed work is the same admitted Plan ValueBudget policy without changing Ledger usage" {
  let (parent, owner, plan) = request_generic_keyed_bound_parent_fixture()
  let before = @resources.ledger_usage(parent.ledger)
  let work = installed_effect_keyed_input_work_limit(
    owner,
    plan.prepared,
    plan.request,
  ).unwrap()
  assert_eq(work, plan.capacity_plan.values.max_work)
  assert_eq(work, plan.capacity_plan.execution.rows.input_values.max_work)
  assert_eq(work, plan.capacity_plan.execution.max_work)
  assert_eq(work, plan.capacity_plan.measurement.max_work)
  assert_true(work > 1000000)
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}

///|
#cfg(target="js")
test "keyed work projection refuses copied Run foreign prepared equal Request and retired custody" {
  let (parent, owner, plan) = request_generic_keyed_bound_parent_fixture()
  let copied = { ..owner, }
  let equal_request = @publication_host.prepare_client_effect_request_identity(
    plan.prepared,
    "sha256:" + "a".repeat(64),
    "keyed-parent-counter",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  assert_true(
    installed_effect_keyed_input_work_limit(copied, plan.prepared, plan.request)
    is Err(ForeignOriginal),
  )
  assert_true(
    installed_effect_keyed_input_work_limit(
      owner,
      installed_effect_managed_fixture(),
      plan.request,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    installed_effect_keyed_input_work_limit(owner, plan.prepared, equal_request)
    is Err(ForeignOriginal),
  )
  retire_installed_managed_run(owner).unwrap()
  assert_true(
    installed_effect_keyed_input_work_limit(owner, plan.prepared, plan.request)
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
