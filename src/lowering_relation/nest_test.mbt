///|
fn nest_pipeline(max_items : String) -> @pipeline.CheckedPipeline {
  @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"key\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"id\":1,\"key\":1}]},\"as\":\"parents\"}," +
      "{\"values\":{\"schema\":{\"child_id\":{\"type\":\"number\",\"nullable\":false},\"key\":{\"type\":\"number\",\"nullable\":true},\"value\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"child_id\":1,\"key\":1,\"value\":2}]},\"as\":\"children\"}," +
      "{\"from\":\"parents\",\"nest\":{\"with\":\"children\",\"on\":[{\"left\":\"key\",\"right\":\"key\"}],\"into\":\"items\",\"fields\":[{\"amount\":\"value\"}]" +
      max_items +
      "},\"as\":\"nested\"}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
test "nest lowering retains checked ports order projection and item guard" {
  let checked = nest_pipeline(",\"max_items\":2")
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 2)
    is Some(@lowering_relation.NestStep(kernel)) else {
    fail("nest step")
  }
  assert_true(
    physical_equal(@lowering_relation.nest_kernel_owner(kernel), owner),
  )
  assert_eq(@lowering_relation.nest_kernel_step(kernel), 2)
  assert_eq(@lowering_relation.nest_kernel_input(kernel, true), "values_0")
  assert_eq(@lowering_relation.nest_kernel_input(kernel, false), "values_1")
  assert_eq(@lowering_relation.nest_kernel_item_limit(kernel), Some(2L))
  assert_eq(@lowering_relation.nest_kernel_key_count(kernel), 1)
  let key = @lowering_relation.nest_kernel_key_at(kernel, 0).unwrap()
  assert_eq(
    (key.left, key.right),
    (@schema.Unqualified("key"), @schema.Unqualified("key")),
  )
  assert_eq(@lowering_relation.nest_kernel_field_count(kernel), 1)
  let field = @lowering_relation.nest_kernel_field_at(kernel, 0).unwrap()
  assert_eq(
    (field.output, field.input),
    ("amount", @schema.Unqualified("value")),
  )
  assert_eq(@lowering_relation.nest_kernel_order_count(kernel), 0)
  assert_true(@lowering_relation.nest_kernel_inherits_order(kernel))
}

///|
test "nest lowering leaves a selected item ceiling unresolved" {
  let checked = nest_pipeline("")
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 2)
    is Some(@lowering_relation.NestStep(kernel)) else {
    fail("nest step")
  }
  assert_eq(@lowering_relation.nest_kernel_item_limit(kernel), None)
}

///|
test "nest lowering emits only registered canonical expansion nodes" {
  let checked = nest_pipeline(",\"max_items\":2")
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  assert_eq(
    @lowering_relation.sequence_canonical_node_count(sequence, 2),
    Some(11),
  )
  assert_eq(
    @lowering_relation.sequence_canonical_node_at(sequence, 2, 0).map(v => {
      (v.id, v.operation)
    }),
    Some(("nest_matched_2", "REL.join")),
  )
  assert_eq(
    @lowering_relation.sequence_canonical_node_at(sequence, 2, 10).map(v => {
      (v.id, v.operation)
    }),
    Some(("nest_2", "REL.select")),
  )
  let writer = @encode.writer(100000, 10000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  let encoded = @encode.finish(writer)
  assert_false(encoded.contains("REL.nest"))
  for
    operation in [
      "REL.join", "REL.select", "REL.groupBy", "REL.where", "REL.derive",
    ] {
    assert_true(encoded.contains("\"op\":\"" + operation + "\""))
  }
  assert_true(
    encoded.contains(
      "\"__actql_nest_items\":{\"expr\":{\"fields\":{\"amount\":" +
      "{\"path\":[\"value\"],\"type\":\"col\"}},\"type\":\"object\"}," +
      "\"fn\":\"array_agg\",\"max_items\":2}",
    ),
  )
}
