///|
fn effect_host_preview_input_fixture() -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledEffectManagedPlan,
  ClientInstalledManagedRun,
  @resources.Ledger,
) {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let original = effect_operation_plan_fixture(prepared, request, contracts)
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  let host = prepare_installed_effect_host_input_capture_recipe_extent(
    "operation",
    [
      @execution.execution_capacity(8L, 8L).unwrap(),
      empty,
      empty,
      empty,
      empty,
      empty,
    ],
    1000000,
    100000,
    64,
  ).unwrap()
  let before = original.operations[0]
  let members = before.member_extents.copy()
  members.push(host)
  let demand = prepare_installed_effect_operation_demand(
    prepared,
    0,
    "save",
    members,
    before.row_extents,
  ).unwrap()
  let plan = prepare_installed_effect_managed_plan(
    prepared,
    request,
    [],
    "",
    "",
    [],
    [],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    [demand],
    provider_factory=_ => [],
  ).unwrap()
  let requirements = prepared_installed_effect_managed_requirements(plan)
  // Explicit existing parent ports for this control/accounting unit only.
  // Product policy and normal Host admission are not changed by this fixture.
  requirements[4] += 1000000L
  requirements[5] += 1000000L
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan, requirements,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  ignore(
    retain_installed_effect_operation_controls_before_construction(
      owner, prepared, request, plan,
    ).unwrap(),
  )
  (prepared, request, plan, owner, ledger)
}

///|
test "Host Preview deferred forest keeps original full text and codec maxima" {
  let (full, full_work) = installed_standard_host_preview_input_parts(
    4096,
    128,
    16,
    None,
  ).unwrap()
  let (initial, initial_work) = installed_standard_host_preview_input_parts(
    4096,
    128,
    16,
    Some(0),
  ).unwrap()
  let (actual, actual_work) = installed_standard_host_preview_input_parts(
    4096,
    128,
    16,
    Some(32),
  ).unwrap()
  assert_eq(initial.owned_utf16_units, full.owned_utf16_units)
  assert_eq(actual.owned_utf16_units, full.owned_utf16_units)
  assert_eq(initial.record_headers, 0L)
  assert_eq(initial.reference_slots, 0L)
  assert_eq(initial.scalar_words, 0L)
  assert_eq(
    @execution.preparation_representation_cost(initial_work).unwrap(),
    0L,
  )
  assert_true(
    actual.record_headers > 0L && actual.record_headers <= full.record_headers,
  )
  assert_true(
    @execution.preparation_representation_cost(actual_work).unwrap() <=
    @execution.preparation_representation_cost(full_work).unwrap(),
  )
  assert_true(
    installed_standard_host_preview_input_parts(4096, 128, 16, Some(4097))
    is None,
  )
}

///|
test "Host Preview grows same original control before parse and keeps its returned forest across later children" {
  let (prepared, request, plan, owner, ledger) = effect_host_preview_input_fixture()
  let before = @resources.ledger_usage(ledger)
  let wire = "{\"rows\":[{\"id\":1}]}"
  begin_installed_effect_operation_control_input(
    owner, prepared, request, plan, wire,
  ).unwrap()
  let active = @resources.ledger_usage(ledger)
  assert_true(active.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_eq(active.attempts, before.attempts)
  assert_eq(active.transferred_bytes, before.transferred_bytes)
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  let held = @resources.ledger_usage(ledger)
  assert_eq(held.reserved_retention_bytes, active.reserved_retention_bytes)
  assert_true(held.reserved_execution_bytes < active.reserved_execution_bytes)
  assert_true(
    begin_installed_effect_operation_control_input(
      owner, prepared, request, plan, wire,
    )
    is Err(AlreadyBound),
  )
  assert_eq(@resources.ledger_usage(ledger), held)
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  assert_true(retire_installed_effect_operation(child, false) is Ok(false))
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(retire_installed_effect_operation(child, true) is Ok(true))
  assert_eq(@resources.ledger_usage(ledger), held)
  assert_true(
    begin_installed_effect_operation_control_input(
      owner, prepared, request, plan, "{\"different\":true}",
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), held)
  retire_installed_managed_run(owner).unwrap()
  assert_true(owner.effect_operation_controls is None)
}

///|
test "Host Preview refused growth leaves same original usage and input selection unchanged" {
  let (prepared, request, plan, owner, ledger) = effect_host_preview_input_fixture()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_control_input(
      owner,
      prepared,
      request,
      plan,
      "x".repeat(500000),
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(owner.effect_operation_controls.unwrap().host_input is None)
  begin_installed_effect_operation_control_input(
    owner, prepared, request, plan, "{}",
  ).unwrap()
  complete_installed_effect_operation_control_construction(
    owner, prepared, request, plan,
  ).unwrap()
  retire_installed_managed_run(owner).unwrap()
}
