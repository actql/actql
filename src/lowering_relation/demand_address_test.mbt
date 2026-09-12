///|
test "fragment demand addresses use root slots and semantic source paths" {
  let expr = "{\"if\":[{\"literal\":true},{\"coalesce\":[{\"literal\":null},{\"literal\":7}]},{\"literal\":9}]}"
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(",{\"derive\":{\"/\":" + expr + ",\"a\":" + expr + "}}"),
    sequence_limits(),
  ).unwrap()
  let roots = @lowering_relation.prepare_roots(sequence, root_limits()).unwrap()
  let index = @lowering_relation.prepare_demand(roots, demand_limits()).unwrap()
  assert_eq(
    @lowering_relation.root_at(roots, 0).unwrap().parameter_pointer,
    "/exprs/a",
  )
  assert_eq(
    @lowering_relation.root_at(roots, 1).unwrap().parameter_pointer,
    "/exprs/~1",
  )
  for r in 0..<2 {
    let paths = @lowering_relation.demand_root_at(index, r).unwrap()
    let node = demand_node(paths, "/if/1/coalesce/1")
    let prefix = "/roots/" + r.to_string() + "/source"
    assert_eq(
      @lowering_relation.demand_source_pointer(index, r, node, max_bytes=100).unwrap(),
      Some(prefix + "/if/1/coalesce/1"),
    )
    let tests = @lowering_relation.demand_source_tests(
      index,
      r,
      node,
      max_tests=2,
      max_pointer_bytes=100,
    ).unwrap()
    assert_eq(tests.length(), 2)
    assert_eq(tests[0].pointer, prefix + "/if/0")
    assert_eq(tests[0].predicate, @typing.IsTrue)
    assert_eq(tests[1].pointer, prefix + "/if/1/coalesce/0")
    assert_eq(tests[1].predicate, @typing.IsNull)
  }
}

///|
test "fragment implicit else has demand but no source address" {
  let roots = demand_roots_for(
    "{\"case\":{\"when\":[{\"when\":{\"literal\":true},\"then\":{\"literal\":1}}]}}",
  )
  let index = @lowering_relation.prepare_demand(roots, demand_limits()).unwrap()
  let paths = @lowering_relation.demand_root_at(index, 0).unwrap()
  let last = @typing.node_count(@typing.demand_expression(paths)) - 1
  assert_eq(
    @lowering_relation.demand_source_pointer(index, 0, last, max_bytes=0).unwrap(),
    None,
  )
  let tests = @lowering_relation.demand_source_tests(
    index,
    0,
    last,
    max_tests=1,
    max_pointer_bytes=100,
  ).unwrap()
  assert_eq(tests.length(), 1)
  assert_eq(tests[0].pointer, "/roots/0/source/case/when/0/when")
  assert_eq(tests[0].predicate, @typing.NotTrue)
}

///|
test "fragment address budgets are cumulative and detached with invalid indices rejected" {
  let roots = demand_roots_for(
    "{\"if\":[{\"literal\":true},{\"coalesce\":[{\"literal\":null},{\"literal\":7}]},{\"literal\":9}]}",
  )
  let index = @lowering_relation.prepare_demand(roots, demand_limits()).unwrap()
  let paths = @lowering_relation.demand_root_at(index, 0).unwrap()
  let node = demand_node(paths, "/if/1/coalesce/1")
  // ASCII fixture: pointer lengths are exact UTF-8 byte counts.
  let size = "/roots/0/source/if/0".length() +
    "/roots/0/source/if/1/coalesce/0".length()
  let tests = @lowering_relation.demand_source_tests(
    index,
    0,
    node,
    max_tests=2,
    max_pointer_bytes=size,
  ).unwrap()
  assert_true(
    @lowering_relation.demand_source_tests(
      index,
      0,
      node,
      max_tests=2,
      max_pointer_bytes=size - 1,
    )
    is Err(@lowering_relation.AddressLimit),
  )
  assert_true(
    @lowering_relation.demand_source_tests(
      index,
      0,
      node,
      max_tests=1,
      max_pointer_bytes=size,
    )
    is Err(@lowering_relation.AddressLimit),
  )
  tests.clear()
  assert_eq(
    @lowering_relation.demand_source_tests(
      index,
      0,
      node,
      max_tests=2,
      max_pointer_bytes=size,
    )
    .unwrap()
    .length(),
    2,
  )
  let pointer_size = "/roots/0/source/if/1/coalesce/1".length()
  assert_true(
    @lowering_relation.demand_source_pointer(
      index,
      0,
      node,
      max_bytes=pointer_size,
    )
    is Ok(Some(_)),
  )
  assert_true(
    @lowering_relation.demand_source_pointer(
      index,
      0,
      node,
      max_bytes=pointer_size - 1,
    )
    is Err(@lowering_relation.AddressLimit),
  )
  assert_true(
    @lowering_relation.demand_source_pointer(index, -1, node, max_bytes=100)
    is Err(@lowering_relation.InvalidRoot),
  )
  assert_true(
    @lowering_relation.demand_source_pointer(index, 1, node, max_bytes=100)
    is Err(@lowering_relation.InvalidRoot),
  )
  assert_true(
    @lowering_relation.demand_source_pointer(index, 0, -1, max_bytes=100)
    is Err(@lowering_relation.InvalidNode),
  )
  assert_true(
    @lowering_relation.demand_source_pointer(index, 0, node, max_bytes=-1)
    is Err(@lowering_relation.InvalidAddressLimits),
  )
  assert_true(
    @lowering_relation.demand_source_tests(
      index,
      0,
      node,
      max_tests=-1,
      max_pointer_bytes=100,
    )
    is Err(@lowering_relation.InvalidAddressLimits),
  )
}
