///|
// The existing authored Effect/Plan/original Resource fixture, with N distinct
// member occurrences. No Source I/O, physical attempt or business Run is used.
fn effect_operation_lookup_work(count : Int) -> Int64 raise {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let extent = prepare_installed_effect_operation_extent(
    "indexed-constructor",
    @execution.execution_capacity(50L, 70L).unwrap(),
    0L,
    false,
  ).unwrap()
  let demand = prepare_installed_effect_operation_demand(
    prepared,
    0,
    "save",
    Array::make(count, extent),
    [],
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
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  let probes = Ref(0L)
  for index in 0..<count {
    // Same private implementation as the public borrow, with its actual
    // synchronous opening fence. Only the work output differs from None.
    owner.effect_operation_opening = true
    let value = borrow_installed_effect_operation_original(
      owner,
      prepared,
      request,
      plan,
      0,
      false,
      index,
      0,
      "indexed-constructor",
      lookup_probes=Some(probes),
    ).unwrap()
    owner.effect_operation_opening = false
    assert_true(
      physical_equal(
        require_installed_effect_operation(value, lookup_probes=Some(probes)).unwrap(),
        ledger,
      ),
    )
    assert_true(retire_installed_effect_operation(value, true).unwrap())
  }
  let spent = @resources.ledger_usage(ledger)
  for index in 0..<count {
    owner.effect_operation_opening = true
    let duplicate = borrow_installed_effect_operation_original(
      owner,
      prepared,
      request,
      plan,
      0,
      false,
      index,
      0,
      "indexed-constructor",
      lookup_probes=Some(probes),
    )
    owner.effect_operation_opening = false
    assert_true(duplicate is Err(AlreadyBound))
  }
  assert_eq(@resources.ledger_usage(ledger), spent)
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  probes.val
}

///|
test "Effect coordinate and original membership lookup avoid quadratic N versus 2N search work" {
  let n = effect_operation_lookup_work(32)
  let twice = effect_operation_lookup_work(64)
  println("Effect lookup probes N=32: \{n}, N=64: \{twice}")
  assert_true(n > 0L)
  assert_true(twice <= 3L * n)
}

///|
test "stable Effect slots retain pending originals and lightweight spent coordinates without reissuing a retired body" {
  let (prepared, request, plan, owner, ledger) = effect_operation_borrow_fixture()
  let first = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  let second = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "operation",
  ).unwrap()
  assert_eq(first.slot, 0)
  assert_eq(second.slot, 1)
  owner.effect_operations[first.slot] = Some(second)
  assert_true(require_installed_effect_operation(first) is Err(Retired))
  owner.effect_operations[first.slot] = Some(first)
  assert_false(retire_installed_effect_operation(first, false).unwrap())
  assert_true(
    owner.effect_operations[first.slot] is Some(original) &&
    physical_equal(original, first),
  )
  assert_true(retire_installed_effect_operation(first, true).unwrap())
  assert_true(owner.effect_operations[first.slot] is None)
  assert_true(
    first.owner is None && first.ledger is None && first.backing is None,
  )
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 2, 0, "operation",
    )
    is Err(AlreadyBound),
  )
  let third = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 1, 0, "operation",
  ).unwrap()
  assert_eq(third.slot, 2)
  assert_true(require_installed_effect_operation(first) is Err(Retired))
  let control = owner.effect_operation_controls.unwrap()
  assert_eq(control.coordinates.length(), 3)
  for (coordinate, _) in control.coordinates {
    assert_true(coordinate.lookup_probes is None)
  }
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(retire_installed_effect_operation(second, true).unwrap())
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(retire_installed_effect_operation(third, true).unwrap())
  assert_true(owner.effect_operations.all(value => value is None))
  retire_installed_managed_run(owner).unwrap()
  assert_true(owner.effect_operation_controls is None)
  assert_true(control.coordinates.is_empty())
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "Effect stable membership rechecks actual operation retirement during its one Run current callback" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let selected : Ref[ClientInstalledEffectOperationBorrow?] = Ref(None)
  let retire_now = Ref(false)
  let acknowledged = Ref(false)
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => {
      if retire_now.val && selected.val is Some(value) {
        retire_now.val = false
        acknowledged.val = retire_installed_effect_operation(value, true)
          is Ok(true)
      }
    },
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let value = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 2, 0, "operation",
  ).unwrap()
  selected.val = Some(value)
  retire_now.val = true
  assert_true(require_installed_effect_operation(value) is Err(Retired))
  assert_true(acknowledged.val)
  assert_true(owner.effect_operations[value.slot] is None)
  assert_true(
    borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, true, 2, 0, "operation",
    )
    is Err(AlreadyBound),
  )
  selected.val = None
  retire_installed_managed_run(owner).unwrap()
}
