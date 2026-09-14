///|
test "Graph publication retains declared and derived node provenance through both row bridges" {
  for form in ["concise", "label", "completed", "shared", "split"] {
    for bridge in ["node_rows", "edge_rows"] {
      let named = form == "shared" || form == "split"
      let label = form == "label" || form == "completed"
      let steps = (if label {
          "{\"derive\":{\"edge_type\":\"to_string(id)\"}},"
        } else {
          ""
        }) +
        (if named {
          "{\"graph\":{\"nodes\":{\"from\":\"remote\",\"id\":\"id\",\"fields\":[]},\"edges\":{\"from\":\"" +
          (if form == "split" { "right" } else { "remote" }) +
          "\",\"source\":\"id\",\"target\":\"extra\",\"fields\":[]}},\"as\":\"g\"}"
        } else {
          "{\"graph\":{\"source\":\"id\",\"target\":\"extra\"" +
          (if form == "label" { ",\"label\":\"edge_type\"" } else { "" }) +
          "}}"
        }) +
        ",{\"" +
        bridge +
        "\":true},{\"select\":[{\"id\":\"" +
        (if bridge == "node_rows" { "id" } else { "src" }) +
        "\"}]}"
      let program = checked_direct_program_fixture(
        graph_steps=steps,
        graph_right=form == "split",
      )
      let unit = program.units[0]
      let policy = publication_source_policy(unit.publications[0]).unwrap()
      assert_eq(
        publication_policy_source_count(policy),
        if form == "split" {
          2
        } else {
          1
        },
      )
      assert_eq(publication_policy_carrier_step_count(policy), 2)
      let retained = publication_policy_carrier_step_at(policy, 1).unwrap()
      guard retained.operation
        is GraphConstruction(nodes~, edges~, checked=operation) else {
        fail("Graph construction lost")
      }
      assert_eq(nodes is Some(_), named)
      assert_eq(retained.step, if label { 1 } else { 0 })
      assert_false(retained.unknown_provenance)
      guard @pipeline.step_at(unit.pipeline, retained.step).unwrap().operation
        is GraphConstruction(checked=original, ..) else {
        fail("original graph owner lost")
      }
      assert_true(physical_equal(operation, original))
      let mut occurrences = 0
      for i in 0..<publication_policy_edge_count(policy) {
        let edge = publication_policy_edge_at(policy, i).unwrap()
        if edge.step == retained.step {
          let original = @pipeline.input_occurrence_at(
            @pipeline.step_at(unit.pipeline, retained.step).unwrap(),
            occurrences,
          ).unwrap()
          assert_eq(edge.occurrence.role, original.role)
          assert_eq(edge.occurrence.target, original.target)
          occurrences += 1
        }
      }
      assert_eq(occurrences, if named { 2 } else { 1 })
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut declared = 0
      let mut derived = 0
      let mut envelopes = 0
      let mut completed = 0
      for i in 0..<@context.operation_closure_count(closure) {
        if @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(GraphConstructionExecution(check))) {
          assert_true(physical_equal(check.operation, operation))
          assert_true(physical_equal(check.site.pipeline, unit.pipeline))
          assert_eq(check.nodes, nodes)
          assert_eq(check.edges, edges)
          assert_eq(
            @context.operation_execution_failure(
              GraphConstructionExecution(check),
            ),
            RejectOperationOutput,
          )
          match check.rule {
            CloseDeclaredEndpoints => declared += 1
            DeriveEndpointNodes => derived += 1
            JournalLabels => completed += 1
            EnforceConstructionEnvelope => {
              let envelope = check.envelope.unwrap()
              assert_eq(@policy.ceiling_value(envelope.input_rows), 1000L)
              assert_eq(@policy.ceiling_value(envelope.output_nodes), 1000L)
              assert_eq(@policy.ceiling_value(envelope.output_edges), 1000L)
              envelopes += 1
            }
            _ => ()
          }
        }
      }
      assert_eq((declared, derived), if named { (1, 0) } else { (0, 1) })
      assert_eq(completed, if form == "completed" { 1 } else { 0 })
      assert_eq(envelopes, 1)
    }
  }
}

///|
test "Graph publication cannot replace missing construction resource selection" {
  try
    checked_direct_program_fixture(
      graph_steps="{\"graph\":{\"source\":\"id\",\"target\":\"extra\"}},{\"node_rows\":true}",
      graph_resources=false,
    )
  catch {
    Closure(UnresolvedOperation(site)) => {
      assert_eq((site.stage, site.step), (0, 0))
      assert_true(
        site.requirement
        is @pipeline.ConstructionRequirement(ResolveGraphConstructionResources),
      )
    }
    error => raise error
  } noraise {
    _ => fail("publication cannot waive construction ceilings")
  }
}
