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
test "kernel preparation fails atomically on cumulative limits" {
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
    is Ok(_),
  )
}

///|
test "ordered preparation preserves authored slots and checked shadow references" {
  let owner = expression_pipeline(
    ",{\"derive\":[{\"z\":\"id\"},{\"id\":\"z\"},{\"a\":\"id\"}]}",
  )
  let kernel = @lowering_relation.prepare_kernel(
    owner,
    1,
    max_bindings=3,
    max_name_bytes=4,
    expression_limits(),
  ).unwrap()
  guard @lowering_relation.kernel_body(kernel)
    is @lowering_relation.OrderedBindings(bindings) else {
    fail("ordered")
  }
  assert_eq(bindings.map(b => b.0), ["z", "id", "a"])
  assert_true(
    @lowering_relation.expression_body(bindings[0].1)
    is @lowering_relation.Field("id", @relation.InputField(_)),
  )
  assert_true(
    @lowering_relation.expression_body(bindings[1].1)
    is @lowering_relation.Field("z", @relation.PriorSlot(0)),
  )
  assert_true(
    @lowering_relation.expression_body(bindings[2].1)
    is @lowering_relation.Field("id", @relation.PriorSlot(1)),
  )
  bindings.clear()
  assert_eq(@lowering_relation.kernel_view_entries(kernel), 3)
  guard @lowering_relation.kernel_body(kernel)
    is @lowering_relation.OrderedBindings(again) else {
    fail("ordered")
  }
  assert_eq(again.length(), 3)
  assert_true(
    @lowering_relation.prepare_kernel(
      owner,
      1,
      max_bindings=2,
      max_name_bytes=4,
      expression_limits(),
    )
    is Err(@lowering_relation.KernelBudgetExceeded),
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

///|
test "assertion kernels preserve checked predicate and authored unique tuple" {
  let owner = expression_pipeline(
    ",{\"assert_rows\":{\"where\":\"id > 0\"}},{\"assert_rows\":{\"unique_by\":[\"id\"]}}",
  )
  let predicate = @lowering_relation.prepare_kernel(
    owner,
    1,
    max_bindings=1,
    max_name_bytes=0,
    expression_limits(),
  ).unwrap()
  guard @lowering_relation.kernel_body(predicate)
    is @lowering_relation.AssertAll(expr) else {
    fail("assert all")
  }
  assert_true(
    @lowering_relation.expression_body(expr)
    is @lowering_relation.Binary(@lowering_relation.Greater, _, _),
  )
  let unique = @lowering_relation.prepare_kernel(
    owner,
    2,
    max_bindings=1,
    max_name_bytes=2,
    expression_limits(),
  ).unwrap()
  guard @lowering_relation.kernel_body(unique)
    is @lowering_relation.AssertUnique(keys) else {
    fail("assert unique")
  }
  assert_eq(keys, [@schema.Unqualified("id")])
  keys.clear()
  guard @lowering_relation.kernel_body(unique)
    is @lowering_relation.AssertUnique(again) else {
    fail("assert unique")
  }
  assert_eq(again.length(), 1)
}
