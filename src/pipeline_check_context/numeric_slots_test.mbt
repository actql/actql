///|
test "numeric slots retain exact demand and add contracts only to owning stages" {
  let profiles = resolution_profiles(
    operation_order_fixture(
      "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}},{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"a\":{\"fn\":\"sum\",\"field\":\"id\",\"filter\":\"FALSE\"},\"b\":{\"fn\":\"avg\",\"field\":\"id\",\"distinct\":true}}}}]",
    ),
  )
  let index = index_program_operation_resolutions(profiles, 10000000, 100).unwrap()
  let requirements = operation_resolution_requirements(index)
  let profile = numeric_profile_fixture()
  let slots = prepare_program_numeric_slots(
    requirements, profile, 10000000, 100,
  ).unwrap()
  assert_eq(numeric_slot_count(slots), 6)
  assert_true(physical_equal(numeric_slots_requirements(slots), requirements))
  for i in 0..<numeric_slot_count(slots) {
    let slot = numeric_slot_at(slots, i).unwrap()
    assert_true(physical_equal(slot.profile, profile))
    assert_true(
      physical_equal(
        slot.call,
        @relation.aggregate_for_validation(slot.group, slot.site.index).unwrap(),
      ),
    )
    assert_eq(slot.step.input, Some(slot.input))
  }
  assert_true(
    close_program_operations(index, 10000000, 100)
    is Err(IncompleteResolution(_)),
  )
  let work = numeric_slots_work(slots)
  assert_true(
    prepare_program_numeric_slots(requirements, profile, work, 6) is Ok(_),
  )
  assert_true(
    prepare_program_numeric_slots(requirements, profile, work - 1, 6)
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_program_numeric_slots(requirements, profile, work, 5)
    is Err(BudgetExceeded),
  )
  assert_true(numeric_slot_at(slots, -1) is None)
  let identity = expression_closure_identity(
    operation_requirements_expressions(requirements),
  )
  let limits : CoreContractLimits = {
    max_work: 10000000,
    max_roots: 1000,
    max_bodies: 100,
    max_edges: 1000,
  }
  let base = collect_core_contracts(identity, limits).unwrap()
  let contracts = collect_core_contracts(
    identity,
    limits,
    numeric_slots=Some(slots),
  ).unwrap()
  assert_true(
    physical_equal(core_contract_numeric_slots(contracts).unwrap(), slots),
  )
  assert_eq(
    core_contract_body_count(contracts),
    core_contract_body_count(base) + 6,
  )
  let mut roots = 0
  for i in 0..<core_contract_root_count(contracts) {
    let root = core_contract_root_at(contracts, i).unwrap()
    if root.site is NumericAggregateProfile(stage, visit, _, _) {
      roots += 1
      assert_eq(
        program_identity_producer_is_local(identity, stage, visit),
        Some(true),
      )
      assert_eq(core_contract_cid(root.body), @numeric.cid(profile))
    }
  }
  // Two local visits own two calls each; the imported visit adds no local root.
  assert_eq(roots, 4)
  let (total_work, _) = core_contract_usage(contracts)
  assert_true(
    collect_core_contracts(
      identity,
      { ..limits, max_work: total_work, },
      numeric_slots=Some(slots),
    )
    is Ok(_),
  )
  assert_true(
    collect_core_contracts(
      identity,
      { ..limits, max_work: total_work - 1, },
      numeric_slots=Some(slots),
    )
    is Err(BudgetExceeded),
  )
  let (other, _, _) = prepared_identity_fixture()
  assert_true(
    collect_core_contracts(other, limits, numeric_slots=Some(slots))
    is Err(ForeignNumericSlots),
  )
}
