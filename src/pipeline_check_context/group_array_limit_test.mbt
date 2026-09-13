///|
test "array aggregate limits select owned Host and literal or bound guards" {
  for
    guard_text in ["", ",\"max_items\":1", ",\"max_items\":{\"$param\":\"n\"}"] {
    let profiles = resolution_profiles(
      operation_order_fixture(
        "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}},{\"assert_rows\":{\"unique_by\":[\"id\"]}},{\"group\":{\"by\":[],\"aggregates\":{\"a\":{\"fn\":\"array_agg\",\"field\":\"id\",\"order_by\":[{\"id\":\"asc\"}]" +
        guard_text +
        "}}}}]",
      ),
    )
    let owner = index_program_operation_resolutions(profiles, 10000000, 100).unwrap()
    let mut found = 0
    for i in 0..<operation_resolution_count(owner) {
      let site = operation_requirements_at(
        operation_resolution_requirements(owner),
        i,
      ).unwrap()
      if site.requirement is @pipeline.RelationRequirement(p) &&
        p.kind is @relation.AggregateEnvelope {
        let limit = select_group_array_limit(owner, i, 10000000, 100).unwrap()
        assert_true(physical_equal(group_array_limit_owner(limit), owner))
        assert_eq(group_array_limit_requirement(limit), i)
        assert_eq(
          group_array_limit_input_law(limit),
          "actql.bound.array-aggregate-input",
        )
        if guard_text.contains("$param") {
          let resolution = group_array_limit_guard_resolution(limit).unwrap()
          assert_true(physical_equal(resolution.site.pipeline, site.pipeline))
          assert_eq(resolution.site.stage, site.stage)
          assert_eq(resolution.site.producer_visit, site.producer_visit)
          assert_true(resolution.value is Integer(1L))
        } else {
          assert_true(group_array_limit_guard_resolution(limit) is None)
        }
        assert_eq(@relation.aggregate_name(group_array_limit_call(limit)), "a")
        let host = @policy.ceiling_value(group_array_limit_host(limit))
        let expected = if guard_text == "" {
          host
        } else {
          Int64::min(host, 1L)
        }
        assert_eq(group_array_limit_maximum(limit), expected)
        assert_eq(
          group_array_limit_guard(limit),
          if guard_text == "" {
            None
          } else {
            Some(1L)
          },
        )
        let work = group_array_limit_work(limit)
        assert_true(select_group_array_limit(owner, i, work, 100) is Ok(_))
        assert_true(
          select_group_array_limit(owner, i, work - 1, 100)
          is Err(BudgetExceeded),
        )
        assert_true(
          select_group_array_limit(owner, i, work, 0) is Err(InvalidLimits),
        )
        if guard_text != "" {
          assert_true(
            select_group_array_limit(owner, i, 10000000, 1)
            is Err(BudgetExceeded),
          )
        }
        assert_true(operation_resolution_at(owner, i) is Some(Unresolved))
        found += 1
      }
    }
    assert_true(found > 0)
    assert_true(
      select_group_array_limit(owner, -1, 10000000, 100)
      is Err(InvalidRequirement),
    )
  }
}

///|
test "array aggregate selection retains Program input bounds after sparse Host slots" {
  for aggregate_items in [1, 2] {
    for host_first in [false, true] {
      let owner = join_resolution_fixture(
        array_group=true,
        aggregate_items~,
        host_first~,
      )
      let mut found = 0
      for i in 0..<operation_resolution_count(owner) {
        let site = operation_requirements_at(
          operation_resolution_requirements(owner),
          i,
        ).unwrap()
        if site.requirement is @pipeline.RelationRequirement(p) &&
          p.kind is @relation.AggregateEnvelope {
          let limit = select_group_array_limit(owner, i, 10000000, 10).unwrap()
          assert_eq(group_array_limit_maximum(limit), 1L)
          assert_eq(group_array_limit_guard(limit), Some(3L))
          assert_eq(
            @policy.ceiling_value(group_array_limit_host(limit)),
            aggregate_items.to_int64(),
          )
          assert_eq(group_array_limit_candidate_count(limit), 1)
          let membership = group_array_limit_candidate_at(limit, 0).unwrap()
          let claim = if host_first { 1 } else { 0 }
          assert_eq(
            @capacity.target_membership_coordinates(membership),
            (0, claim, 0),
          )
          assert_true(
            @capacity.bind_target_membership(
              @capacity.target_membership_closure(membership),
              @capacity.target_membership_rows(membership),
              0,
              1 - claim,
            )
            is Err(_),
          )
          let work = group_array_limit_work(limit)
          assert_true(select_group_array_limit(owner, i, work, 3) is Ok(_))
          assert_true(
            select_group_array_limit(owner, i, work - 1, 3)
            is Err(BudgetExceeded),
          )
          assert_true(
            select_group_array_limit(owner, i, work, 2) is Err(BudgetExceeded),
          )
          assert_true(group_array_limit_candidate_at(limit, -1) is None)
          assert_true(group_array_limit_candidate_at(limit, 1) is None)
          found += 1
        }
      }
      assert_eq(found, 1)
    }
  }
}
