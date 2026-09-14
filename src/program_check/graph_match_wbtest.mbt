///|
test "formal Graph matches retain selector distinctions and resources through imports" {
  for empty in [true, false] {
    for
      (body, node, ids, types, predicate) in [
        (
          "{\"match_nodes\":{\"ids\":[1,1],\"fields\":[\"node_id\"]}}",
          true,
          2,
          None,
          false,
        ),
        (
          "{\"match_nodes\":{\"where\":\"node_id > 0\",\"fields\":[\"node_id\"]}}",
          true,
          0,
          None,
          true,
        ),
        (
          "{\"match_edges\":{\"fields\":[\"id\",\"value\"]}}",
          false,
          0,
          None,
          false,
        ),
        (
          "{\"match_edges\":{\"types\":[],\"where\":\"id > 0\",\"fields\":[\"id\",\"value\"]}}",
          false,
          0,
          Some(0),
          true,
        ),
        (
          "{\"match_edges\":{\"types\":[\"x\",\"x\"],\"fields\":[\"id\",\"value\"]}}",
          false,
          0,
          Some(2),
          false,
        ),
      ] {
      let programs : Array[CheckedProgram] = []
      let suffix = if node {
        ",{\"select\":[{\"id\":\"node_id\"},{\"value\":\"node_id\"}],\"as\":\"projected\"}"
      } else {
        ",{\"select\":[\"id\",\"value\"],\"as\":\"projected\"}"
      }
      let _ = local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        sga=true,
        graph_construction_limit=Some(1000),
        graph_input_limit=Some(1),
        graph_output_limit=Some(1),
        generated_rows=Some(if empty { "[]" } else { "[{\"id\":1}]" }),
        producer_suffix=",{\"graph\":{\"source\":\"id\",\"target\":\"value\"}}," +
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
        assert_eq(@graph.match_id_count(check.operation), ids)
        assert_true(@graph.match_id_at(check.operation, -1) is None)
        assert_true(@graph.match_id_at(check.operation, ids) is None)
        if ids > 0 {
          assert_true(@graph.match_id_at(check.operation, 0) is Some(_))
        }
        @graph.match_ids(check.operation).clear()
        assert_eq(@graph.match_id_count(check.operation), ids)
        assert_eq(@graph.match_type_count(check.operation), types)
        if types == Some(2) {
          assert_eq(@graph.match_type_at(check.operation, 0), Some("x"))
          assert_eq(@graph.match_type_at(check.operation, 1), Some("x"))
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
      assert_eq(counts[1], if ids > 0 { 3 } else { 0 })
      assert_eq(counts[2], if types is Some(_) { 3 } else { 0 })
      assert_eq(counts[3], if predicate { 3 } else { 0 })
      assert_eq(counts[4], 3)
      assert_eq(counts[5], 3)
      assert_true(unit_publication_at(program, 1, 0) is Some(_))
    }
  }
}
