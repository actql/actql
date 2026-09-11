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
test "sequence rejects pending ordered contract after a supported prefix" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"x\":\"1\"}},{\"derive\":[{\"id\":{\"literal\":2}}]}",
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, sequence_limits())
    is Err(
      @lowering_relation.KernelFailure(
        2,
        @lowering_relation.NeedsSharedRowKernelContract
      )
    ),
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
