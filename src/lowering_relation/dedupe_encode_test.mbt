///|
test "dedupe emits authored repeated keys and explicit representative invariants" {
  let owner = expression_pipeline(
    ",{\"dedupe_rows\":{\"by\":[\"id\",\"id\"],\"order_by\":[{\"field\":\"id\",\"dir\":\"desc\",\"nulls\":\"first\"}]}}",
  )
  let limits = { ..sequence_limits(), max_bindings: 3, max_name_bytes: 6, }
  let sequence = @lowering_relation.prepare_sequence(owner, limits).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("dedupe")
  }
  let writer = @encode.writer(10000, 1000, 100)
  assert_true(@lowering_relation.kernel_is_dedupe(kernel))
  assert_eq(@lowering_relation.kernel_dedupe_key_count(kernel), 2)
  for index in 0..<2 {
    assert_eq(
      @lowering_relation.kernel_dedupe_key_at(kernel, index),
      Some(@schema.Unqualified("id")),
    )
  }
  assert_eq(@lowering_relation.kernel_dedupe_order_count(kernel), 1)
  assert_eq(
    @lowering_relation.kernel_dedupe_order_at(kernel, 0),
    Some((@schema.Unqualified("id"), true, true)),
  )
  assert_true(@lowering_relation.kernel_dedupe_key_at(kernel, -1) is None)
  assert_true(@lowering_relation.kernel_dedupe_key_at(kernel, 2) is None)
  assert_true(@lowering_relation.kernel_dedupe_order_at(kernel, 1) is None)
  @lowering_relation.emit_kernel_node(kernel, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"dedupe_1\",\"in\":[\"values_0\"],\"op\":\"REL.dedupeRows\",\"params\":{\"by\":[\"id\",\"id\"],\"keep\":\"first\",\"on_tie\":\"fail\",\"order_by\":[{\"dir\":\"desc\",\"field\":\"id\",\"nulls\":\"first\"}]}}",
  )
  for
    limited in [
      { ..limits, max_bindings: 2, },
      { ..limits, max_name_bytes: 5, },
      { ..limits, expressions: { ..limits.expressions, max_work: 2, }, },
    ] {
    assert_true(
      @lowering_relation.prepare_sequence(owner, limited)
      is Err(
        @lowering_relation.KernelFailure(
          1,
          @lowering_relation.KernelBudgetExceeded
        )
      ),
    )
  }
}

///|
test "dedupe semantic view preserves different keys and representative order" {
  let owner = expression_pipeline(
    ",{\"derive\":{\"z\":\"id\"}},{\"dedupe_rows\":{\"by\":[\"z\",\"id\"],\"order_by\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"last\"},{\"field\":\"z\",\"dir\":\"desc\",\"nulls\":\"first\"}]}}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 2)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("dedupe")
  }
  assert_eq(@lowering_relation.kernel_dedupe_key_count(kernel), 2)
  assert_eq(@lowering_relation.kernel_dedupe_order_count(kernel), 2)
  for (index, name) in [(0, "z"), (1, "id")] {
    assert_eq(
      @lowering_relation.kernel_dedupe_key_at(kernel, index),
      Some(@schema.Unqualified(name)),
    )
  }
  assert_eq(
    @lowering_relation.kernel_dedupe_order_at(kernel, 0),
    Some((@schema.Unqualified("id"), false, false)),
  )
  assert_eq(
    @lowering_relation.kernel_dedupe_order_at(kernel, 1),
    Some((@schema.Unqualified("z"), true, true)),
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"dedupe_2\",\"in\":[\"derive_1\"],\"op\":\"REL.dedupeRows\",\"params\":{\"by\":[\"z\",\"id\"],\"keep\":\"first\",\"on_tie\":\"fail\",\"order_by\":[{\"dir\":\"asc\",\"field\":\"id\",\"nulls\":\"last\"},{\"dir\":\"desc\",\"field\":\"z\",\"nulls\":\"first\"}]}}",
  )
}
