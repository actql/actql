///|
test "mean generator preserves ordered repeated samples and registered AoA body" {
  let graph = graph_match_carrier()
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"mean_graphs\":{\"with\":[\"peer\",\"g\",\"peer\"],\"weights\":[1,2,0],\"support\":{\"nodes\":1,\"edges\":0.5},\"properties\":{\"nodes\":{\"active\":\"exact_equal\"},\"edges\":{\"active\":\"exact_equal\"}}},\"as\":\"combined\"}]",
    ),
    [("g", graph), ("peer", graph)],
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
  let step = @pipeline.step_at(checked, 0).unwrap()
  assert_eq(step.input, None)
  for
    (index, target) in [
      (0, @pipeline.Input(1)),
      (1, @pipeline.Input(0)),
      (2, @pipeline.Input(1)),
    ] {
    let occurrence = @pipeline.input_occurrence_at(step, index).unwrap()
    assert_eq(occurrence.target, target)
    assert_eq(occurrence.role, @pipeline.Sample(index))
  }
  let obligations = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
  assert_eq(@pipeline.operation_obligations_count(obligations), 7)
  assert_true(
    @pipeline.operation_obligations_graph_mean(obligations) is Some(_),
  )
  assert_eq(
    @pipeline.operation_profile_requirement(
      @pipeline.operation_obligations_at(obligations, 0).unwrap(),
    ),
    Some(@pipeline.GraphProfile),
  )
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(checked, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let node = @lowering_relation.node_at(
    @lowering_relation.bound_preparation(owner),
    0,
  ).unwrap()
  assert_eq(@lowering_relation.operation(node), "SGA.mean_structural")
  assert_eq(@lowering_relation.node_input_count(node), 3)
  assert_true(@lowering_relation.node_can_split_carrier_transform(node))
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  assert_true(
    @lowering_relation.sequence_step(sequence, 0)
    is Some(@lowering_relation.GraphMeanStep(_)),
  )
  let writer = @encode.writer(20000, 2000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"mean_graphs_0\",\"in\":[\"input_1\",\"input_0\",\"input_1\"],\"op\":\"SGA.mean_structural\",\"params\":{\"weights\":[1,2,0],\"support\":{\"nodes\":1,\"edges\":0.5},\"properties\":{\"nodes\":{\"active\":\"exact_equal\"},\"edges\":{\"active\":\"exact_equal\"}}}}]",
  )
}
