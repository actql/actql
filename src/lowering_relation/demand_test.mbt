///|
fn demand_limits() -> @lowering_relation.DemandLimits {
  {
    max_roots: 100,
    max_nodes: 1000,
    max_work: 100000,
    max_text_bytes: 100000,
    max_links: 10000,
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
fn demand_node(paths : @typing.DemandPaths, pointer : String) -> Int raise {
  for i in 0..<@typing.node_count(@typing.demand_expression(paths)) {
    if @typing.demand_pointer(paths, i, max_bytes=10000).unwrap() ==
      Some(pointer) {
      return i
    }
  }
  fail("missing pointer " + pointer)
}

///|
fn assert_demand(
  paths : @typing.DemandPaths,
  pointer : String,
  expected : Array[(String, @typing.DemandTestKind)],
) -> Unit raise {
  let tests = @typing.demand_tests(
    paths,
    demand_node(paths, pointer),
    max_tests=100,
  ).unwrap()
  assert_eq(tests.length(), expected.length())
  for i in 0..<tests.length() {
    assert_eq(
      @typing.demand_pointer(paths, tests[i].node_index, max_bytes=10000).unwrap(),
      Some(expected[i].0),
    )
    assert_eq(tests[i].kind, expected[i].1)
  }
}

///|
test "shared nested demand preserves exact checked owner and fixed semantic paths" {
  let roots = demand_roots_for(
    "{\"if\":[{\"eq\":[{\"field\":\"id\"},{\"literal\":1}]},{\"coalesce\":[{\"nullif\":[{\"field\":\"id\"},{\"literal\":1}]},{\"literal\":7}]},{\"literal\":9}]}",
  )
  let index = @lowering_relation.prepare_demand(roots, demand_limits()).unwrap()
  let paths = @lowering_relation.demand_root_at(index, 0).unwrap()
  assert_true(physical_equal(@lowering_relation.demand_roots(index), roots))
  assert_true(
    physical_equal(
      @typing.demand_expression(paths),
      @lowering_relation.root_at(roots, 0).unwrap().typed_expression,
    ),
  )
  assert_eq(@typing.node_count(@typing.demand_expression(paths)), 10)
  assert_demand(paths, "/if/0", [])
  assert_demand(paths, "/if/1", [("/if/0", IsTrue)])
  assert_demand(paths, "/if/2", [("/if/0", NotTrue)])
  assert_demand(paths, "/if/0/eq/0", [])
  assert_demand(paths, "/if/1/coalesce/1", [
    ("/if/0", IsTrue),
    ("/if/1/coalesce/0", IsNull),
  ])
  assert_demand(paths, "/if/1/coalesce/0/nullif/0", [("/if/0", IsTrue)])
  assert_true(@lowering_relation.demand_root_at(index, -1) is None)
  assert_true(@lowering_relation.demand_root_at(index, 1) is None)
}

///|
test "shared CASE demand has no fabricated source for implicit else" {
  let roots = demand_roots_for(
    "{\"case\":{\"when\":[{\"when\":{\"literal\":false},\"then\":{\"literal\":1}},{\"when\":{\"literal\":true},\"then\":{\"literal\":2}}]}}",
  )
  let index = @lowering_relation.prepare_demand(roots, demand_limits()).unwrap()
  let paths = @lowering_relation.demand_root_at(index, 0).unwrap()
  let typed = @typing.demand_expression(paths)
  assert_eq(@typing.node_count(typed), 6)
  assert_demand(paths, "/case/when/0/when", [])
  assert_demand(paths, "/case/when/0/then", [("/case/when/0/when", IsTrue)])
  assert_demand(paths, "/case/when/1/when", [("/case/when/0/when", NotTrue)])
  assert_demand(paths, "/case/when/1/then", [
    ("/case/when/0/when", NotTrue),
    ("/case/when/1/when", IsTrue),
  ])
  let last = @typing.node_count(typed) - 1
  assert_true(@typing.node_form(typed, last) is Some(ImplicitNull))
  assert_eq(@typing.demand_pointer(paths, last, max_bytes=0).unwrap(), None)
  let tests = @typing.demand_tests(paths, last, max_tests=2).unwrap()
  assert_eq(tests.length(), 2)
  for i in 0..<2 {
    assert_eq(tests[i].kind, NotTrue)
    assert_eq(
      @typing.demand_pointer(paths, tests[i].node_index, max_bytes=100).unwrap(),
      Some("/case/when/" + i.to_string() + "/when"),
    )
  }
}

///|
test "shared demand preserves eager booleans and opaque literal data" {
  for
    expr in [
      "{\"and\":[{\"literal\":false},{\"literal\":true}]}", "{\"or\":[{\"literal\":true},{\"literal\":false}]}",
    ] {
    let index = @lowering_relation.prepare_demand(
      demand_roots_for(expr),
      demand_limits(),
    ).unwrap()
    let paths = @lowering_relation.demand_root_at(index, 0).unwrap()
    assert_eq(@typing.node_count(@typing.demand_expression(paths)), 3)
    for i in 0..<3 {
      assert_eq(@typing.demand_tests(paths, i, max_tests=0).unwrap(), [])
    }
  }
  let index = @lowering_relation.prepare_demand(
    demand_roots_for(
      "{\"literal\":{\"if\":[true,1,2],\"$param\":\"business\"}}",
    ),
    demand_limits(),
  ).unwrap()
  let paths = @lowering_relation.demand_root_at(index, 0).unwrap()
  assert_eq(@typing.node_count(@typing.demand_expression(paths)), 1)
  assert_demand(paths, "", [])
}

///|
fn exact_demand_limits(
  index : @lowering_relation.DemandIndex,
) -> @lowering_relation.DemandLimits {
  let u = @lowering_relation.demand_usage(index)
  {
    max_roots: u.roots,
    max_nodes: u.nodes,
    max_work: u.work,
    max_text_bytes: u.text_bytes,
    max_links: u.links,
  }
}

///|
test "shared demand wrapper enforces all cumulative budget axes and retry is clean" {
  let roots = demand_roots_for(
    "{\"if\":[{\"literal\":true},{\"literal\":1},{\"literal\":2}]}",
  )
  let index = @lowering_relation.prepare_demand(roots, demand_limits()).unwrap()
  let exact = exact_demand_limits(index)
  for
    short in [
      { ..exact, max_roots: exact.max_roots - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
      { ..exact, max_links: exact.max_links - 1, },
    ] {
    assert_true(
      @lowering_relation.prepare_demand(roots, short)
      is Err(@lowering_relation.DemandLimit),
    )
  }
  assert_true(@lowering_relation.prepare_demand(roots, exact) is Ok(_))
  assert_true(
    @lowering_relation.prepare_demand(roots, { ..exact, max_work: -1, })
    is Err(@lowering_relation.InvalidDemandLimits),
  )
  let paths = @lowering_relation.demand_root_at(index, 0).unwrap()
  let node = demand_node(paths, "/if/1")
  assert_true(
    @typing.demand_pointer(paths, node, max_bytes=4) is Err(BudgetExceeded),
  )
  assert_true(
    @typing.demand_tests(paths, node, max_tests=0) is Err(BudgetExceeded),
  )
  let copy = @typing.demand_tests(paths, node, max_tests=1).unwrap()
  copy.clear()
  assert_eq(@typing.demand_tests(paths, node, max_tests=1).unwrap().length(), 1)
}

///|
test "root budgets accumulate while typed condition frames stay separate" {
  let expr = "{\"if\":[{\"literal\":true},{\"literal\":1},{\"literal\":2}]}"
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(",{\"derive\":{\"x\":" + expr + ",\"y\":" + expr + "}}"),
    sequence_limits(),
  ).unwrap()
  let roots = @lowering_relation.prepare_roots(sequence, root_limits()).unwrap()
  let index = @lowering_relation.prepare_demand(roots, demand_limits()).unwrap()
  let exact = exact_demand_limits(index)
  assert_eq(exact.max_roots, 2)
  assert_eq(exact.max_nodes, 8)
  for r in 0..<2 {
    let paths = @lowering_relation.demand_root_at(index, r).unwrap()
    assert_true(
      physical_equal(
        @typing.demand_expression(paths),
        @lowering_relation.root_at(roots, r).unwrap().typed_expression,
      ),
    )
    assert_demand(paths, "", [])
    assert_demand(paths, "/if/1", [("/if/0", IsTrue)])
    assert_demand(paths, "/if/2", [("/if/0", NotTrue)])
  }
  let first = @typing.demand_usage(
    @lowering_relation.demand_root_at(index, 0).unwrap(),
  )
  assert_eq(exact.max_work, 2 + first.work * 2)
  assert_eq(exact.max_text_bytes, first.text_bytes * 2)
  assert_eq(exact.max_links, first.links * 2)
  assert_true(@lowering_relation.prepare_demand(roots, exact) is Ok(_))
  for
    short in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
      { ..exact, max_links: exact.max_links - 1, },
    ] {
    assert_true(
      @lowering_relation.prepare_demand(roots, short)
      is Err(@lowering_relation.DemandLimit),
    )
  }
}
