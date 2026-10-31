///|
// The existing authored Effect/Plan/original Resource fixture, with N distinct
// member occurrences. No Source I/O, physical attempt or business Run is used.
fn effect_operation_lookup_work(count : Int) -> Int64 raise {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let extent = prepare_installed_effect_operation_extent(
    "indexed-constructor", @execution.execution_capacity(50L, 70L).unwrap(),
    0L, false,
  ).unwrap()
  let demand = prepare_installed_effect_operation_demand(
    prepared, 0, "save", Array::make(count, extent), [],
  ).unwrap()
  let plan = prepare_installed_effect_managed_plan(
    prepared, request, [], "", "", [], [], contracts,
    source_query_original_values, Some(source_query_original_fragment), None,
    [demand], provider_factory=_ => [],
  ).unwrap()
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan, prepared_installed_effect_managed_requirements(plan),
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
      owner, prepared, request, plan, 0, false, index, 0,
      "indexed-constructor", lookup_probes=Some(probes),
    ).unwrap()
    owner.effect_operation_opening = false
    assert_true(physical_equal(require_installed_effect_operation(
      value, lookup_probes=Some(probes),
    ).unwrap(), ledger))
    assert_true(retire_installed_effect_operation(value, true).unwrap())
  }
  let spent = @resources.ledger_usage(ledger)
  for index in 0..<count {
    owner.effect_operation_opening = true
    let duplicate = borrow_installed_effect_operation_original(
      owner, prepared, request, plan, 0, false, index, 0,
      "indexed-constructor", lookup_probes=Some(probes),
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
