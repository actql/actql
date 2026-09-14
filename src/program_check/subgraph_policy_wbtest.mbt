///|
test "subgraph policy retains Graph and selector inputs independently" {
  for mode in 0..<4 {
    for edge_predicate in [false, true] {
      let selector = match mode {
        0 => "{\"ids\":[1,1]}"
        1 => "{\"where\":\"node_id = node_id\"}"
        2 => "{\"from\":\"remote\",\"id\":\"id\"}"
        _ => "{\"from\":\"right\",\"id\":\"id\"}"
      }
      let steps = "{\"from\":\"remote\",\"graph\":{\"source\":\"id\",\"target\":\"extra\"}},{\"subgraph\":{\"nodes\":" +
        selector +
        (if edge_predicate { ",\"edges\":{\"literal\":false}" } else { "" }) +
        "}},{\"node_rows\":true}"
      let program = checked_direct_program_fixture(
        graph_steps=steps,
        graph_right=mode == 3,
      )
      let unit = program.units[0]
      let policy = publication_source_policy(unit.publications[0]).unwrap()
      assert_eq(
        publication_policy_source_count(policy),
        if mode == 3 {
          2
        } else {
          1
        },
      )
      let retained = publication_policy_carrier_step_at(policy, 1).unwrap()
      assert_eq(retained.step, 1)
      assert_eq(retained.unknown_provenance, mode == 0 || edge_predicate)
      guard retained.operation is Subgraph(selector~, checked=operation) else {
        fail("subgraph lost")
      }
      assert_eq(selector is Some(_), mode >= 2)
      guard @pipeline.step_at(unit.pipeline, 1).unwrap().operation
        is Subgraph(checked=original, ..) else {
        fail("original subgraph lost")
      }
      assert_true(physical_equal(operation, original))
      let mut edges = 0
      for i in 0..<publication_policy_edge_count(policy) {
        let edge = publication_policy_edge_at(policy, i).unwrap()
        if edge.step == 1 {
          assert_eq(
            edge.occurrence.target,
            if edges == 0 {
              Step(0)
            } else {
              Input(0)
            },
          )
          edges += 1
        }
      }
      assert_eq(edges, if mode >= 2 { 2 } else { 1 })
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut scopes = 0
      for i in 0..<@context.operation_closure_count(closure) {
        if @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(SubgraphExecution(check))) {
          assert_true(physical_equal(check.operation, operation))
          assert_eq(check.selector_relation, selector)
          assert_eq(check.input, Step(0))
          if check.rule == PreservePolicyAndScope {
            scopes += 1
          }
        }
      }
      assert_eq(scopes, 1)
    }
  }
}
