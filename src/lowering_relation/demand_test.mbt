///|
fn demand_limits() -> @lowering_relation.DemandLimits {
  {
    max_entries: 1000,
    max_conditions: 1000,
    max_pending: 1000,
    max_work: 10000,
  }
}

///|
fn demand_roots_for(expr : String) -> @lowering_relation.RootIndex {
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(",{\"derive\":{\"out\":" + expr + "}}"),
    sequence_limits(),
  ).unwrap()
  @lowering_relation.prepare_roots(sequence, root_limits()).unwrap()
}

///|
fn condition_path(
  index : @lowering_relation.DemandIndex,
  entry : Int,
) -> Array[(Int, @lowering_relation.DemandTest)] {
  let result = []
  let mut next = @lowering_relation.demand_entry_at(index, entry).unwrap().condition
  while next is Some(i) {
    let c = @lowering_relation.demand_condition_at(index, i).unwrap()
    result.push((c.entry, c.predicate))
    next = c.previous
  }
  Array::makei(result.length(), i => result[result.length() - i - 1])
}

///|
test "nested IF and coalesce inherit occurrence-bound conditions without evaluation" {
  let roots = demand_roots_for(
    "{\"if\":[{\"eq\":[{\"field\":\"id\"},{\"literal\":1}]},{\"coalesce\":[{\"nullif\":[{\"field\":\"id\"},{\"literal\":1}]},{\"literal\":7}]},{\"literal\":9}]}",
  )
  let index = @lowering_relation.prepare_demand(roots, demand_limits()).unwrap()
  assert_true(physical_equal(@lowering_relation.demand_roots(index), roots))
  assert_true(
    physical_equal(
      @lowering_relation.demand_entry_at(index, 0).unwrap().expression,
      @lowering_relation.root_at(roots, 0).unwrap().expression,
    ),
  )
  assert_eq(@lowering_relation.demand_entry_count(index), 10)
  assert_eq(@lowering_relation.demand_condition_count(index), 3)
  assert_eq(@lowering_relation.demand_entry_at(index, 0).unwrap().parent, None)
  assert_eq(
    @lowering_relation.demand_entry_at(index, 7).unwrap().parent,
    Some((2, 1)),
  )
  assert_eq(
    @lowering_relation.demand_entry_at(index, 8).unwrap().parent,
    Some((6, 0)),
  )
  assert_eq(condition_path(index, 1), [])
  assert_eq(condition_path(index, 2), [(1, @lowering_relation.True)])
  assert_eq(condition_path(index, 3), [(1, @lowering_relation.NotTrue)])
  assert_eq(condition_path(index, 4), [])
  assert_eq(condition_path(index, 7), [
    (1, @lowering_relation.True),
    (6, @lowering_relation.Null),
  ])
  assert_eq(condition_path(index, 8), [(1, @lowering_relation.True)])
  assert_eq(
    expression_wire(
      @lowering_relation.demand_entry_at(index, 7).unwrap().expression,
    ),
    "{\"body\":7,\"op\":\"literal\"}",
  )
}

///|
test "CASE records earlier not-true conditions before own true and implicit else" {
  let roots = demand_roots_for(
    "{\"case\":{\"when\":[{\"when\":{\"literal\":false},\"then\":{\"literal\":1}},{\"when\":{\"literal\":true},\"then\":{\"literal\":2}}]}}",
  )
  let index = @lowering_relation.prepare_demand(roots, demand_limits()).unwrap()
  assert_eq(@lowering_relation.demand_entry_count(index), 6)
  assert_eq(
    @lowering_relation.demand_entry_at(index, 5).unwrap().parent,
    Some((0, 4)),
  )
  assert_eq(condition_path(index, 1), [])
  assert_eq(condition_path(index, 2), [(1, @lowering_relation.True)])
  assert_eq(condition_path(index, 3), [(1, @lowering_relation.NotTrue)])
  assert_eq(condition_path(index, 4), [
    (1, @lowering_relation.NotTrue),
    (3, @lowering_relation.True),
  ])
  assert_eq(condition_path(index, 5), [
    (1, @lowering_relation.NotTrue),
    (3, @lowering_relation.NotTrue),
  ])
  assert_true(
    @lowering_relation.expression_body(
      @lowering_relation.demand_entry_at(index, 5).unwrap().expression,
    )
    is @lowering_relation.TypedNull,
  )
}

///|
test "eager boolean operands add no short-circuit demand and literals remain opaque" {
  for
    expr in [
      "{\"and\":[{\"literal\":false},{\"literal\":true}]}", "{\"or\":[{\"literal\":true},{\"literal\":false}]}",
    ] {
    let index = @lowering_relation.prepare_demand(
      demand_roots_for(expr),
      demand_limits(),
    ).unwrap()
    assert_eq(@lowering_relation.demand_entry_count(index), 3)
    assert_eq(@lowering_relation.demand_condition_count(index), 0)
    for i in 0..<3 {
      assert_eq(condition_path(index, i), [])
    }
  }
  let index = @lowering_relation.prepare_demand(
    demand_roots_for(
      "{\"literal\":{\"if\":[true,1,2],\"$param\":\"business\"}}",
    ),
    demand_limits(),
  ).unwrap()
  assert_eq(@lowering_relation.demand_entry_count(index), 1)
  assert_eq(@lowering_relation.demand_condition_count(index), 0)
}

///|
test "demand preparation enforces exact cumulative limits and is retryable" {
  let roots = demand_roots_for(
    "{\"if\":[{\"literal\":true},{\"literal\":1},{\"literal\":2}]}",
  )
  let exact : @lowering_relation.DemandLimits = {
    max_entries: 4,
    max_conditions: 2,
    max_pending: 3,
    max_work: 13,
  }
  for
    limits in [
      { ..exact, max_entries: 3, },
      { ..exact, max_conditions: 1, },
      { ..exact, max_pending: 2, },
      { ..exact, max_work: 12, },
    ] {
    assert_true(
      @lowering_relation.prepare_demand(roots, limits)
      is Err(@lowering_relation.DemandLimit),
    )
  }
  assert_true(@lowering_relation.prepare_demand(roots, exact) is Ok(_))
  assert_true(
    @lowering_relation.prepare_demand(roots, { ..exact, max_pending: -1, })
    is Err(@lowering_relation.InvalidDemandLimits),
  )
}

///|
test "separate roots share budgets but never inherit each other's condition frame" {
  let expr = "{\"if\":[{\"literal\":true},{\"literal\":1},{\"literal\":2}]}"
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(",{\"derive\":{\"x\":" + expr + ",\"y\":" + expr + "}}"),
    sequence_limits(),
  ).unwrap()
  let roots = @lowering_relation.prepare_roots(sequence, root_limits()).unwrap()
  let limits : @lowering_relation.DemandLimits = {
    max_entries: 8,
    max_conditions: 4,
    max_pending: 3,
    max_work: 26,
  }
  let index = @lowering_relation.prepare_demand(roots, limits).unwrap()
  assert_eq(@lowering_relation.demand_entry_count(index), 8)
  assert_eq(@lowering_relation.demand_entry_at(index, 4).unwrap().root_index, 1)
  assert_eq(condition_path(index, 4), [])
  assert_eq(condition_path(index, 6), [(5, @lowering_relation.True)])
  assert_eq(condition_path(index, 7), [(5, @lowering_relation.NotTrue)])
  assert_true(
    @lowering_relation.prepare_demand(roots, { ..limits, max_work: 25, })
    is Err(@lowering_relation.DemandLimit),
  )
}
