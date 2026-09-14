///|
test "Graph structural operations retain source policy and exact execution ownership" {
  for
    body in [
      "{\"normalize_graph\":true}", "{\"degree\":{\"direction\":\"in\"}}", "{\"degree\":{\"direction\":\"out\"}}",
      "{\"degree\":{\"direction\":\"both\"}}", "{\"graph_bounds\":{\"max_nodes\":0}}",
      "{\"graph_bounds\":{\"max_edges\":1,\"max_degree\":2}}",
    ] {
    let normalize = body.contains("normalize_graph")
    let bounds = body.contains("graph_bounds")
    let steps = "{\"graph\":{\"source\":\"id\",\"target\":\"extra\"}}," +
      body +
      (if normalize { ",{\"node_rows\":true}" } else { "" }) +
      ",{\"select\":[{\"id\":\"" +
      (if normalize { "id" } else if bounds { "node_id" } else { "node" }) +
      "\"}]}"
    let program = checked_direct_program_fixture(graph_steps=steps)
    let unit = program.units[0]
    let policy = publication_source_policy(unit.publications[0]).unwrap()
    assert_eq(publication_policy_source_count(policy), 1)
    let retained = publication_policy_carrier_step_at(
      policy,
      if normalize {
        1
      } else {
        0
      },
    ).unwrap()
    guard retained.operation is Graph(operation) else {
      fail("Graph operation lost")
    }
    assert_eq(retained.step, 1)
    assert_eq(retained.unknown_provenance, bounds)
    guard @pipeline.step_at(unit.pipeline, 1).unwrap().operation
      is Graph(original) else {
      fail("Graph original lost")
    }
    assert_true(physical_equal(operation, original))
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut admissions = 0
    for i in 0..<@context.operation_closure_count(closure) {
      if @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(GraphExecution(check))) &&
        check.rule == AdmitGraphData {
        assert_true(physical_equal(check.operation, operation))
        assert_true(physical_equal(check.site.pipeline, unit.pipeline))
        assert_eq(check.input, Step(0))
        admissions += 1
      }
    }
    assert_eq(admissions, 1)
  }
}

///|
test "SourceView components retain policy and explicit producer capacity material" {
  for kind in ["weak", "strong"] {
    for guarded in [false, true] {
      let steps = "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"nodes\"},{\"from\":\"remote\",\"derive\":{\"value\":\"extra\"},\"as\":\"edges\"},{\"graph\":{\"nodes\":{\"from\":\"nodes\",\"id\":\"id\"},\"edges\":{\"from\":\"edges\",\"source\":\"id\",\"target\":\"value\"}},\"as\":\"g\"},{\"components\":{\"kind\":\"" +
        kind +
        "\"" +
        (if guarded { ",\"max_output_rows\":2" } else { "" }) +
        "}},{\"select\":[{\"id\":\"node_id\"}]}"
      if guarded {
        // The current capacity constructor has no author-source binding path.
        // Publication policy must not bypass that unresolved requirement.
        let rejected = try {
          let _ = checked_direct_program_fixture(
            graph_steps=steps,
            graph_components=true,
          )
          false
        } catch {
          Source(
            SourceView(
              Context(
                Stages(Capacity(_, _, Components(_, UnresolvedAuthorSource)))
              )
            )
          ) => true
          error => raise error
        }
        assert_true(rejected)
        continue
      }
      let program = checked_direct_program_fixture(
        graph_steps=steps,
        graph_components=true,
      )
      let unit = program.units[0]
      let policy = publication_source_policy(unit.publications[0]).unwrap()
      assert_eq(publication_policy_source_count(policy), 1)
      assert_eq(publication_policy_generator_count(policy), 1)
      let retained = publication_policy_carrier_step_at(policy, 0).unwrap()
      guard retained.operation is Graph(operation) else {
        fail("components lost")
      }
      assert_eq(@graph.operation(operation), Components)
      assert_eq(retained.step, 3)
      assert_eq(retained.unknown_provenance, guarded)
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut orders = 0
      for i in 0..<@context.operation_closure_count(closure) {
        if @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(GraphExecution(check))) &&
          check.rule == OrderComponentIdentities {
          assert_true(physical_equal(check.operation, operation))
          orders += 1
        }
      }
      assert_eq(orders, 1)
    }
  }
}
