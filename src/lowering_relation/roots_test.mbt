///|
fn root_limits() -> @lowering_relation.RootLimits {
  { max_roots: 100, max_pointer_bytes: 10000, max_work: 100000, }
}

///|
test "ordered roots sort pointers while retaining authored slot ownership" {
  let tail = StringBuilder()
  tail.write_string(",{\"derive\":[")
  for i in 0..<12 {
    if i > 0 {
      tail.write_string(",")
    }
    tail.write_string("{\"s" + i.to_string() + "\":\"id\"}")
  }
  tail.write_string("]}")
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(tail.to_string()),
    sequence_limits(),
  ).unwrap()
  let roots = @lowering_relation.prepare_kernel_roots(
    sequence,
    1,
    root_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("kernel")
  }
  guard @lowering_relation.kernel_body(kernel)
    is @lowering_relation.OrderedBindings(bindings) else {
    fail("ordered")
  }
  assert_eq(bindings.map(b => b.0), [
    "s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11",
  ])
  for root_index, slot in [0, 1, 10, 11, 2, 3, 4, 5, 6, 7, 8, 9] {
    let root = @lowering_relation.root_at(roots, root_index).unwrap()
    assert_eq(root.parameter_pointer, "/bindings/" + slot.to_string() + "/expr")
    assert_true(physical_equal(root.expression, bindings[slot].1))
    assert_true(
      physical_equal(
        root.typed_expression,
        @relation.binding_at(@lowering_relation.kernel_checked(kernel), slot).unwrap().expression,
      ),
    )
  }
  assert_true(
    @lowering_relation.prepare_kernel_roots(sequence, 1, {
      ..root_limits(),
      max_roots: 11,
    })
    is Err(@lowering_relation.RootLimit),
  )
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
  // Escaped pointer ordering must carry the original checked expression with
  // its lowered partner, not select the same numeric slot in the sorted index.
  for (root_index, binding_index) in [(0, 1), (1, 2), (2, 0)] {
    let original = @relation.binding_at(
        @lowering_relation.kernel_checked(kernel),
        binding_index,
      ).unwrap().expression
    assert_true(
      physical_equal(
        @lowering_relation.root_at(index, root_index).unwrap().typed_expression,
        original,
      ),
    )
  }
  guard @lowering_relation.sequence_step(sequence, 3)
    is Some(@lowering_relation.RowStep(predicate)) else {
    fail("predicate")
  }
  assert_true(
    physical_equal(
      @lowering_relation.root_at(index, 3).unwrap().typed_expression,
      @relation.binding_at(@lowering_relation.kernel_checked(predicate), 0).unwrap().expression,
    ),
  )
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
