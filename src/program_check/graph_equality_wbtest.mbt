///|
test "formal Graph equality retains both operands and resource requirements across imports" {
  for empty in [true, false] {
    for self_comparison in [true, false] {
      let programs : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        sga=true,
        graph_construction_limit=Some(1000),
        generated_rows=Some(if empty { "[]" } else { "[{\"id\":1}]" }),
        producer_suffix=",{\"graph\":{\"source\":\"id\",\"target\":\"value\"},\"as\":\"g\"},{\"normalize_graph\":true,\"as\":\"other\"},{\"graphs_equal\":{\"with\":\"" +
          (if self_comparison { "other" } else { "g" }) +
          "\"}},{\"select\":[{\"id\":\"equal\"},{\"value\":\"equal\"}],\"as\":\"projected\"}",
        producer_result_from="projected",
        extra_step_budget=4,
      )
      assert_eq(programs.length(), 1)
      let program = programs[0]
      assert_eq(unit_count(program), 2)
      let producer = unit_pipeline(program, 0).unwrap()
      let step = @pipeline.step_at(producer, 4).unwrap()
      assert_eq(@pipeline.input_occurrence_count(step), 2)
      let checks = @context.stage_requirement_operations(requirements(program))
      let counts = [0, 0, 0]
      for i in 0..<@context.operation_closure_count(checks) {
        guard @context.operation_closure_at(checks, i)
          is Some(ExecutionCheck(GraphEqualityExecution(check))) else {
          continue
        }
        assert_true(physical_equal(check.site.pipeline, producer))
        assert_true(physical_equal(check.step, step))
        assert_eq(check.left, @pipeline.Step(3))
        assert_eq(
          check.right,
          @pipeline.Step(if self_comparison { 3 } else { 2 }),
        )
        assert_eq(check.site.step, 4)
        let index = match check.rule {
          AdmitOperands => 0
          CompareCanonicalGraphs => 1
          RequireComparisonResources => 2
        }
        counts[index] += 1
        assert_eq(
          @context.operation_execution_phase(GraphEqualityExecution(check)),
          if index == 1 {
            BeforeOperationOutput
          } else {
            BeforeOperationInputUse
          },
        )
        assert_eq(
          @context.operation_execution_failure(GraphEqualityExecution(check)),
          RejectOperationOutput,
        )
        assert_eq(
          @context.graph_comparison_resource_count(check),
          if index == 2 {
            3
          } else {
            0
          },
        )
        if index == 2 {
          assert_eq(
            @context.graph_comparison_resource_at(check, 0),
            Some(ComparisonWork),
          )
          assert_eq(
            @context.graph_comparison_resource_at(check, 1),
            Some(RetainedComparisonState),
          )
          assert_eq(
            @context.graph_comparison_resource_at(check, 2),
            Some(InputAndTemporaryBytes),
          )
        } else {
          assert_true(@context.graph_comparison_resource_at(check, 0) is None)
        }
        assert_true(@context.graph_comparison_resource_at(check, -1) is None)
        assert_true(@context.graph_comparison_resource_at(check, 3) is None)
      }
      for n in counts {
        assert_eq(n, 3)
      }
      assert_true(unit_publication_at(program, 1, 0) is Some(_))
    }
  }
}
