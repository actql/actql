///|
test "group semantic occurrence maps to canonical grouping then null-first ordering" {
  let owner = expression_pipeline(
    ",{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  assert_eq(
    @lowering_relation.sequence_canonical_node_count(sequence, 1),
    Some(2),
  )
  let group = @lowering_relation.sequence_canonical_node_at(sequence, 1, 0).unwrap()
  let order = @lowering_relation.sequence_canonical_node_at(sequence, 1, 1).unwrap()
  assert_eq(
    (group.source_step, group.id, group.operation),
    (1, "aggregate_1", "REL.groupBy"),
  )
  assert_eq(
    (order.source_step, order.id, order.operation),
    (1, "group_1", "REL.orderByStable"),
  )
  assert_true(
    @lowering_relation.sequence_canonical_node_at(sequence, 1, 2) is None,
  )
  assert_true(
    @lowering_relation.sequence_canonical_node_at(sequence, 1, -1) is None,
  )
  assert_true(
    @lowering_relation.sequence_canonical_node_count(sequence, 2) is None,
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  let wire = @encode.finish(writer)
  assert_true(
    wire.contains(
      "\"id\":\"aggregate_1\",\"in\":[\"values_0\"],\"op\":\"REL.groupBy\"",
    ),
  )
  assert_true(
    wire.contains(
      "\"id\":\"group_1\",\"in\":[\"aggregate_1\"],\"op\":\"REL.orderByStable\",\"params\":{\"by\":[{\"dir\":\"asc\",\"field\":\"id\",\"nulls\":\"first\"}]}",
    ),
  )
}
