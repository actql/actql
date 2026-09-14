///|
test "nest item selection includes sparse child proof slots without changing guard scope" {
  for host_first in [false, true] {
    let owner = join_resolution_fixture(
      nest_items=true,
      aggregate_items=5,
      host_first~,
    )
    let mut found = 0
    for i in 0..<operation_resolution_count(owner) {
      let site = operation_requirements_at(
        operation_resolution_requirements(owner),
        i,
      ).unwrap()
      guard site.requirement is @pipeline.NestRequirement(ResolveItemLimit) else {
        continue
      }
      let limit = select_nest_item_limit(owner, i, 10000000, 3).unwrap()
      assert_eq(limit.maximum, 1L)
      assert_eq(limit.guard_value, Some(3L))
      assert_eq(@policy.ceiling_value(limit.host), 5L)
      assert_eq(nest_item_candidate_count(limit), 1)
      let candidate = nest_item_candidate_at(limit, 0).unwrap()
      assert_eq(
        @capacity.target_membership_coordinates(candidate),
        (0, if host_first { 1 } else { 0 }, 0),
      )
      assert_true(select_nest_item_limit(owner, i, limit.work, 3) is Ok(_))
      assert_true(
        select_nest_item_limit(owner, i, limit.work - 1, 3)
        is Err(BudgetExceeded),
      )
      assert_true(
        select_nest_item_limit(owner, i, limit.work, 2) is Err(BudgetExceeded),
      )
      found += 1
    }
    assert_eq(found, 1)
  }
}

///|
test "nest item selection retains Host and bound guards at each producer visit" {
  for
    guard_text in ["", ",\"max_items\":3", ",\"max_items\":{\"$param\":\"n\"}"] {
    let owner = index_program_operation_resolutions(
      resolution_profiles(
        operation_order_fixture(
          "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}},{\"distinct\":[\"id\"],\"as\":\"keyed\"},{\"nest\":{\"with\":\"keyed\",\"on\":[{\"left\":\"id\",\"right\":\"id\"},{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"id\"]" +
          guard_text +
          "}}]",
        ),
      ),
      10000000,
      100,
    ).unwrap()
    let mut found = 0
    for i in 0..<operation_resolution_count(owner) {
      let site = operation_requirements_at(
        operation_resolution_requirements(owner),
        i,
      ).unwrap()
      guard site.requirement is @pipeline.NestRequirement(ResolveItemLimit) else {
        continue
      }
      let value = select_nest_item_limit(owner, i, 10000000, 100).unwrap()
      assert_true(physical_equal(value.owner, owner))
      assert_true(physical_equal(value.site, site))
      assert_eq(value.requirement, i)
      assert_eq(value.child, @pipeline.Step(1))
      let expected_guard = if guard_text == "" {
        None
      } else if guard_text.contains("$param") {
        Some(1L)
      } else {
        Some(3L)
      }
      assert_eq(value.guard_value, expected_guard)
      let host = @policy.ceiling_value(value.host)
      assert_eq(
        value.maximum,
        expected_guard.map(n => Int64::min(n, host)).unwrap_or(host),
      )
      assert_eq(nest_item_candidate_count(value), 0)
      assert_true(nest_item_candidate_at(value, -1) is None)
      assert_true(nest_item_candidate_at(value, 0) is None)
      if guard_text.contains("$param") {
        let scalar = value.guard_resolution.unwrap()
        assert_eq(scalar.site.stage, site.stage)
        assert_eq(scalar.site.producer_visit, site.producer_visit)
        assert_true(physical_equal(scalar.site.pipeline, site.pipeline))
        assert_eq(scalar.value, Integer(1L))
      } else {
        assert_true(value.guard_resolution is None)
      }
      let count = if expected_guard is Some(_) { 2 } else { 1 }
      assert_true(select_nest_item_limit(owner, i, value.work, count) is Ok(_))
      assert_true(
        select_nest_item_limit(owner, i, value.work - 1, count)
        is Err(BudgetExceeded),
      )
      if count == 2 {
        assert_true(
          select_nest_item_limit(owner, i, value.work, 1) is Err(BudgetExceeded),
        )
      }
      assert_true(operation_resolution_at(owner, i) is Some(Unresolved))
      found += 1
    }
    assert_eq(found, 3)
    let linked = link_program_nest_item_limits(owner, 10000000, 3, 100).unwrap()
    let mut links = 0
    for i in 0..<operation_resolution_count(linked) {
      if operation_resolution_at(linked, i) is Some(Execution(NestItems(limit))) {
        links += 1
        assert_eq(limit.requirement, i)
        assert_true(physical_equal(limit.owner, owner))
        assert_eq(
          operation_execution_phase(NestItems(limit)),
          BeforeOperationOutput,
        )
        assert_eq(
          operation_execution_failure(NestItems(limit)),
          RejectOperationOutput,
        )
      }
    }
    assert_eq(links, 3)
    assert_true(
      link_program_nest_item_limits(owner, 10000000, 2, 100)
      is Err(BudgetExceeded),
    )
    assert_true(
      link_program_nest_item_limits(linked, 10000000, 3, 100)
      is Err(ForeignEvidence),
    )
    assert_true(
      select_nest_item_limit(owner, -1, 10000000, 100)
      is Err(InvalidRequirement),
    )
  }
}
