///|
test "sort emits only compiler resolved terms and keeps empty sort as a node" {
  for
    (body, expected, terms) in [
      ("[]", "[]", 0),
      (
        "[{\"field\":\"id\",\"dir\":\"desc\",\"nulls\":\"first\"}]", "[{\"dir\":\"desc\",\"field\":\"id\",\"nulls\":\"first\"}]",
        1,
      ),
    ] {
    let owner = expression_pipeline(",{\"sort\":" + body + "}")
    let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
    guard @lowering_relation.sequence_step(sequence, 1)
      is Some(@lowering_relation.RowStep(kernel)) else {
      fail("sort")
    }
    assert_eq(@lowering_relation.kernel_sort_term_count(kernel), terms)
    assert_true(@lowering_relation.kernel_sort_term_at(kernel, -1) is None)
    assert_true(@lowering_relation.kernel_sort_term_at(kernel, terms) is None)
    let writer = @encode.writer(10000, 1000, 100)
    @lowering_relation.emit_kernel_node(kernel, writer)
    assert_eq(
      @encode.finish(writer),
      "{\"id\":\"sort_1\",\"in\":[\"values_0\"],\"op\":\"REL.orderByStable\",\"params\":{\"by\":" +
      expected +
      "}}",
    )
    if terms > 0 {
      assert_true(
        @lowering_relation.prepare_sequence(owner, {
          ..sequence_limits(),
          max_bindings: 0,
        })
        is Err(
          @lowering_relation.KernelFailure(
            1,
            @lowering_relation.KernelBudgetExceeded
          )
        ),
      )
    }
  }
}
