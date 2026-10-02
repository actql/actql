///|
test "formal common Graph resources retain producer ownership through Result imports" {
  for empty in [true, false] {
    for
      body in [
        "{\"normalize_graph\":true}", "{\"degree\":{\"direction\":\"both\"}}", "{\"components\":{\"kind\":\"weak\"}}",
        "{\"components\":{\"kind\":\"strong\"}}", "{\"graph_bounds\":{\"max_nodes\":0}}",
      ] {
      let programs : Array[CheckedProgram] = []
      let component = body.contains("components")
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
          second_stage=true,
          sga=true,
          graph_construction_limit=Some(1000),
          graph_input_limit=Some(1),
          graph_output_limit=Some(1),
          generated_rows=Some(if empty { "[]" } else { "[{\"id\":1}]" }),
          producer_suffix=",{\"graph\":{\"source\":\"id\",\"target\":\"value\"}}" +
            suffix,
          producer_result_from="projected",
          extra_step_budget=4,
        )
      catch {
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
        _ => assert_false(component)
      }
      assert_eq(programs.length(), if component { 0 } else { 1 })
      if !component {
        assert_eq(unit_count(programs[0]), 2)
        assert_true(unit_publication_at(programs[0], 0, 0) is Some(_))
        assert_true(unit_publication_at(programs[0], 1, 0) is Some(_))
        let producer = unit_pipeline(programs[0], 0).unwrap()
        let producer_step = @pipeline.step_at(producer, 3).unwrap()
        let operations = @context.stage_requirement_operations(
          requirements(programs[0]),
        )
        let mut found = 0
        let mut root_visits = 0
        let mut imported = 0
        for i in 0..<@context.operation_closure_count(operations) {
          if @context.operation_closure_at(operations, i)
            is Some(ExecutionCheck(GraphResources(check))) {
            found += 1
            assert_eq(check.site.step, 3)
            assert_eq(check.input, @pipeline.Step(2))
            assert_true(physical_equal(check.step, producer_step))
            if check.site.stage == 0 {
              root_visits += 1
            } else {
              assert_eq(check.site.stage, 1)
              imported += 1
            }
            assert_true(physical_equal(check.site.pipeline, producer))
            match check.scope {
              PreserveGraph => assert_true(body.contains("normalize_graph"))
              RelationRows(limit) => {
                assert_false(body.contains("normalize_graph"))
                assert_eq(
                  @policy.ceiling_field(limit),
                  "max_relation_output_rows",
                )
                assert_eq(@policy.ceiling_value(limit), 1000L)
                assert_true(
                  physical_equal(@policy.ceiling_policy(limit), check.policy),
                )
              }
            }
          }
        }
        // The consumer imports two Results from the same producer. Both visits
        // retain that producer's operation rather than rebinding it locally.
        assert_eq(found, 3)
        assert_eq(root_visits, 1)
        assert_eq(imported, 2)
      }
    }
  }
}

///|
test "formal Property Graph construction reaches owned closure without exposing partial success" {
  for empty in [true, false] {
    let programs : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        property_graph=true,
        generated_rows=Some(if empty { "[]" } else { "[{\"id\":1}]" }),
        producer_suffix="," +
          (
            #|{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"seed","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[]},"as":"g"},{"match_nodes":{"definition":"N","label":"Node","where":"true","fields":["id"]}},{"derive":{"value":"id"},"as":"projected"}
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
          is @pipeline.PropertyGraphConstruction(..),
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
test "formal Property Graph construction with selected resource scopes reaches Result" {
  for empty in [true, false] {
    let identities : Array[String] = []
    for cap in [1, 1000] {
      let programs : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        property_graph=true,
        graph_construction_limit=Some(cap),
        generated_rows=Some(if empty { "[]" } else { "[{\"id\":1}]" }),
        producer_suffix="," +
          (
            #|{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"seed","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[]},"as":"g"},{"match_nodes":{"definition":"N","label":"Node","where":"true","fields":["id"]}},{"derive":{"value":"id"},"as":"projected"}
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
      let mut found = 0
      for i in 0..<@context.operation_closure_count(operations) {
        guard @context.operation_closure_at(operations, i)
          is Some(ExecutionCheck(PropertyGraphConstructionExecution(check))) &&
          check.envelope is Some(envelope) else {
          continue
        }
        found += 1
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
      assert_true(found > 0)
    }
    assert_eq(identities[0], identities[1])
  }
}
