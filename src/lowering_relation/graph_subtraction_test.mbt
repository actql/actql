///|
test "subtraction lowers two ordered operands without a union identity" {
  let graph = graph_match_carrier()
  let checked = @pipeline.check_carriers(
    cursor("[{\"from\":\"g\",\"subtract_graphs\":{\"with\":\"g\"}}]"),
    [("g", graph)],
    None,
    None,
    {
      max_steps: 100,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 4000,
    },
  ).unwrap()
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  assert_true(
    @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphSubtractionStep(_)),
  )
  let writer = @encode.writer(20000, 2000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"subtract_graphs_0\",\"in\":[\"input_0\",\"input_0\"],\"op\":\"SGA.diff_structural\",\"params\":{}}]",
  )
}
