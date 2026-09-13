///|
test "formal Graph operations reject missing resource closure at the owning step" {
  for
    body in [
      "{\"normalize_graph\":true}", "{\"degree\":{\"direction\":\"both\"}}", "{\"components\":{\"kind\":\"weak\"}}",
      "{\"components\":{\"kind\":\"strong\"}}", "{\"graph_bounds\":{\"max_nodes\":0}}",
    ] {
    let programs : Array[CheckedProgram] = []
    let suffix = if body == "{\"normalize_graph\":true}" {
      "," +
      body +
      ",{\"node_rows\":true},{\"derive\":{\"value\":\"id\"},\"as\":\"projected\"}"
    } else {
      "," +
      body +
      ",{\"select\":[{\"id\":\"" +
      (if body == "{\"degree\":{\"direction\":\"both\"}}" {
        "node"
      } else {
        "node_id"
      }) +
      "\"},{\"value\":\"" +
      (if body == "{\"degree\":{\"direction\":\"both\"}}" {
        "degree"
      } else if body == "{\"graph_bounds\":{\"max_nodes\":0}}" {
        "actual"
      } else {
        "component_size"
      }) +
      "\"}],\"as\":\"projected\"}"
    }
    try
      local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        sga=true,
        graph_construction_limit=Some(1000),
        generated_rows=Some("[{\"id\":1}]"),
        producer_suffix=",{\"graph\":{\"source\":\"id\",\"target\":\"value\"}}" +
          suffix,
        producer_result_from="projected",
        extra_step_budget=4,
      )
    catch {
      Closure(UnresolvedOperation(site)) => {
        assert_true(
          site.requirement is @pipeline.GraphRequirement(ResolveGraphResources),
        )
        assert_eq(site.stage, 0)
        assert_eq(site.step, 3)
      }
      Source(
        SourceView(
          Context(
            Stages(
              Capacity(
                stage,
                visit,
                ComponentsCollection(MissingApplication(step))
              )
            )
          )
        )
      ) => {
        assert_true(
          body == "{\"components\":{\"kind\":\"weak\"}}" ||
          body == "{\"components\":{\"kind\":\"strong\"}}",
        )
        assert_eq(stage, 0)
        assert_eq(visit, 0)
        assert_eq(step, 3)
      }
      other => raise other
    } noraise {
      _ => fail("unresolved Graph resources must not produce a CheckedProgram")
    }
    assert_eq(programs.length(), 0)
  }
}

///|
test "formal Graph construction reaches owned closure without exposing partial success" {
  for empty in [true, false] {
    let programs : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        sga=true,
        generated_rows=Some(if empty { "[]" } else { "[{\"id\":1}]" }),
        producer_suffix=",{\"graph\":{\"source\":\"id\",\"target\":\"value\"}},{\"node_rows\":true},{\"derive\":{\"value\":\"id\"},\"as\":\"projected\"}",
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
        sga=true,
        graph_construction_limit=Some(cap),
        generated_rows=Some(if empty { "[]" } else { "[{\"id\":1}]" }),
        producer_suffix=",{\"graph\":{\"source\":\"id\",\"target\":\"value\"}},{\"node_rows\":true},{\"derive\":{\"value\":\"id\"},\"as\":\"projected\"}",
        producer_result_from="projected",
        extra_step_budget=3,
      )
      assert_eq(programs.length(), 1)
      let program = programs[0]
      identities.push(unit_definition_cid(program, 0).unwrap())
      let operations = @context.stage_requirement_operations(
        requirements(program),
      )
      let mut found = 0
      for i in 0..<@context.operation_closure_count(operations) {
        guard @context.operation_closure_at(operations, i)
          is Some(ExecutionCheck(GraphConstructionExecution(check))) &&
          check.envelope is Some(envelope) else {
          continue
        }
        found += 1
        assert_true(check.rule is EnforceConstructionEnvelope)
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
      assert_true(found > 0)
    }
    assert_eq(identities[0], identities[1])
  }
}
