///|
test "keyed distinct expands projection before distinct with collision-checked IDs" {
  let owner = expression_pipeline(",{\"distinct\":[\"id\"]}")
  let prepared = @lowering_relation.bound_preparation(owner)
  let usage = @lowering_relation.usage(prepared)
  assert_eq(usage.nodes, 3)
  assert_eq(usage.references, 2)
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"values_0\",\"in\":[],\"op\":\"REL.values\",\"params\":{\"rows\":[{\"id\":1}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"}}}},{\"id\":\"select_1\",\"in\":[\"values_0\"],\"op\":\"REL.select\",\"params\":{\"columns\":[\"id\"]}},{\"id\":\"distinct_1\",\"in\":[\"select_1\"],\"op\":\"REL.distinct\",\"params\":{}}]",
  )
  let exact : @lowering_relation.Limits = {
    max_nodes: usage.nodes,
    max_references: usage.references,
    max_work: usage.work,
    max_identifier_bytes: usage.identifier_bytes,
  }
  let pipeline = @lowering_relation.pipeline(prepared)
  assert_true(@lowering_relation.prepare(pipeline, exact) is Ok(_))
  for
    limited in [
      { ..exact, max_nodes: usage.nodes - 1, },
      { ..exact, max_references: usage.references - 1, },
      { ..exact, max_work: usage.work - 1, },
      { ..exact, max_identifier_bytes: usage.identifier_bytes - 1, },
    ] {
    assert_true(@lowering_relation.prepare(pipeline, limited) is Err(_))
  }
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
