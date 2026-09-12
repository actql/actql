///|
test "kernel root scopes preserve original ownership and restart fragment root numbering" {
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(
      ",{\"derive\":{\"a\":\"if(TRUE, 1, 2)\"}},{\"filter\":\"if(TRUE, TRUE, FALSE)\"},{\"select\":[\"id\"]}",
    ),
    sequence_limits(),
  ).unwrap()
  let all = @lowering_relation.prepare_roots(sequence, root_limits()).unwrap()
  assert_eq(@lowering_relation.root_step_range(all), (0, 4))
  for step in [1, 2] {
    let scoped = @lowering_relation.prepare_kernel_roots(
      sequence,
      step,
      root_limits(),
    ).unwrap()
    assert_true(
      physical_equal(@lowering_relation.root_sequence(scoped), sequence),
    )
    assert_eq(@lowering_relation.root_step_range(scoped), (step, step + 1))
    assert_eq(@lowering_relation.root_count(scoped), 1)
    let root = @lowering_relation.root_at(scoped, 0).unwrap()
    let global = @lowering_relation.root_at(all, step - 1).unwrap()
    assert_eq(root.step_index, step)
    assert_eq(root.step_id, global.step_id)
    assert_true(physical_equal(root.expression, global.expression))
    assert_true(physical_equal(root.typed_expression, global.typed_expression))
    let demand = @lowering_relation.prepare_demand(scoped, demand_limits()).unwrap()
    let paths = @lowering_relation.demand_root_at(demand, 0).unwrap()
    let node = demand_node(paths, "/if/1")
    assert_eq(
      @lowering_relation.demand_source_pointer(demand, 0, node, max_bytes=100).unwrap(),
      Some("/roots/0/source/if/1"),
    )
    let tests = @lowering_relation.demand_source_tests(
      demand,
      0,
      node,
      max_tests=1,
      max_pointer_bytes=100,
    ).unwrap()
    assert_eq(tests[0].pointer, "/roots/0/source/if/0")
    assert_eq(tests[0].predicate, @typing.IsTrue)
  }
  assert_eq(@lowering_relation.sequence_count(sequence), 4)
}

///|
test "empty expression kernel keeps scope and nonexpression operations stay outside fragments" {
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(
      ",{\"derive\":{}},{\"derive\":{}},{\"select\":[\"id\"]}",
    ),
    sequence_limits(),
  ).unwrap()
  for step in [1, 2] {
    let scoped = @lowering_relation.prepare_kernel_roots(sequence, step, {
      max_roots: 0,
      max_pointer_bytes: 0,
      max_work: 1,
    }).unwrap()
    assert_eq(@lowering_relation.root_count(scoped), 0)
    assert_eq(@lowering_relation.root_step_range(scoped), (step, step + 1))
    assert_true(
      physical_equal(@lowering_relation.root_sequence(scoped), sequence),
    )
    assert_true(
      @lowering_relation.prepare_kernel_roots(sequence, step, {
        max_roots: 0,
        max_pointer_bytes: 0,
        max_work: 0,
      })
      is Err(@lowering_relation.RootLimit),
    )
  }
  for step in [0, 3] {
    assert_true(
      @lowering_relation.prepare_kernel_roots(sequence, step, root_limits())
      is Err(@lowering_relation.NotExpressionKernel),
    )
  }
  for step in [-1, 4] {
    assert_true(
      @lowering_relation.prepare_kernel_roots(sequence, step, root_limits())
      is Err(@lowering_relation.InvalidStep),
    )
  }
  assert_true(
    @lowering_relation.prepare_kernel_roots(sequence, 1, {
      ..root_limits(),
      max_work: -1,
    })
    is Err(@lowering_relation.InvalidRootLimits),
  )
}
