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
fn ordered_nest_pipeline() -> @pipeline.CheckedPipeline {
  @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"key\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"key\":1}]},\"as\":\"parents\"}," +
      "{\"values\":{\"schema\":{\"key\":{\"type\":\"number\",\"nullable\":false},\"position\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"key\":1,\"position\":0,\"value\":2},{\"key\":1,\"position\":1,\"value\":1},{\"key\":1,\"position\":2,\"value\":1}]},\"as\":\"children\"}," +
      "{\"from\":\"parents\",\"nest\":{\"with\":\"children\",\"on\":[{\"left\":\"key\",\"right\":\"key\"}],\"into\":\"items\",\"fields\":[{\"amount\":\"value\"},{\"position\":\"position\"}],\"order_by\":[{\"value\":\"asc\"}]},\"as\":\"nested\"}]",
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
fn repeated_nest_pipeline(second : Bool) -> @pipeline.CheckedPipeline {
  let tail = if second {
    ",{\"from\":\"nested\",\"nest\":{\"with\":\"children\"," +
    "\"on\":[{\"left\":\"key\",\"right\":\"key\"}]," +
    "\"into\":\"more\",\"fields\":[{\"amount\":\"value\"}]}," +
    "\"as\":\"nested_again\"}"
  } else {
    ""
  }
  @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"key\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"parents\"}," +
      "{\"values\":{\"schema\":{\"key\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"children\"}," +
      "{\"from\":\"parents\",\"nest\":{\"with\":\"children\",\"on\":[{\"left\":\"key\",\"right\":\"key\"}],\"into\":\"items\",\"fields\":[{\"amount\":\"value\"}]},\"as\":\"nested\"}" +
      tail +
      "]",
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
fn canonical_node_and_identifier_totals(
  sequence : @lowering_relation.PreparedSequence,
) -> (Int, Int) {
  let mut nodes = 0
  let mut bytes = 0
  for step in 0..<@lowering_relation.sequence_count(sequence) {
    let count = @lowering_relation.sequence_canonical_node_count(sequence, step).unwrap()
    nodes += count
    for index in 0..<count {
      bytes += @lowering_relation.sequence_canonical_node_at(
        sequence, step, index,
      ).unwrap().id.length()
    }
  }
  (nodes, bytes)
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

///|
test "authored nest order emits a stable sort despite inherited tie order" {
  let checked = ordered_nest_pipeline()
  let prepared = @lowering_relation.prepare(checked, limits()).unwrap()
  let usage = @lowering_relation.usage(prepared)
  let exact : @lowering_relation.Limits = {
    max_nodes: usage.nodes,
    max_references: usage.references,
    max_work: usage.work,
    max_identifier_bytes: usage.identifier_bytes,
  }
  assert_true(@lowering_relation.prepare(checked, exact) is Ok(_))
  for
    limited in [
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_references: exact.max_references - 1, },
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_identifier_bytes: exact.max_identifier_bytes - 1, },
    ] {
    assert_true(@lowering_relation.prepare(checked, limited) is Err(_))
  }
  let owner = @lowering_relation.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 2)
    is Some(@lowering_relation.NestStep(kernel)) else {
    fail("nest step")
  }
  assert_true(@lowering_relation.nest_kernel_inherits_order(kernel))
  assert_eq(usage.nodes, 14)
  assert_eq(usage.references, 15)
  assert_eq(usage.work, 29)
  assert_eq(
    canonical_node_and_identifier_totals(sequence),
    (usage.nodes, usage.identifier_bytes),
  )
  assert_eq(
    @lowering_relation.sequence_canonical_node_count(sequence, 2),
    Some(12),
  )
  assert_eq(
    @lowering_relation.sequence_canonical_node_at(sequence, 2, 2).map(v => {
      (v.id, v.operation)
    }),
    Some(("nest_ordered_2", "REL.orderByStable")),
  )
  let writer = @encode.writer(100000, 10000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  let encoded = @encode.finish(writer)
  assert_true(
    encoded.contains(
      "{\"id\":\"nest_ordered_2\",\"in\":[\"nest_children_2\"]," +
      "\"op\":\"REL.orderByStable\"",
    ),
  )
}

///|
test "nest budgets include repeated finite expansions" {
  for second in [false, true] {
    let checked = repeated_nest_pipeline(second)
    let prepared = @lowering_relation.prepare(checked, limits()).unwrap()
    let usage = @lowering_relation.usage(prepared)
    let exact : @lowering_relation.Limits = {
      max_nodes: usage.nodes,
      max_references: usage.references,
      max_work: usage.work,
      max_identifier_bytes: usage.identifier_bytes,
    }
    assert_true(@lowering_relation.prepare(checked, exact) is Ok(_))
    for
      limited in [
        { ..exact, max_nodes: exact.max_nodes - 1, },
        { ..exact, max_references: exact.max_references - 1, },
        { ..exact, max_work: exact.max_work - 1, },
        { ..exact, max_identifier_bytes: exact.max_identifier_bytes - 1, },
      ] {
      assert_true(@lowering_relation.prepare(checked, limited) is Err(_))
    }
    let owner = @lowering_relation.bind_parameters(
      prepared,
      None,
      max_parameters=0,
      max_name_bytes=0,
    ).unwrap()
    let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
    assert_eq(usage.nodes, if second { 24 } else { 13 })
    assert_eq(usage.references, if second { 28 } else { 14 })
    assert_eq(usage.work, if second { 52 } else { 27 })
    assert_eq(
      canonical_node_and_identifier_totals(sequence),
      (usage.nodes, usage.identifier_bytes),
    )
    assert_eq(
      @lowering_relation.sequence_canonical_node_count(sequence, 2),
      Some(11),
    )
    if second {
      assert_eq(
        @lowering_relation.sequence_canonical_node_count(sequence, 3),
        Some(11),
      )
    }
  }
}
