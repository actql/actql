///|
test "Graph path policy retains selectors and independent search limits" {
  for shortest in [false, true] {
    for mode in 0..<4 {
      for patterned in [false, true] {
        let selector = match mode {
          0 => "{\"ids\":[1]}"
          1 => "{\"from\":\"remote\",\"id\":\"id\"}"
          2 => "{\"from\":\"right\",\"id\":\"id\"}"
          _ => "{\"where\":{\"literal\":false}}"
        }
        let operation = if shortest {
          "{\"shortest_path\":{\"source\":" +
          selector +
          ",\"target\":{\"from\":\"remote\",\"id\":\"id\"},\"selection\":\"each_pair\",\"direction\":\"both\",\"max_hops\":2" +
          (if patterned { ",\"weight\":\"value\"" } else { "" }) +
          "}}"
        } else {
          "{\"traverse\":{\"start\":" +
          selector +
          "," +
          (if patterned {
            "\"hops\":[{\"direction\":\"out\",\"node_where\":\"node_id = node_id\",\"edge_where\":\"id = id\"}]"
          } else {
            "\"direction\":\"out\",\"min_hops\":0,\"max_hops\":2"
          }) +
          ",\"emit\":\"nodes\"}}"
        }
        let steps = "{\"from\":\"remote\",\"derive\":{\"value\":\"extra\"}},{\"filter\":\"id = id\"},{\"graph\":{\"source\":\"id\",\"target\":\"value\"}}," +
          operation +
          ",{\"select\":[{\"id\":\"" +
          (if shortest { "source_id" } else { "start_id" }) +
          "\"}]}"
        let program = checked_direct_program_fixture(
          graph_steps=steps,
          graph_right=mode == 2,
          graph_traversal=if shortest { "shortest_path" } else { "traverse" },
        )
        let unit = program.units[0]
        let policy = publication_source_policy(unit.publications[0]).unwrap()
        assert_eq(
          publication_policy_source_count(policy),
          if mode == 2 {
            2
          } else {
            1
          },
        )
        let retained = publication_policy_carrier_step_at(policy, 0).unwrap()
        assert_eq(retained.step, 3)
        assert_eq(
          retained.unknown_provenance,
          shortest || !patterned || mode == 0 || mode == 3,
        )
        let step = @pipeline.step_at(unit.pipeline, 3).unwrap()
        match (retained.operation, step.operation) {
          (Traverse(checked=a, ..), Traverse(checked=b, ..)) =>
            assert_true(physical_equal(a, b))
          _ => fail("path operation lost")
        }
        let mut edges = 0
        for i in 0..<publication_policy_edge_count(policy) {
          if publication_policy_edge_at(policy, i).unwrap().step == 3 {
            edges += 1
          }
        }
        assert_eq(
          edges,
          1 +
          (if mode == 1 || mode == 2 { 1 } else { 0 }) +
          (if shortest { 1 } else { 0 }),
        )
        let limit = unit_traversal_limit_at(program, 0, 0).unwrap()
        assert_true(physical_equal(traversal_limit_selection(limit).step, step))
        for scope in [@step_bounds.SearchPaths, @step_bounds.OutputRows] {
          assert_eq(
            @derivation.minimum_value(
              @wire.limit_minimum(traversal_limit_claim(limit, scope)),
            ),
            1000L,
          )
        }
      }
    }
  }
}
