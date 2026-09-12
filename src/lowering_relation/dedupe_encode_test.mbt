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
