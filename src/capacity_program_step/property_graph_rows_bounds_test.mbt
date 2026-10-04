///|
test "Graph row bounds retain entity quantities instead of preserving Relation rows" {
  for
    (operation, quantity, law) in [
      ("node_rows", "nodes", "actql.bound.graph-node-rows"),
      ("edge_rows", "edges", "actql.bound.graph-edge-rows"),
    ] {
    let pipeline = graph_measure_pipeline(
      "[{\"values\":{\"schema\":{\"key\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"key\":1}]},\"as\":\"n\"},{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"n\",\"key\":[\"key\"],\"labels\":[]}],\"edges\":[{\"name\":\"E\",\"from\":\"n\",\"key\":[\"key\"],\"labels\":[],\"source\":{\"definition\":\"N\",\"key\":[\"key\"]},\"target\":{\"definition\":\"N\",\"key\":[\"key\"]}}]},\"as\":\"g\"},{\"" +
      operation +
      "\":true}]",
    )
    let seed = @capacity_program_step.check(
      pipeline,
      0,
      proof("actql.bound.values", 1L, "{\"op\":\"source\"}"),
    ).unwrap()
    let graph = @capacity_program_step.check_with_inputs(
      pipeline,
      1,
      measure_proof(
        1,
        "actql.bound.property-graph-" + quantity,
        quantity,
        1L,
        seed,
      ),
      [seed],
      max_operand_work=5,
    ).unwrap()
    let projected = @capacity_program_step.check_with_inputs(
      pipeline,
      2,
      measure_proof(2, law, "rows", 1L, graph),
      [graph],
    ).unwrap()
    assert_true(
      physical_equal(
        @capacity_program_step.input_at(projected, 0).unwrap(),
        graph,
      ),
    )
    assert_true(
      @capacity_program_step.check_with_inputs(
        pipeline,
        2,
        measure_proof(2, law, "rows", 2L, graph),
        [graph],
      )
      is Err(ValueMismatch),
    )
    let wrong = if quantity == "nodes" { "edges" } else { "nodes" }
    let other = @capacity_program_step.check_with_inputs(
      pipeline,
      1,
      measure_proof(1, "actql.bound.property-graph-" + wrong, wrong, 1L, seed),
      [seed],
      max_operand_work=5,
    ).unwrap()
    assert_true(
      @capacity_program_step.check_with_inputs(
        pipeline,
        2,
        measure_proof(2, law, "rows", 1L, other),
        [other],
      )
      is Err(InputUnitMismatch(0)),
    )
    assert_true(
      @capacity_program_step.check_with_inputs(
        pipeline,
        2,
        measure_proof(2, "actql.bound.match-nodes", "rows", 1L, graph),
        [graph],
      )
      is Err(LawMismatch),
    )
  }
}
