///|
test "Graph binary operations retain both source policies and repeated union inputs" {
  for separate in [false, true] {
    for
      name in [
        "graphs_equal", "graph_diff", "apply_graph_delta", "graft_graph", "subtract_graphs",
        "union_graphs",
      ] {
      let prefix = "{\"from\":\"remote\",\"graph\":{\"source\":\"id\",\"target\":\"extra\"},\"as\":\"g\"},{\"from\":\"" +
        (if separate { "right" } else { "remote" }) +
        "\",\"graph\":{\"source\":\"id\",\"target\":\"extra\"},\"as\":\"other\"},"
      let suffix = match name {
        "graphs_equal" =>
          "{\"from\":\"g\",\"graphs_equal\":{\"with\":\"other\"}},{\"select\":[{\"id\":\"equal\"}]}"
        "graph_diff" =>
          "{\"from\":\"g\",\"graph_diff\":{\"with\":\"other\"}},{\"derive\":{\"id\":\"delta.base_graph_cid\"}}"
        "apply_graph_delta" =>
          "{\"from\":\"g\",\"graph_diff\":{\"with\":\"other\"},\"as\":\"changes\"},{\"from\":\"g\",\"apply_graph_delta\":{\"with\":\"changes\",\"field\":\"delta\"}},{\"node_rows\":true}"
        "union_graphs" =>
          "{\"from\":\"g\",\"union_graphs\":{\"with\":[\"other\",\"g\",\"other\"]}},{\"node_rows\":true}"
        _ =>
          "{\"from\":\"g\",\"" +
          name +
          "\":{\"with\":\"other\"}},{\"node_rows\":true}"
      }
      let program = checked_direct_program_fixture(
        graph_steps=prefix + suffix,
        graph_right=separate,
      )
      let unit = program.units[0]
      let policy = publication_source_policy(unit.publications[0]).unwrap()
      assert_eq(
        publication_policy_source_count(policy),
        if separate {
          2
        } else {
          1
        },
      )
      let step = if name == "apply_graph_delta" { 3 } else { 2 }
      let mut found = 0
      for i in 0..<publication_policy_carrier_step_count(policy) {
        let retained = publication_policy_carrier_step_at(policy, i).unwrap()
        if retained.step == step {
          found += 1
          assert_false(retained.unknown_provenance)
          match
            (
              retained.operation,
              @pipeline.step_at(unit.pipeline, step).unwrap().operation,
            ) {
            (GraphEquality(checked=a, ..), GraphEquality(checked=b, ..)) =>
              assert_true(physical_equal(a, b))
            (GraphDiff(checked=a, ..), GraphDiff(checked=b, ..)) =>
              assert_true(physical_equal(a, b))
            (GraphApply(checked=a, ..), GraphApply(checked=b, ..)) =>
              assert_true(physical_equal(a, b))
            (GraphStructural(checked=a, ..), GraphStructural(checked=b, ..)) =>
              assert_true(physical_equal(a, b))
            (GraphUnion(a), GraphUnion(b)) => assert_true(physical_equal(a, b))
            _ => fail("binary Graph owner lost")
          }
        }
      }
      assert_eq(found, 1)
      let targets = []
      for i in 0..<publication_policy_edge_count(policy) {
        let edge = publication_policy_edge_at(policy, i).unwrap()
        if edge.step == step {
          targets.push(edge.occurrence.target)
        }
      }
      assert_eq(
        targets,
        if name == "union_graphs" {
          [Step(0), Step(1), Step(0), Step(1)]
        } else if name == "apply_graph_delta" {
          [Step(0), Step(2)]
        } else {
          [Step(0), Step(1)]
        },
      )
    }
  }
}
