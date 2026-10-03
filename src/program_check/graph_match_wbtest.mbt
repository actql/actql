///|
test "formal Property Graph matches retain definition labels selectors and resources through imports" {
  for empty in [true, false] {
    for
      (body, node, types, predicate) in [
        (
          "{\"match_nodes\":{\"definition\":\"N\",\"label\":\"Node\",\"where\":\"id = id\",\"fields\":[\"id\"]}}",
          true,
          None,
          true,
        ),
        (
          "{\"match_nodes\":{\"definition\":\"N\",\"where\":\"id > 0\",\"fields\":[\"id\"]}}",
          true,
          None,
          true,
        ),
        (
          "{\"match_edges\":{\"definition\":\"E\",\"label\":\"R\",\"fields\":[\"id\",\"value\"]}}",
          false,
          None,
          false,
        ),
        (
          "{\"match_edges\":{\"definition\":\"E\",\"types\":[],\"where\":\"id > 0\",\"fields\":[\"id\",\"value\"]}}",
          false,
          Some(0),
          true,
        ),
        (
          "{\"match_edges\":{\"definition\":\"E\",\"types\":[\"R\",\"R\"],\"fields\":[\"id\",\"value\"]}}",
          false,
          Some(2),
          false,
        ),
      ] {
      let programs : Array[CheckedProgram] = []
      let suffix = if node {
        ",{\"derive\":{\"value\":\"id\"},\"as\":\"projected\"}"
      } else {
        ",{\"select\":[\"id\",\"value\"],\"as\":\"projected\"}"
      }
      let _ = local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        property_graph=true,
        graph_construction_limit=Some(1000),
        graph_input_limit=Some(1),
        graph_output_limit=Some(1),
        generated_rows=Some(if empty { "[]" } else { "[{\"id\":1}]" }),
        producer_suffix="," +
          (
            #|{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"seed","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[{"name":"E","from":"derived","key":["id"],"source":{"definition":"N","key":["id"]},"target":{"definition":"N","key":["id"]},"labels":[{"name":"R","properties":{"mode":"all_columns"}}]}]},"as":"g"},
          ) +
          body +
          suffix,
        producer_result_from="projected",
        extra_step_budget=3,
      )
      let program = programs[0]
      let producer = unit_pipeline(program, 0).unwrap()
      let checks = @context.stage_requirement_operations(requirements(program))
      let counts = Array::make(6, 0)
      for i in 0..<@context.operation_closure_count(checks) {
        guard @context.operation_closure_at(checks, i)
          is Some(ExecutionCheck(GraphMatchExecution(check))) else {
          continue
        }
        assert_true(physical_equal(check.site.pipeline, producer))
        assert_eq(check.site.step, 3)
        assert_eq(check.input, @pipeline.Step(2))
        assert_eq(@graph.match_property_definition(check.operation), 0)
        assert_eq(
          @graph.match_property_definition_name(check.operation),
          if node {
            "N"
          } else {
            "E"
          },
        )
        assert_eq(@graph.match_id_count(check.operation), 0)
        assert_true(@graph.match_id_at(check.operation, -1) is None)
        assert_true(@graph.match_id_at(check.operation, 0) is None)
        @graph.match_ids(check.operation).clear()
        assert_eq(@graph.match_id_count(check.operation), 0)
        assert_eq(@graph.match_type_count(check.operation), types)
        if types == Some(2) {
          assert_eq(@graph.match_type_at(check.operation, 0), Some("R"))
          assert_eq(@graph.match_type_at(check.operation, 1), Some("R"))
          @graph.match_types(check.operation).unwrap().clear()
          assert_eq(@graph.match_type_count(check.operation), Some(2))
        }
        assert_true(@graph.match_type_at(check.operation, -1) is None)
        assert_true(
          @graph.match_type_at(check.operation, types.unwrap_or(0)) is None,
        )
        assert_eq(
          @policy.ceiling_field(check.output_rows),
          "max_relation_output_rows",
        )
        assert_eq(@policy.ceiling_value(check.output_rows), 1000L)
        assert_true(
          physical_equal(
            @policy.ceiling_policy(check.output_rows),
            check.policy,
          ),
        )
        let index = match check.rule {
          AdmitGraph => 0
          SelectExistingIdentities => 1
          FilterEdgeTypes => 2
          EvaluatePredicate => 3
          OrderMatches => 4
          EnforceMatchResources => 5
        }
        counts[index] += 1
        assert_eq(
          @context.operation_execution_phase(GraphMatchExecution(check)),
          if index == 0 || index == 5 {
            BeforeOperationInputUse
          } else {
            BeforeOperationOutput
          },
        )
        assert_eq(
          @context.operation_execution_failure(GraphMatchExecution(check)),
          RejectOperationOutput,
        )
        assert_eq(
          @context.graph_match_resource_count(check),
          if index == 5 {
            3
          } else {
            0
          },
        )
        if index == 5 {
          for
            j, resource in [
              @context.GraphComparisonResource::ComparisonWork,
              RetainedComparisonState,
              InputAndTemporaryBytes,
            ] {
            assert_eq(
              @context.graph_match_resource_at(check, j),
              Some(resource),
            )
          }
        }
      }
      assert_eq(counts[0], 3)
      assert_eq(counts[1], 0)
      assert_eq(counts[2], if types is Some(_) { 3 } else { 0 })
      assert_eq(counts[3], if predicate { 3 } else { 0 })
      assert_eq(counts[4], 3)
      assert_eq(counts[5], 3)
      assert_true(unit_publication_at(program, 1, 0) is Some(_))
    }
  }
}
