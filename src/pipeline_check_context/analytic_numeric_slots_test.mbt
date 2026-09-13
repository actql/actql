///|
test "analytic numeric templates retain exact frame calls without closing observations" {
  let profiles = resolution_profiles(
    operation_order_fixture(
      scalar_steps(
        "{\"analytic\":{\"partition_by\":[\"id\",\"id\"],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"},\"functions\":{\"a\":{\"fn\":\"sum\",\"expr\":\"id / 0\",\"filter\":\"FALSE\"},\"b\":{\"fn\":\"avg\",\"field\":\"id\",\"distinct\":true},\"c\":{\"fn\":\"count\",\"field\":\"id\"}}}}",
      ),
    ),
  )
  let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
  let requirements = operation_resolution_requirements(index)
  let profile = numeric_profile_fixture()
  let slots = prepare_program_analytic_numeric_slots(
    requirements, profile, 10000000, 100,
  ).unwrap()
  assert_eq(analytic_numeric_slot_count(slots), 6)
  assert_true(
    physical_equal(analytic_numeric_slots_requirements(slots), requirements),
  )
  for i in 0..<analytic_numeric_slot_count(slots) {
    let slot = analytic_numeric_slot_at(slots, i).unwrap()
    assert_true(physical_equal(slot.profile, profile))
    assert_true(
      physical_equal(
        slot.frame_call,
        @relation.analytic_call_for_validation(slot.analytic, slot.site.index).unwrap(),
      ),
    )
    guard slot.frame_call.function is @relation.Aggregate(call) else {
      fail("not aggregate")
    }
    assert_true(physical_equal(call, slot.call))
    assert_eq(slot.step.input, Some(slot.input))
    assert_true(
      operation_resolution_at(index, slot.requirement_index) is Some(Unresolved),
    )
    assert_true(slot.frame_call.name == "a" || slot.frame_call.name == "b")
  }
  let work = analytic_numeric_slots_work(slots)
  let linked = link_program_analytic_numeric_slots(index, slots, 10000000, 6).unwrap()
  assert_eq(
    operation_resolution_unresolved_count(linked),
    operation_resolution_unresolved_count(index) - 6,
  )
  for i in 0..<analytic_numeric_slot_count(slots) {
    let slot = analytic_numeric_slot_at(slots, i).unwrap()
    guard operation_resolution_at(linked, slot.requirement_index)
      is Some(Execution(AnalyticExecution(check))) &&
      check.rule is CaptureNumericObservation(retained) else {
      fail("missing numeric requirement")
    }
    assert_true(physical_equal(retained, slot))
    assert_true(physical_equal(check.analytic, slot.analytic))
    assert_true(physical_equal(check.site, slot.site))
    assert_eq(
      operation_execution_phase(AnalyticExecution(check)),
      BeforeOperationOutput,
    )
    assert_eq(
      operation_execution_failure(AnalyticExecution(check)),
      RejectOperationOutput,
    )
  }
  let linked_work = operation_resolution_work(linked)
  assert_true(
    link_program_analytic_numeric_slots(index, slots, linked_work, 6) is Ok(_),
  )
  assert_true(
    link_program_analytic_numeric_slots(index, slots, linked_work - 1, 6)
    is Err(BudgetExceeded),
  )
  assert_true(
    link_program_analytic_numeric_slots(index, slots, linked_work, 5)
    is Err(BudgetExceeded),
  )
  assert_true(
    link_program_analytic_numeric_slots(linked, slots, 10000000, 6)
    is Err(ForeignOccurrence(_)),
  )
  let foreign = index_program_operation_resolutions(
    resolution_profiles(
      operation_order_fixture(
        "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}}]",
      ),
    ),
    10000000,
    1000,
  ).unwrap()
  assert_true(
    link_program_analytic_numeric_slots(foreign, slots, 10000000, 6)
    is Err(ForeignOccurrence(-1)),
  )
  assert_true(
    prepare_program_analytic_numeric_slots(requirements, profile, work, 6)
    is Ok(_),
  )
  assert_true(
    prepare_program_analytic_numeric_slots(requirements, profile, work - 1, 6)
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_program_analytic_numeric_slots(requirements, profile, work, 5)
    is Err(BudgetExceeded),
  )
  assert_true(analytic_numeric_slot_at(slots, -1) is None)
  assert_true(analytic_numeric_slot_at(slots, 6) is None)
  assert_true(
    prepare_program_numeric_slots(requirements, profile, work, 6)
    is Err(UnsupportedOccurrence(_)),
  )
}
