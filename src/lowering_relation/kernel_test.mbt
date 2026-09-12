///|
test "prepared map kernel preserves canonical binding order and defensive access" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"z\":\"id + 2\",\"a\":\"id + 1\"}}",
  )
  let kernel = @lowering_relation.prepare_kernel(
    owner,
    1,
    max_bindings=2,
    max_name_bytes=2,
    expression_limits(),
  ).unwrap()
  assert_true(physical_equal(@lowering_relation.kernel_owner(kernel), owner))
  assert_eq(@lowering_relation.kernel_step(kernel), 1)
  assert_eq(@lowering_relation.kernel_input(kernel), "values_0")
  guard @lowering_relation.kernel_body(kernel)
    is @lowering_relation.SnapshotMap(bindings) else {
    fail("map")
  }
  assert_eq(bindings.map(p => p.0), ["a", "z"])
  assert_eq(
    expression_wire(bindings[0].1),
    "{\"body\":[{\"body\":\"id\",\"op\":\"field\"},{\"body\":1,\"op\":\"literal\"}],\"op\":\"add\"}",
  )
  bindings.clear()
  guard @lowering_relation.kernel_body(kernel)
    is @lowering_relation.SnapshotMap(again) else {
    fail("map")
  }
  assert_eq(again.length(), 2)
}

///|
test "empty map remains a kernel and select keeps authored column order" {
  let owner = expression_pipeline(
    ",{\"derive\":{},\"as\":\"kept\"},{\"derive\":{\"z\":\"id\"}},{\"select\":[\"z\",\"id\"]}",
  )
  let noop = @lowering_relation.prepare_kernel(
    owner,
    1,
    max_bindings=0,
    max_name_bytes=0,
    expression_limits(),
  ).unwrap()
  guard @lowering_relation.kernel_body(noop)
    is @lowering_relation.SnapshotMap(bindings) else {
    fail("no-op lost")
  }
  assert_eq(bindings.length(), 0)
  let projection = @lowering_relation.prepare_kernel(
    owner,
    3,
    max_bindings=2,
    max_name_bytes=6,
    expression_limits(),
  ).unwrap()
  guard @lowering_relation.kernel_body(projection)
    is @lowering_relation.Select(fields) else {
    fail("select")
  }
  assert_eq(fields.map(f => @schema.reference_name(f.output)), ["z", "id"])
  fields.clear()
  guard @lowering_relation.kernel_body(projection)
    is @lowering_relation.Select(again) else {
    fail("select")
  }
  assert_eq(again.length(), 2)
}

///|
test "kernel preparation fails atomically on cumulative limits and pending ordered contract" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"a\":{\"literal\":1},\"b\":{\"literal\":2}}}",
  )
  let enough = { ..expression_limits(), max_nodes: 2, max_literal_nodes: 2, }
  assert_true(
    @lowering_relation.prepare_kernel(
      owner,
      1,
      max_bindings=2,
      max_name_bytes=2,
      enough,
    )
    is Ok(_),
  )
  for cap in [{ ..enough, max_nodes: 1, }, { ..enough, max_literal_nodes: 1, }] {
    assert_true(
      @lowering_relation.prepare_kernel(
        owner,
        1,
        max_bindings=2,
        max_name_bytes=2,
        cap,
      )
      is Err(@lowering_relation.ExpressionFailure(_)),
    )
  }
  assert_true(
    @lowering_relation.prepare_kernel(
      owner,
      1,
      max_bindings=1,
      max_name_bytes=2,
      enough,
    )
    is Err(@lowering_relation.KernelBudgetExceeded),
  )
  let ordered = expression_pipeline(",{\"derive\":[{\"id\":{\"literal\":2}}]}")
  assert_true(
    @lowering_relation.prepare_kernel(
      ordered,
      1,
      max_bindings=1,
      max_name_bytes=2,
      enough,
    )
    is Err(@lowering_relation.NeedsRowKernelImplementation),
  )
}

///|
test "predicate kernel carries its typed expression without testing it at lowering time" {
  let owner = expression_pipeline(
    ",{\"filter\":{\"gt\":[{\"field\":\"id\"},{\"literal\":0}]}}",
  )
  let kernel = @lowering_relation.prepare_kernel(
    owner,
    1,
    max_bindings=1,
    max_name_bytes=0,
    expression_limits(),
  ).unwrap()
  guard @lowering_relation.kernel_body(kernel)
    is @lowering_relation.Filter(expr) else {
    fail("predicate")
  }
  assert_true(
    @lowering_relation.expression_body(expr)
    is @lowering_relation.Binary(@lowering_relation.Greater, _, _),
  )
}
