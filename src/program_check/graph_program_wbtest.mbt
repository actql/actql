///|
test "formal Graph construction reaches owned closure without exposing partial success" {
  for empty in [true, false] {
    let programs : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        graph=true,
        generated_rows=Some(if empty { "[]" } else { "[{\"id\":1}]" }),
        producer_suffix="," +
          (
            #|{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"seed","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[]},"as":"g"},{"match_nodes":{"definition":"N","label":"Node","where":"true","fields":["id"]}},{"derive":{"value":"id"},"as":"projected"}
          ),
        producer_result_from="projected",
        extra_step_budget=3,
      )
    catch {
      Closure(UnresolvedOperation(site)) => {
        assert_true(
          site.requirement
          is @pipeline.ConstructionRequirement(
            ResolveGraphConstructionResources
          ),
        )
        assert_eq(site.step, 2)
        assert_eq(site.stage, 0)
        assert_eq(site.index, 3)
        assert_true(
          @pipeline.step_at(site.pipeline, site.step).unwrap().operation
          is @pipeline.GraphConstruction(..),
        )
      }
      other => raise other
    } noraise {
      _ => fail("expected incomplete Graph closure")
    }
    assert_eq(programs.length(), 0)
  }
}

///|
test "formal Graph construction with selected resource scopes reaches Result" {
  for empty in [true, false] {
    let identities : Array[String] = []
    for cap in [1, 1000] {
      let programs : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        graph=true,
        graph_construction_limit=Some(cap),
        generated_rows=Some(if empty { "[]" } else { "[{\"id\":1}]" }),
        producer_suffix="," +
          (
            #|{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"seed","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[]},"as":"g"},{"match_nodes":{"definition":"N","label":"Node","where":"true","fields":["id"]}},{"derive":{"value":"id"},"as":"projected"}
          ),
        producer_result_from="projected",
        extra_step_budget=3,
      )
      assert_eq(programs.length(), 1)
      let program = programs[0]
      identities.push(unit_definition_cid(program, 0).unwrap())
      let operations = @context.stage_requirement_operations(
        requirements(program),
      )
      let producer = unit_pipeline(program, 0).unwrap()
      let original_step = @pipeline.step_at(producer, 2).unwrap()
      let mut found = 0
      let mut root_visits = 0
      let mut imported_visits = 0
      for i in 0..<@context.operation_closure_count(operations) {
        guard @context.operation_closure_at(operations, i)
          is Some(ExecutionCheck(GraphConstructionExecution(check))) &&
          check.envelope is Some(envelope) else {
          continue
        }
        found += 1
        assert_eq(check.site.step, 2)
        assert_true(physical_equal(check.step, original_step))
        if check.site.stage == 0 {
          root_visits += 1
        } else {
          assert_eq(check.site.stage, 1)
          imported_visits += 1
        }
        assert_true(check.rule is EnforcePropertyConstructionEnvelope)
        assert_true(
          physical_equal(
            check.site.pipeline,
            unit_pipeline(program, 0).unwrap(),
          ),
        )
        for
          (ceiling, field) in [
            (envelope.input_rows, "max_graph_construction_input_rows"),
            (envelope.output_nodes, "max_graph_construction_nodes"),
            (envelope.output_edges, "max_graph_construction_edges"),
          ] {
          assert_eq(@policy.ceiling_field(ceiling), field)
          assert_eq(@policy.ceiling_value(ceiling), cap.to_int64())
          assert_true(
            physical_equal(@policy.ceiling_policy(ceiling), envelope.policy),
          )
        }
      }
      // Two imported Results retain the original constructor and policy;
      // equal content is not a substitute producer owner.
      assert_eq(found, 3)
      assert_eq(root_visits, 1)
      assert_eq(imported_visits, 2)
      assert_true(unit_publication_at(program, 0, 0) is Some(_))
      assert_true(unit_publication_at(program, 1, 0) is Some(_))
    }
    assert_eq(identities[0], identities[1])
  }
}
