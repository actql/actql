///|
fn reference_limits() -> @lowering_relation.OrderedReferenceLimits {
  {
    max_references: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
    max_frames: 100,
  }
}

///|
fn ordered_kernel(tail : String) -> @lowering_relation.PreparedKernel {
  @lowering_relation.prepare_kernel(
    expression_pipeline(tail),
    1,
    max_bindings=100,
    max_name_bytes=10000,
    expression_limits(),
  ).unwrap()
}

///|
fn references_wire(
  index : @lowering_relation.OrderedReferences,
) -> String raise {
  let writer = @encode.writer(100000, 10000, 100)
  @lowering_relation.emit_ordered_references(index, writer)
  @encode.finish(writer)
}

///|
test "ordered reference table keeps occurrences and checked shadow identity" {
  let kernel = ordered_kernel(
    ",{\"derive\":[{\"old\":\"id\"},{\"id\":\"id + 1\"},{\"total\":\"old + id\"},{\"twice\":\"total + total\"}]}",
  )
  let index = @lowering_relation.prepare_ordered_references(
    kernel,
    reference_limits(),
  ).unwrap()
  assert_true(
    physical_equal(@lowering_relation.ordered_reference_kernel(index), kernel),
  )
  assert_eq(@lowering_relation.ordered_reference_count(index), 6)
  assert_eq(
    references_wire(index),
    "[{\"at\":\"/bindings/0/expr\",\"target\":{\"input_field\":\"id\"}},{\"at\":\"/bindings/1/expr/body/0\",\"target\":{\"input_field\":\"id\"}},{\"at\":\"/bindings/2/expr/body/0\",\"target\":{\"prior_slot\":0}},{\"at\":\"/bindings/2/expr/body/1\",\"target\":{\"prior_slot\":1}},{\"at\":\"/bindings/3/expr/body/0\",\"target\":{\"prior_slot\":2}},{\"at\":\"/bindings/3/expr/body/1\",\"target\":{\"prior_slot\":2}}]",
  )
  assert_true(@lowering_relation.ordered_reference_at(index, -1) is None)
  assert_true(@lowering_relation.ordered_reference_at(index, 6) is None)
}

///|
test "reference preorder covers lazy branches and case independently of serialization" {
  let index = @lowering_relation.prepare_ordered_references(
    ordered_kernel(
      ",{\"derive\":[{\"v\":\"CASE WHEN id > 0 THEN -id ELSE if(id = 0, id, coalesce(id, id)) END\"}]}",
    ),
    reference_limits(),
  ).unwrap()
  let expected = [
    "/bindings/0/expr/body/when/0/when/body/0", "/bindings/0/expr/body/when/0/then/body",
    "/bindings/0/expr/body/else/body/0/body/0", "/bindings/0/expr/body/else/body/1",
    "/bindings/0/expr/body/else/body/2/body/0", "/bindings/0/expr/body/else/body/2/body/1",
  ]
  assert_eq(
    @lowering_relation.ordered_reference_count(index),
    expected.length(),
  )
  for i, pointer in expected {
    let entry = @lowering_relation.ordered_reference_at(index, i).unwrap()
    assert_eq(entry.at, pointer)
    assert_true(entry.target is @relation.InputField(_))
  }
}

///|
test "vector score references retain the structured operand paths" {
  let owner = vector_expression_pipeline(
    "{\"vector_score\":{\"left\":{\"field\":\"left\"},\"right\":{\"field\":\"right\"},\"metric\":\"dot\"}}",
  )
  let expression = @lowering_relation.lower_expression(
    owner,
    0,
    0,
    expression_limits(),
  ).unwrap()
  let kernel = match
    @lowering_relation.prepare_kernel(
      owner,
      0,
      max_bindings=100,
      max_name_bytes=10000,
      expression_limits(),
    ) {
    Ok(value) => value
    Err(_) => fail("vector score kernel")
  }
  let index = @lowering_relation.prepare_ordered_references(
    kernel,
    reference_limits(),
  ).unwrap()
  assert_true(
    @lowering_relation.expression_body(expression)
    is @lowering_relation.VectorScore(_, _, _),
  )
  assert_eq(
    references_wire(index),
    "[{\"at\":\"/bindings/0/expr/body/left\",\"target\":{\"input_field\":\"left\"}},{\"at\":\"/bindings/0/expr/body/right\",\"target\":{\"input_field\":\"right\"}}]",
  )
}

///|
test "reference table never interprets expression shaped literal business data" {
  let kernel = ordered_kernel(
    ",{\"derive\":[{\"payload\":{\"literal\":{\"op\":\"field\",\"body\":\"missing\",\"$param\":\"business\",\"prior_slot\":99}}}]}",
  )
  let index = @lowering_relation.prepare_ordered_references(kernel, {
    ..reference_limits(),
    max_references: 0,
    max_pointer_bytes: 0,
  }).unwrap()
  assert_eq(references_wire(index), "[]")
}

///|
test "reference budgets are cumulative and failure cannot expose a partial table" {
  let kernel = ordered_kernel(",{\"derive\":[{\"x\":\"id\"},{\"y\":\"id\"}]}")
  let limits = reference_limits()
  // Two 16-byte root pointers and two visits: exactly 34 work units.
  let exact : @lowering_relation.OrderedReferenceLimits = {
    max_references: 2,
    max_pointer_bytes: 32,
    max_work: 34,
    max_frames: 1,
  }
  assert_true(
    @lowering_relation.prepare_ordered_references(kernel, exact) is Ok(_),
  )
  for
    short in [
      { ..exact, max_references: 1, },
      { ..exact, max_pointer_bytes: 31, },
      { ..exact, max_work: 33, },
      { ..exact, max_frames: 0, },
    ] {
    assert_true(
      @lowering_relation.prepare_ordered_references(kernel, short)
      is Err(@lowering_relation.ReferenceLimit),
    )
  }
  assert_true(
    @lowering_relation.prepare_ordered_references(kernel, {
      ..limits,
      max_work: -1,
    })
    is Err(@lowering_relation.InvalidReferenceLimits),
  )
  assert_true(
    @lowering_relation.prepare_ordered_references(
      ordered_kernel(",{\"derive\":{}}"),
      limits,
    )
    is Err(@lowering_relation.NotOrderedKernel),
  )
}

///|
test "wide expression reference traversal uses bounded continuations" {
  let source = StringBuilder()
  source.write_string(",{\"derive\":[{\"x\":\"coalesce(")
  for i in 0..<80 {
    if i > 0 {
      source.write_string(",")
    }
    source.write_string("id")
  }
  source.write_string(")\"}]}")
  let index = @lowering_relation.prepare_ordered_references(
    ordered_kernel(source.to_string()),
    { ..reference_limits(), max_frames: 2, },
  ).unwrap()
  assert_eq(@lowering_relation.ordered_reference_count(index), 80)
  assert_eq(
    @lowering_relation.ordered_reference_at(index, 79).unwrap().at,
    "/bindings/0/expr/body/79",
  )
  let short = @encode.writer(5, 1000, 100)
  assert_true(
    try {
      @lowering_relation.emit_ordered_references(index, short)
      false
    } catch {
      @encode.OutputLimit => true
      _ => false
    },
  )
  assert_true(
    try {
      let _ = @encode.finish(short)
      false
    } catch {
      _ => true
    },
  )
}
