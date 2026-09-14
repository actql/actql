///|
test "formal nearest retains both roles and resource requirements through Result imports" {
  for candidate_vectors in [false, true] {
    for query_vectors in [false, true] {
      for empty in 0..<4 {
        let programs : Array[CheckedProgram] = []
        let suffix = ",{\"from\":\"derived\",\"filter\":\"" +
          (if empty == 1 || empty == 3 { "FALSE" } else { "TRUE" }) +
          "\",\"as\":\"c\"},{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"},\"as\":\"cv\"},{\"from\":\"derived\",\"filter\":\"" +
          (if empty == 2 || empty == 3 { "FALSE" } else { "TRUE" }) +
          "\",\"as\":\"q\"},{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"},\"as\":\"qv\"},{\"from\":\"" +
          (if candidate_vectors { "cv" } else { "c" }) +
          "\",\"nearest\":{\"queries\":\"" +
          (if query_vectors { "qv" } else { "q" }) +
          "\",\"metric\":\"dot\",\"k\":2,\"candidate_id\":\"id\",\"query_id\":\"id\"}},{\"select\":[{\"id\":\"query_id\"},{\"value\":\"candidate_id\"}],\"as\":\"projected\"}"
        let _ = local_construction_fixture(
          { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
          through_check=true,
          checked_results=programs,
          second_stage=true,
          veca=true,
          generated_schema="{\"id\":{\"type\":\"number\",\"nullable\":false},\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}}",
          generated_rows=Some(
            "[{\"id\":1,\"embedding\":[1,2]},{\"id\":2,\"embedding\":[2,1]}]",
          ),
          producer_expression="id",
          producer_suffix=suffix,
          producer_result_from="projected",
          extra_step_budget=6,
        )
        let program = programs[0]
        assert_eq(unit_count(program), 2)
        let closure = @context.stage_requirement_operations(
          program.requirements,
        )
        let mut resources = 0
        let mut ranks = 0
        let mut completions = 0
        let mut resource_policy : @policy.Policy? = None
        for i in 0..<@context.operation_closure_count(closure) {
          if @context.operation_closure_at(closure, i)
            is Some(ExecutionCheck(NearestExecution(check))) {
            assert_true(
              physical_equal(check.site.pipeline, program.units[0].pipeline),
            )
            assert_eq(check.site.step, 6)
            assert_true(
              physical_equal(
                check.step,
                @pipeline.step_at(program.units[0].pipeline, 6).unwrap(),
              ),
            )
            assert_eq(
              check.candidates,
              @pipeline.Step(if candidate_vectors { 3 } else { 2 }),
            )
            assert_eq(
              check.queries,
              @pipeline.Step(if query_vectors { 5 } else { 4 }),
            )
            if resource_policy is Some(policy) {
              assert_true(physical_equal(policy, check.policy))
            } else {
              resource_policy = Some(check.policy)
            }
            match check.rule {
              ResolveNearestResources => {
                resources += 1
                assert_eq(@context.nearest_resource_count(check), 5)
                assert_eq(
                  @policy.ceiling_value(check.host_output_rows.unwrap()),
                  1000L,
                )
                assert_true(
                  physical_equal(
                    @policy.ceiling_policy(check.host_output_rows.unwrap()),
                    check.policy,
                  ),
                )
              }
              AssignContiguousOneBasedRanks => ranks += 1
              JournalVectorFieldCompletion(_, _) => completions += 1
              _ => ()
            }
            assert_eq(
              @context.operation_execution_failure(NearestExecution(check)),
              RejectOperationOutput,
            )
          }
        }
        assert_eq(resources, 3)
        assert_eq(ranks, 3)
        assert_eq(
          completions,
          3 *
          (
            (if candidate_vectors { 0 } else { 1 }) +
            (if query_vectors { 0 } else { 1 })
          ),
        )
      }
    }
  }
}
