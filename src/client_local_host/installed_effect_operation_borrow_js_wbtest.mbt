///|
fn effect_operation_borrow_fixture() -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledEffectManagedPlan,
  ClientInstalledManagedRun,
  @resources.Ledger,
) {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  // Existing explicit 10-byte initial carrier tests original accounting only;
  // it is not the final normal Host constructor/implementation recipe.
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  (prepared, request, plan, owner, ledger)
}

///|
test "Effect operation reserves original occurrence before construction and retains failed cleanup" {
  let (prepared, request, plan, owner, ledger) = effect_operation_borrow_fixture()
  let before = @resources.ledger_usage(ledger)
  let operation = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  let reserved = @resources.ledger_usage(ledger)
  assert_eq(
    reserved.reserved_retention_bytes,
    before.reserved_retention_bytes + 50L,
  )
  assert_eq(
    reserved.reserved_execution_bytes,
    before.reserved_execution_bytes + 70L,
  )
  assert_eq(reserved.reserved_attempts, before.reserved_attempts)
  assert_true(start_installed_effect_operation(operation) is Err(Unsupported))
  assert_eq(retire_installed_effect_operation(operation, false), Ok(false))
  assert_eq(@resources.ledger_usage(ledger), reserved)
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_eq(retire_installed_effect_operation(operation, true), Ok(true))
  assert_eq(retire_installed_effect_operation(operation, true), Ok(true))
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 2, 0, "operation",
    )
    is Err(AlreadyBound),
  )
  assert_true(
    operation.owner is None &&
    operation.ledger is None &&
    operation.backing is None,
  )
  retire_installed_managed_run(owner).unwrap()
}

///|
test "Effect physical occurrence spends once and original lost reply stays uncertain after cleanup" {
  let (prepared, request, plan, owner, ledger) = effect_operation_borrow_fixture()
  let operation = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "operation",
  ).unwrap()
  assert_true(
    charge_installed_effect_operation(operation, 1L) is Err(Unsupported),
  )
  let before = @resources.ledger_usage(ledger)
  start_installed_effect_operation(operation).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts + 1)
  assert_true(start_installed_effect_operation(operation) is Err(AlreadyBound))
  charge_installed_effect_operation(operation, 5L).unwrap()
  mark_installed_effect_operation_unknown(operation).unwrap()
  let unknown = @resources.ledger_usage(ledger)
  assert_eq(unknown.transferred_bytes, before.transferred_bytes + 5L)
  assert_eq(
    unknown.uncertain_transfer_bytes,
    before.uncertain_transfer_bytes + 8L,
  )
  assert_eq(retire_installed_effect_operation(operation, false), Ok(false))
  assert_eq(@resources.ledger_usage(ledger), unknown)
  assert_eq(retire_installed_effect_operation(operation, true), Ok(true))
  assert_eq(@resources.ledger_usage(ledger).attempts, unknown.attempts)
  assert_eq(
    @resources.ledger_usage(ledger).uncertain_transfer_bytes,
    unknown.uncertain_transfer_bytes,
  )
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 0, 0, "operation",
    )
    is Err(AlreadyBound),
  )
  retire_installed_managed_run(owner).unwrap()
}

///|
test "Effect occurrence refuses foreign Plan request name and row before reserving" {
  let (prepared, request, plan, owner, ledger) = effect_operation_borrow_fixture()
  let (_, foreign_request, _) = effect_operation_plan_inputs()
  let foreign_plan = effect_operation_plan_fixture(
    prepared,
    request,
    prepare_installed_sequence_contracts(
      source_query_original_registry,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    ).unwrap(),
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, foreign_request, plan, 0, true, 0, 0, "operation",
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, foreign_plan, 0, true, 0, 0, "operation",
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    borrow_installed_effect_operation(
      owner,
      prepared,
      request,
      plan,
      0,
      true,
      0,
      plan.rows,
      "operation",
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 0, 0, "foreign",
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  retire_installed_managed_run(owner).unwrap()
}
