///|
test "whole-row distinct emits the registered node with closed empty params" {
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(",{\"distinct\":true}"),
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("distinct kernel")
  }
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"distinct_1\",\"in\":[\"values_0\"],\"op\":\"REL.distinct\",\"params\":{}}",
  )
}
