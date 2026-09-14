///|
test "formal graph means retain all samples and obligations across Result imports" {
  for missing in ["exclude", "zero"] {
    for nulls in ["exclude", "zero", "fail"] {
      for empty in [false, true] {
        let programs : Array[CheckedProgram] = []
        let suffix = ",{\"graph\":{\"nodes\":{\"from\":\"derived\",\"id\":\"id\",\"fields\":[\"value\"]},\"edges\":{\"from\":\"seed\",\"source\":\"id\",\"target\":\"id\",\"fields\":[]}},\"as\":\"g\"},{\"mean_graphs\":{\"with\":[\"g\",\"g\",\"g\"],\"weights\":[0,1.7976931348623157e308,1.7976931348623157e308],\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{\"value\":{\"mean\":{\"missing\":\"" +
          missing +
          "\",\"nulls\":\"" +
          nulls +
          "\"}}},\"edges\":{}}},\"as\":\"mean\"},{\"node_rows\":true},{\"select\":[\"id\",\"value\"],\"as\":\"projected\"}"
        let _ = local_construction_fixture(
          { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
          through_check=true,
          checked_results=programs,
          second_stage=true,
          sga=true,
          graph_construction_limit=Some(1000),
          generated_rows=Some(
            if empty {
              "[]"
            } else {
              "[{\"id\":1},{\"id\":2}]"
            },
          ),
          producer_expression="id",
          producer_suffix=suffix,
          producer_result_from="projected",
          extra_step_budget=4,
        )
        let program = programs[0]
        assert_eq(unit_count(program), 2)
        let step = @pipeline.step_at(program.units[0].pipeline, 3).unwrap()
        assert_true(step.input is None)
        let closure = @context.stage_requirement_operations(
          program.requirements,
        )
        let counts = Array::make(10, 0)
        let mut owner_policy : @policy.Policy? = None
        for i in 0..<@context.operation_closure_count(closure) {
          if @context.operation_closure_at(closure, i)
            is Some(ExecutionCheck(GraphMeanExecution(check))) {
            assert_true(physical_equal(check.step, step))
            assert_true(
              physical_equal(check.site.pipeline, program.units[0].pipeline),
            )
            assert_eq(check.site.step, 3)
            counts[check.site.index] += 1
            if owner_policy is Some(policy) {
              assert_true(physical_equal(check.policy, policy))
            } else {
              owner_policy = Some(check.policy)
            }
            assert_eq(@context.graph_mean_sample_count(check), 3)
            for sample in 0..<3 {
              let (input, weight) = @context.graph_mean_sample_at(check, sample).unwrap()
              assert_eq(input.role, @pipeline.Sample(sample))
              assert_eq(input.target, @pipeline.Step(2))
              assert_eq(
                weight,
                if sample == 0 {
                  0.0
                } else {
                  1.7976931348623157e308
                },
              )
            }
            if check.rule == @context.RequireMeanResources {
              assert_eq(@context.graph_mean_resource_count(check), 4)
              assert_eq(
                @context.operation_execution_phase(GraphMeanExecution(check)),
                BeforeOperationInputUse,
              )
            }
            assert_eq(
              @context.operation_execution_failure(GraphMeanExecution(check)),
              RejectOperationOutput,
            )
          }
        }
        // One producer visit and its two retained import visits, never a new
        // consumer-owned mean or a proof that the graph values were evaluated.
        for count in counts {
          assert_eq(count, 3)
        }
      }
    }
  }
}
