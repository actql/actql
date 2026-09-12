///|
test "rename and drop emit normative select nodes without deleting empty operations" {
  let owner = expression_pipeline(
    ",{\"rename\":{\"id\":\"renamed\"}},{\"rename\":{}},{\"drop\":[]}",
  )
  let expected = [
    "{\"id\":\"select_1\",\"in\":[\"values_0\"],\"op\":\"REL.select\",\"params\":{\"columns\":[{\"from\":\"id\",\"to\":\"renamed\"}]}}",
    "{\"id\":\"select_2\",\"in\":[\"select_1\"],\"op\":\"REL.select\",\"params\":{\"columns\":[\"renamed\"]}}",
    "{\"id\":\"select_3\",\"in\":[\"select_2\"],\"op\":\"REL.select\",\"params\":{\"columns\":[\"renamed\"]}}",
  ]
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  for i = 1; i <= 3; i = i + 1 {
    guard @lowering_relation.sequence_step(sequence, i)
      is Some(@lowering_relation.RowStep(kernel)) else {
      fail("projection node")
    }
    let writer = @encode.writer(10000, 1000, 100)
    @lowering_relation.emit_kernel_node(kernel, writer)
    assert_eq(@encode.finish(writer), expected[i - 1])
  }
}

///|
test "projection preparation preserves cumulative binding and name budgets" {
  let owner = expression_pipeline(
    ",{\"rename\":{\"id\":\"renamed\"}},{\"drop\":[]}",
  )
  let exact = { ..sequence_limits(), max_bindings: 2, max_name_bytes: 23, }
  assert_true(@lowering_relation.prepare_sequence(owner, exact) is Ok(_))
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
    @lowering_relation.prepare_sequence(owner, { ..exact, max_name_bytes: 22, })
    is Err(
      @lowering_relation.KernelFailure(
        2,
        @lowering_relation.KernelBudgetExceeded
      )
    ),
  )
}
