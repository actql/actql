///|
test "formal vector preparation scoring and row bridge retain resource owners through imports" {
  for metric in ["cosine", "dot", "l2"] {
    for empty in [false, true] {
      let programs : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        veca=true,
        root_extra=if metric == "dot" {
          "\"params\":{\"q\":{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"default\":[1,2]}},"
        } else {
          ""
        },
        generated_schema="{\"id\":{\"type\":\"number\",\"nullable\":false},\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}}",
        generated_rows=Some(
          if empty {
            "[]"
          } else {
            "[{\"id\":1,\"embedding\":[1,2]},{\"id\":2,\"embedding\":[2,1]}]"
          },
        ),
        producer_expression="id",
        producer_suffix=",{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}},{\"normalize_vectors\":true},{\"score_vectors\":{\"query\":" +
          (if metric == "dot" { "{\"$param\":\"q\"}" } else { "[1,2]" }) +
          ",\"metric\":\"" +
          metric +
          "\"}},{\"normalize_vectors\":true},{\"vectors\":true},{\"select\":[\"id\",\"value\"],\"as\":\"projected\"}",
        producer_result_from="projected",
        extra_step_budget=6,
      )
      let program = programs[0]
      assert_eq(unit_count(program), 2)
      let closure = @context.stage_requirement_operations(program.requirements)
      let mut resources = 0
      let mut scores = 0
      let mut policy_owner : @policy.Policy? = None
      for i in 0..<@context.operation_closure_count(closure) {
        if @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(VectorExecution(check))) {
          assert_true(
            physical_equal(check.site.pipeline, program.units[0].pipeline),
          )
          assert_true(
            physical_equal(
              check.step,
              @pipeline.step_at(program.units[0].pipeline, check.site.step).unwrap(),
            ),
          )
          assert_eq(check.input, @pipeline.Step(check.site.step - 1))
          if policy_owner is Some(policy) {
            assert_true(physical_equal(policy, check.policy))
          } else {
            policy_owner = Some(check.policy)
          }
          if check.rule == @context.RequireVectorResources {
            resources += 1
            assert_eq(
              @context.vector_resource_count(check),
              if check.site.step == 4 {
                4
              } else {
                3
              },
            )
            assert_eq(
              @context.operation_execution_phase(VectorExecution(check)),
              BeforeOperationInputUse,
            )
          }
          if check.rule == @context.OrderVectorScores {
            scores += 1
          }
          assert_eq(
            @context.operation_execution_failure(VectorExecution(check)),
            RejectOperationOutput,
          )
        }
      }
      assert_eq(resources, 12)
      assert_eq(scores, 3)
    }
  }
}
