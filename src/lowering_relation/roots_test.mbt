///|
fn root_limits() -> @lowering_relation.RootLimits {
  { max_roots: 100, max_pointer_bytes: 10000, max_work: 100000, }
}

///|
test "root graph order is step order rather than lexical generated ID order" {
  let tail = StringBuilder()
  for i in 1..<13 {
    tail.write_string(",{\"derive\":{\"field_" + i.to_string() + "\":\"1\"}}")
  }
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(tail.to_string()),
    sequence_limits(),
  ).unwrap()
  let index = @lowering_relation.prepare_roots(sequence, root_limits()).unwrap()
  assert_eq(@lowering_relation.root_count(index), 12)
  for i in 0..<12 {
    let root = @lowering_relation.root_at(index, i).unwrap()
    assert_eq(root.step_index, i + 1)
    assert_eq(root.step_id, "derive_" + (i + 1).to_string())
  }
}

///|
test "roots preserve graph order and sort escaped pointers without reordering evaluation" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"~\":\"1\",\"/\":\"2\",\"a\":\"3\"}},{\"derive\":{}},{\"filter\":\"true\"},{\"select\":[\"id\"]}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  let index = @lowering_relation.prepare_roots(sequence, root_limits()).unwrap()
  assert_true(physical_equal(@lowering_relation.root_sequence(index), sequence))
  assert_eq(@lowering_relation.root_count(index), 4)
  let expected = [
    (1, "derive_1", "/exprs/a"),
    (1, "derive_1", "/exprs/~0"),
    (1, "derive_1", "/exprs/~1"),
    (3, "where_3", "/expr"),
  ]
  for i = 0; i < expected.length(); i = i + 1 {
    let root = @lowering_relation.root_at(index, i).unwrap()
    assert_eq(
      (root.step_index, root.step_id, root.parameter_pointer),
      expected[i],
    )
  }
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("kernel")
  }
  guard @lowering_relation.kernel_body(kernel)
    is @lowering_relation.SnapshotMap(bindings) else {
    fail("map")
  }
  assert_eq(bindings.map(b => b.0), ["/", "a", "~"])
  assert_true(
    physical_equal(
      @lowering_relation.root_at(index, 2).unwrap().expression,
      bindings[0].1,
    ),
  )
  assert_eq(
    expression_wire(@lowering_relation.root_at(index, 2).unwrap().expression),
    "{\"body\":2,\"op\":\"literal\"}",
  )
  assert_true(@lowering_relation.root_at(index, -1) is None)
  assert_true(@lowering_relation.root_at(index, 4) is None)
}

///|
test "root index budgets are cumulative and empty map has no invented root" {
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(",{\"derive\":{\"a\":\"1\"}},{\"filter\":\"true\"}"),
    sequence_limits(),
  ).unwrap()
  let exact : @lowering_relation.RootLimits = {
    max_roots: 2,
    max_pointer_bytes: 13,
    max_work: 21,
  }
  assert_true(@lowering_relation.prepare_roots(sequence, exact) is Ok(_))
  for
    limited in [
      { ..exact, max_roots: 1, },
      { ..exact, max_pointer_bytes: 12, },
      { ..exact, max_work: 20, },
    ] {
    assert_true(
      @lowering_relation.prepare_roots(sequence, limited)
      is Err(@lowering_relation.RootLimit),
    )
  }
  assert_true(
    @lowering_relation.prepare_roots(sequence, { ..exact, max_roots: -1, })
    is Err(@lowering_relation.InvalidRootLimits),
  )
  let empty = @lowering_relation.prepare_sequence(
    expression_pipeline(",{\"derive\":{}},{\"select\":[\"id\"]}"),
    sequence_limits(),
  ).unwrap()
  let index = @lowering_relation.prepare_roots(empty, {
    max_roots: 0,
    max_pointer_bytes: 0,
    max_work: 3,
  }).unwrap()
  assert_eq(@lowering_relation.root_count(index), 0)
  assert_eq(
    @lowering_relation.sequence_count(@lowering_relation.root_sequence(index)),
    3,
  )
}

///|
test "root pointer sorting uses UTF16 but pointer ceilings use UTF8" {
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(",{\"derive\":{\"😀\":\"1\",\"\uE000\":\"2\"}}"),
    sequence_limits(),
  ).unwrap()
  let limits = { ..root_limits(), max_pointer_bytes: 21, }
  let roots = @lowering_relation.prepare_roots(sequence, limits).unwrap()
  assert_eq(
    @lowering_relation.root_at(roots, 0).unwrap().parameter_pointer,
    "/exprs/😀",
  )
  assert_eq(
    @lowering_relation.root_at(roots, 1).unwrap().parameter_pointer,
    "/exprs/\uE000",
  )
  assert_true(
    @lowering_relation.prepare_roots(sequence, {
      ..limits,
      max_pointer_bytes: 20,
    })
    is Err(@lowering_relation.RootLimit),
  )
}
