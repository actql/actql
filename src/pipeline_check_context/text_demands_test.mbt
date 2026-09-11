///|
fn consumer_bounds(steps : String) -> TextBoundsChecks {
  let (context, capacity) = selected_fixture(
    false,
    profile=bound_profile(),
    steps=Some(steps),
  )
  let selected = bind_capacity_policy(
    context,
    capacity,
    max_work=1000000,
    max_text_bytes=1000000,
    max_policy_nodes=100,
  ).unwrap()
  let validation = prepare_expression_validation(selected, validation_limits()).unwrap()
  check_text_bounds(
    check_patterns(validation, pattern_limits()).unwrap(),
    bound_limits(),
  ).unwrap()
}

///|
test "analytic aggregate filters precede coalesce demand but do not mask navigation" {
  let checked = consumer_bounds(
    (
      #|[{"distinct":true},{"analytic":{"partition_by":[],"order_by":[{"id":"asc"}],"frame":{"start":"current_row","end":"current_row"},"functions":{"a":{"fn":"sum","expr":"coalesce(try_number('1'), try_number('2'))","filter":"CAST(NULL AS BOOLEAN)"},"b":{"fn":"lag","expr":"try_number('3')"}}}}]
    ),
  )
  assert_eq(text_bound_count(checked), 9)
  for i in 0..<text_bound_count(checked) {
    let entry = text_bound_at(checked, i).unwrap()
    let req = validation_site_requirement(text_bound_site(entry))
    let tests = text_bound_demand_tests(entry, max_tests=2).unwrap()
    if req.consumer == @pipeline.AnalyticArgument("b") {
      assert_true(req.filter is None)
      assert_eq(tests.length(), 0)
    } else {
      assert_eq(req.consumer, @pipeline.AnalyticArgument("a"))
      assert_eq(tests[0].slot, req.filter.unwrap().slot)
      assert_eq(tests[0].kind, @typing.IsTrue)
      assert_true(
        @typing.node_at(tests[0].expression, 0).unwrap().contract.nullable,
      )
      if i % 3 == 1 {
        assert_eq(tests.length(), 2)
        assert_eq(tests[1].kind, @typing.IsNull)
        assert_eq(tests[1].slot, req.slot)
        assert_eq(
          @typing.demand_pointer(
            text_bound_demands(entry),
            tests[1].node_index,
            max_bytes=100,
          ).unwrap(),
          Some("/coalesce/0"),
        )
      } else {
        assert_eq(tests.length(), 1)
      }
    }
  }
}

///|
test "aggregate demand prefixes retain their own filter before local branches" {
  let checked = consumer_bounds(
    (
      #|[{"group":{"by":["id"],"aggregates":{"a":{"fn":"sum","expr":"if(id > 1, try_number('1'), try_number('2'))","filter":"id > 0"},"b":{"fn":"sum","expr":"try_number('3')","filter":"id > 0"}}}}]
    ),
  )
  assert_eq(text_bound_count(checked), 9)
  for i in 0..<text_bound_count(checked) {
    let entry = text_bound_at(checked, i).unwrap()
    let req = validation_site_requirement(text_bound_site(entry))
    let count = if req.consumer == @pipeline.AggregateArgument("a") {
      2
    } else {
      1
    }
    let tests = text_bound_demand_tests(entry, max_tests=count).unwrap()
    assert_eq(tests.length(), count)
    assert_eq(tests[0].slot, req.filter.unwrap().slot)
    assert_eq(tests[0].node_index, 0)
    assert_eq(tests[0].kind, @typing.IsTrue)
    assert_true(
      physical_equal(tests[0].expression, req.filter.unwrap().expression),
    )
    assert_true(tests[0].slot < req.slot)
    if count == 2 {
      assert_eq(tests[1].slot, req.slot)
      assert_true(physical_equal(tests[1].expression, req.expression))
      assert_eq(
        @typing.demand_pointer(
          text_bound_demands(entry),
          tests[1].node_index,
          max_bytes=100,
        ).unwrap(),
        Some("/if/0"),
      )
      assert_eq(
        tests[1].kind,
        if i % 3 == 0 {
          @typing.IsTrue
        } else {
          @typing.NotTrue
        },
      )
    }
    assert_true(
      text_bound_demand_tests(entry, max_tests=count - 1)
      is Err(@typing.BudgetExceeded),
    )
    assert_true(
      text_bound_demand_tests(entry, max_tests=-1) is Err(@typing.InvalidLimits),
    )
    tests.clear()
    assert_eq(
      text_bound_demand_tests(entry, max_tests=count).unwrap().length(),
      count,
    )
  }
  let a = text_bound_demand_tests(
      text_bound_at(checked, 0).unwrap(),
      max_tests=2,
    ).unwrap()[0]
  let b = text_bound_demand_tests(
      text_bound_at(checked, 2).unwrap(),
      max_tests=1,
    ).unwrap()[0]
  assert_true(a.slot != b.slot)
  assert_true(!physical_equal(a.expression, b.expression))
}

///|
test "filter evaluation does not depend on its own result and false filters are not folded" {
  let checked = consumer_bounds(
    (
      #|[{"group":{"by":["id"],"aggregates":{"a":{"fn":"sum","expr":"try_number('1')","filter":"if(id > 0, regex_match('x', 'x'), FALSE)"},"b":{"fn":"sum","expr":"try_number('2')","filter":"FALSE"}}}}]
    ),
  )
  assert_eq(text_bound_count(checked), 9)
  for i in 0..<text_bound_count(checked) {
    let entry = text_bound_at(checked, i).unwrap()
    let req = validation_site_requirement(text_bound_site(entry))
    let tests = text_bound_demand_tests(entry, max_tests=1).unwrap()
    assert_eq(tests.length(), 1)
    if req.consumer is @pipeline.AggregateFilter(_) {
      assert_true(req.filter is None)
      assert_eq(tests[0].slot, req.slot)
      assert_eq(
        @typing.demand_pointer(
          text_bound_demands(entry),
          tests[0].node_index,
          max_bytes=100,
        ).unwrap(),
        Some("/if/0"),
      )
    } else {
      assert_eq(tests[0].slot, req.filter.unwrap().slot)
      assert_eq(tests[0].node_index, 0)
    }
    assert_eq(tests[0].kind, @typing.IsTrue)
  }
  let plain = check_text_bounds(
    bound_fixture("try_number('1')"),
    bound_limits(),
  ).unwrap()
  assert_eq(
    text_bound_demand_tests(text_bound_at(plain, 0).unwrap(), max_tests=0)
    .unwrap()
    .length(),
    0,
  )
}
