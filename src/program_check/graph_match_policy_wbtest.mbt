///|
test "Graph matches preserve source policy and selector value provenance" {
  for
    (body, node, unknown) in [
      ("{\"match_nodes\":{\"ids\":[1,1],\"fields\":[\"node_id\"]}}", true, true),
      (
        "{\"match_nodes\":{\"where\":\"node_id = node_id\",\"fields\":[\"node_id\"]}}",
        true, false,
      ),
      (
        "{\"match_nodes\":{\"where\":\"node_id > 0\",\"fields\":[\"node_id\"]}}",
        true, true,
      ),
      ("{\"match_edges\":{\"fields\":[\"id\"]}}", false, false),
      ("{\"match_edges\":{\"types\":[],\"fields\":[\"id\"]}}", false, false),
      (
        "{\"match_edges\":{\"types\":[\"x\",\"x\"],\"fields\":[\"id\"]}}", false,
        true,
      ),
      (
        "{\"match_edges\":{\"types\":[],\"where\":\"id > 0\",\"fields\":[\"id\"]}}",
        false, true,
      ),
    ] {
    let steps = "{\"graph\":{\"source\":\"id\",\"target\":\"extra\"}}," +
      body +
      (if node { ",{\"select\":[{\"id\":\"node_id\"}]}" } else { "" })
    let program = checked_direct_program_fixture(graph_steps=steps)
    let unit = program.units[0]
    let policy = publication_source_policy(unit.publications[0]).unwrap()
    assert_eq(publication_policy_source_count(policy), 1)
    let retained = publication_policy_carrier_step_at(policy, 0).unwrap()
    assert_eq(retained.step, 1)
    assert_eq(retained.unknown_provenance, unknown)
    guard retained.operation is GraphMatch(operation) else {
      fail("match owner lost")
    }
    guard @pipeline.step_at(unit.pipeline, 1).unwrap().operation
      is GraphMatch(original) else {
      fail("original match lost")
    }
    assert_true(physical_equal(original, operation))
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut admission = 0
    let mut resources = 0
    for i in 0..<@context.operation_closure_count(closure) {
      if @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(GraphMatchExecution(check))) {
        assert_true(physical_equal(check.operation, operation))
        assert_true(physical_equal(check.site.pipeline, unit.pipeline))
        assert_eq(check.input, Step(0))
        if check.rule == AdmitGraph {
          admission += 1
        }
        if check.rule == EnforceMatchResources {
          resources += 1
          assert_eq(@context.graph_match_resource_count(check), 3)
          assert_eq(@policy.ceiling_value(check.output_rows), 1000L)
        }
      }
    }
    assert_eq(admission, 1)
    assert_eq(resources, 1)
  }
}
