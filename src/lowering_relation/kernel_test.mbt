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
  assert_true(@lowering_relation.kernel_json_pick(kernel) is None)
  let view = @lowering_relation.kernel_bindings(kernel).unwrap()
  assert_false(@lowering_relation.bindings_ordered(view))
  assert_eq(@lowering_relation.bindings_count(view), 2)
  assert_eq(@lowering_relation.binding_at(view, 0).unwrap().0, "a")
  assert_eq(@lowering_relation.binding_at(view, 1).unwrap().0, "z")
  assert_true(@lowering_relation.binding_at(view, -1) is None)
  assert_true(@lowering_relation.binding_at(view, 2) is None)
  assert_true(@lowering_relation.kernel_unique_keys(kernel) is None)
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
  assert_eq(@lowering_relation.bindings_count(view), 2)
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
  let view = @lowering_relation.prepare_projection(
    @lowering_relation.kernel_checked(projection),
  ).unwrap()
  let first = @lowering_relation.projection_field_at(view, 0).unwrap()
  assert_eq(
    (first.output, first.input),
    (@schema.Unqualified("z"), @schema.Unqualified("z")),
  )
  assert_eq(
    @lowering_relation.projection_field_at(view, 1).unwrap().output,
    @schema.Unqualified("id"),
  )
  assert_true(@lowering_relation.projection_field_at(view, -1) is None)
  assert_true(@lowering_relation.projection_field_at(view, 2) is None)
  fields.clear()
  assert_eq(@lowering_relation.projection_field_count(view), 2)
  assert_eq(
    @lowering_relation.projection_field_at(view, 0).unwrap().output,
    @schema.Unqualified("z"),
  )
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
  let view = @lowering_relation.kernel_bindings(kernel).unwrap()
  assert_true(@lowering_relation.bindings_ordered(view))
  assert_eq(@lowering_relation.bindings_count(view), 3)
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
  assert_eq(@lowering_relation.binding_at(view, 1).unwrap().0, "id")
  assert_true(
    @lowering_relation.expression_body(
      @lowering_relation.binding_at(view, 1).unwrap().1,
    )
    is @lowering_relation.Field("z", @relation.PriorSlot(0)),
  )
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
  let view = @lowering_relation.kernel_unique_keys(unique).unwrap()
  assert_eq(@lowering_relation.unique_key_count(view), 1)
  assert_eq(
    @lowering_relation.unique_key_at(view, 0),
    Some(@schema.Unqualified("id")),
  )
  assert_true(@lowering_relation.unique_key_at(view, -1) is None)
  assert_true(@lowering_relation.unique_key_at(view, 1) is None)
  assert_true(@lowering_relation.kernel_bindings(unique) is None)
  guard @lowering_relation.kernel_body(unique)
    is @lowering_relation.AssertUnique(keys) else {
    fail("assert unique")
  }
  assert_eq(keys, [@schema.Unqualified("id")])
  keys.clear()
  assert_eq(@lowering_relation.unique_key_count(view), 1)
  guard @lowering_relation.kernel_body(unique)
    is @lowering_relation.AssertUnique(again) else {
    fail("assert unique")
  }
  assert_eq(again.length(), 1)
}

///|
test "json pick kernel retains exact checked field path and output" {
  let pipeline = @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"inner\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"leaf\":{\"type\":\"number\",\"nullable\":false}}}}}},\"rows\":[{\"payload\":{\"inner\":{\"leaf\":3}}}]},\"as\":\"seed\"},{\"json_pick\":{\"column\":\"payload\",\"path\":[\"inner\",\"leaf\"],\"output\":\"picked\"}}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(pipeline, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let kernel = @lowering_relation.prepare_kernel(
    owner,
    1,
    max_bindings=4,
    max_name_bytes=24,
    expression_limits(),
  ).unwrap()
  guard @lowering_relation.kernel_body(kernel)
    is @lowering_relation.JsonPick(column, path, output) else {
    fail("json pick")
  }
  assert_eq(column, @schema.Unqualified("payload"))
  assert_eq(path, ["inner", "leaf"])
  assert_eq(output, "picked")
  let view = @lowering_relation.kernel_json_pick(kernel).unwrap()
  assert_eq(@lowering_relation.json_pick_column(view), column)
  assert_eq(@lowering_relation.json_pick_output(view), output)
  assert_eq(@lowering_relation.json_pick_path_count(view), 2)
  assert_eq(@lowering_relation.json_pick_path_at(view, 0), Some("inner"))
  assert_eq(@lowering_relation.json_pick_path_at(view, 1), Some("leaf"))
  assert_true(@lowering_relation.json_pick_path_at(view, -1) is None)
  assert_true(@lowering_relation.json_pick_path_at(view, 2) is None)
  path.clear()
  // Mutating the defensive legacy export cannot alter the read-only view.
  assert_eq(@lowering_relation.json_pick_path_count(view), 2)
  assert_eq(@lowering_relation.json_pick_path_at(view, 1), Some("leaf"))
  guard @lowering_relation.kernel_body(kernel)
    is @lowering_relation.JsonPick(_, again, _) else {
    fail("json pick")
  }
  assert_eq(again.length(), 2)
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"json_pick_1\",\"in\":[\"values_0\"],\"op\":\"REL.json.pick\",\"params\":{\"column\":\"payload\",\"output\":\"picked\",\"path\":[\"inner\",\"leaf\"]}}",
  )
}
