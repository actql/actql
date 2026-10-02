///|
fn sequence_limits() -> @lowering_relation.SequenceLimits {
  {
    max_steps: 100,
    max_rows: 100,
    max_cells: 1000,
    max_bindings: 100,
    max_name_bytes: 10000,
    expressions: expression_limits(),
  }
}

///|
test "checked prefix preserves its owner and shares finite preparation limits" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"x\":\"1\"}},{\"derive\":{\"y\":\"2\"}}",
  )
  let limits = {
    ..sequence_limits(),
    max_steps: 2,
    expressions: { ..expression_limits(), max_nodes: 1, },
  }
  let prefix = @lowering_relation.prepare_sequence_prefix(owner, 1, limits).unwrap()
  assert_true(physical_equal(@lowering_relation.sequence_owner(prefix), owner))
  assert_eq(@lowering_relation.sequence_count(prefix), 2)
  assert_true(@lowering_relation.sequence_step(prefix, 2) is None)
  assert_true(
    @lowering_relation.prepare_sequence(owner, limits)
    is Err(@lowering_relation.SequenceLimit),
  )
  assert_true(
    @lowering_relation.prepare_sequence_prefix(owner, -1, limits)
    is Err(@lowering_relation.SequenceLimit),
  )
  assert_true(
    @lowering_relation.prepare_sequence_prefix(owner, 3, limits)
    is Err(@lowering_relation.SequenceLimit),
  )
  assert_true(
    @lowering_relation.prepare_sequence_prefix(owner, 1, {
      ..limits,
      max_steps: 1,
    })
    is Err(@lowering_relation.SequenceLimit),
  )
  assert_true(
    @lowering_relation.prepare_sequence_prefix(owner, 1, {
      ..limits,
      expressions: { ..limits.expressions, max_nodes: 0, },
    })
    is Err(
      @lowering_relation.KernelFailure(
        1,
        @lowering_relation.ExpressionFailure(_)
      )
    ),
  )
}

///|
test "source-free Values emits one complete AoA pipeline" {
  let one = @lowering_relation.prepare_sequence(
    expression_pipeline(""),
    sequence_limits(),
  ).unwrap()
  let writer = @encode.writer(10000, 1000, 100)
  assert_true(
    @lowering_relation.emit_source_free_values_pipeline(one, writer) is Ok(_),
  )
  assert_eq(
    @encode.finish(writer),
    "{\"output\":\"values_0\",\"sources\":{},\"steps\":[{\"id\":\"values_0\",\"in\":[],\"op\":\"REL.values\",\"params\":{\"rows\":[{\"id\":1}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"}}}}],\"version\":\"aoa-pipeline/0.1\"}",
  )
  let multiple = @lowering_relation.prepare_sequence(
    expression_pipeline(",{\"derive\":{}}"),
    sequence_limits(),
  ).unwrap()
  let chained_writer = @encode.writer(10000, 1000, 100)
  assert_true(
    @lowering_relation.emit_source_free_values_pipeline(
      multiple, chained_writer,
    )
    is Ok(_),
  )
  assert_true(
    @encode.finish(chained_writer).contains("\"output\":\"derive_1\""),
  )
}

///|
test "all four operations prepare under one owner and emit one ordered step array" {
  let owner = expression_pipeline(
    ",{\"derive\":{}},{\"filter\":\"true\"},{\"select\":[\"id\"]}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  assert_true(
    physical_equal(@lowering_relation.sequence_owner(sequence), owner),
  )
  assert_eq(@lowering_relation.sequence_count(sequence), 4)
  assert_true(
    @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.ValuesStep(_)),
  )
  assert_true(@lowering_relation.sequence_step(sequence, 4) is None)
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"values_0\",\"in\":[],\"op\":\"REL.values\",\"params\":{\"rows\":[{\"id\":1}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"}}}},{\"id\":\"derive_1\",\"in\":[\"values_0\"],\"op\":\"REL.derive\",\"params\":{\"exprs\":{}}},{\"id\":\"where_2\",\"in\":[\"derive_1\"],\"op\":\"REL.where\",\"params\":{\"expr\":{\"body\":true,\"op\":\"literal\"}}},{\"id\":\"select_3\",\"in\":[\"where_2\"],\"op\":\"REL.select\",\"params\":{\"columns\":[\"id\"]}}]",
  )
}

///|
test "sequence preparation shares expression budget and exposes no partial result" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"x\":\"1\"}},{\"derive\":{\"y\":\"2\"}}",
  )
  let exact = {
    ..sequence_limits(),
    expressions: { ..expression_limits(), max_nodes: 2, },
  }
  assert_true(@lowering_relation.prepare_sequence(owner, exact) is Ok(_))
  let short = { ..exact, expressions: { ..exact.expressions, max_nodes: 1, }, }
  assert_true(
    @lowering_relation.prepare_sequence(owner, short)
    is Err(
      @lowering_relation.KernelFailure(
        2,
        @lowering_relation.ExpressionFailure(_)
      )
    ),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, { ..exact, max_bindings: 1, })
    is Err(
      @lowering_relation.KernelFailure(
        2,
        @lowering_relation.KernelBudgetExceeded
      )
    ),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, { ..exact, max_name_bytes: 1, })
    is Err(
      @lowering_relation.KernelFailure(
        2,
        @lowering_relation.KernelBudgetExceeded
      )
    ),
  )
}

///|
test "ordered preparation does not confer fragment encoding admission" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"x\":\"1\"}},{\"derive\":[{\"id\":{\"literal\":2}}]}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  assert_eq(@lowering_relation.sequence_count(sequence), 3)
  let occurrence = @lowering_relation.sequence_canonical_node_at(sequence, 2, 0).unwrap()
  assert_eq(
    (occurrence.source_step, occurrence.id, occurrence.operation),
    (2, "derive_2", "REL.derive"),
  )
  let fragment = @lowering_relation.prepare_fragment_pipeline(
    sequence,
    2,
    root_limits(),
  ).unwrap()
  assert_true(
    @lowering_relation.prepare_fragment_request(fragment, 10L, 1000L)
    is Err(@lowering_relation.RowLimitsMismatch),
  )
  let writer = @encode.writer(100000, 10000, 100)
  assert_true(
    try {
      @lowering_relation.emit_sequence_steps(sequence, writer)
      false
    } catch {
      @encode.InvalidStructure => true
      _ => false
    },
  )
  assert_true(
    try {
      let _ = @encode.finish(writer)
      false
    } catch {
      _ => true
    },
  )
}

///|
test "multiple values nodes share row and cell preparation ceilings" {
  let owner = expression_pipeline(
    ",{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2}]},\"as\":\"other\"}",
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_rows: 2,
      max_cells: 2,
    })
    is Ok(_),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_rows: 1,
    })
    is Err(@lowering_relation.ValuesFailure(1, @lowering_relation.ValuesLimit)),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_cells: 1,
    })
    is Err(@lowering_relation.ValuesFailure(1, @lowering_relation.ValuesLimit)),
  )
}
