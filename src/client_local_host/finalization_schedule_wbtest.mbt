///|
test "finalization scheduling retains finite semantic and mandatory scratch dimensions" {
  // Independent cursor inventory: semantic20m, three row/cell arrays600k,
  // admitted reference-node100k, three column slots3 and closing transitions3.
  assert_eq(
    local_finalization_round_bound(20000000, 100000, 1, 100000),
    Some(20700006),
  )
  assert_eq(local_finalization_round_bound(0, 0, 0, 0), Some(3))
  assert_eq(local_finalization_round_bound(-1, 0, 0, 0), None)
  assert_eq(local_finalization_round_bound(0, -1, 0, 0), None)
  assert_eq(local_finalization_round_bound(0, 0, -1, 0), None)
  assert_eq(local_finalization_round_bound(0, 0, 0, -1), None)
  assert_eq(
    local_finalization_round_bound(2147483647, 0, 0, 0),
    Some(2147483647),
  )
  assert_eq(
    local_finalization_round_bound(0, 2147483647, 2147483647, 0),
    Some(2147483647),
  )
}

///|
test "finalization scheduling is same original prepared DATA without a new admission" {
  let prepared = source_free_requirements_prepared()
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let requirements = prepare_source_free_local_requirements(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let before = requirements.maximum_limits()
  let original_plan = requirements.capacity_plan
  let rounds = requirements.finalization_round_limit(prepared).unwrap()
  assert_true(rounds > 1000)
  assert_true(rounds.to_int64() > original_plan.execution.max_work.to_int64())
  assert_eq(requirements.maximum_limits(), before)
  assert_true(physical_equal(requirements.capacity_plan, original_plan))
  let equal = source_free_requirements_prepared()
  assert_true(requirements.finalization_round_limit(equal) is None)
}
