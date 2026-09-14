///|
test "formal RRF retains producer checks repeated inputs and static score envelopes across imports" {
  for empty in [false, true] {
    for
      weights in [
        "[1,0,2]", "[1.7976931348623157e308,1.7976931348623157e308,1.7976931348623157e308]",
      ] {
      let programs : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        veca=true,
        generated_schema="{\"id\":{\"type\":\"number\",\"nullable\":false},\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}}",
        generated_rows=Some(
          if empty {
            "[]"
          } else {
            "[{\"id\":1,\"embedding\":[1,2]},{\"id\":2,\"embedding\":[2,1]}]"
          },
        ),
        producer_expression="id",
        producer_suffix=",{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"},\"as\":\"v\"},{\"nearest\":{\"queries\":\"v\",\"metric\":\"dot\",\"k\":2},\"as\":\"n\"},{\"merge_rankings\":{\"with\":[\"n\",\"n\"],\"by\":[\"query_id\"],\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":2,\"score_policy\":{\"rrf\":{\"rank_constant\":1,\"rank_window\":1,\"weights\":" +
          weights +
          "}}}},{\"select\":[{\"id\":\"query_id\"},{\"value\":\"candidate_id\"}],\"as\":\"projected\"}",
        producer_result_from="projected",
        extra_step_budget=4,
      )
      let program = programs[0]
      assert_eq(unit_count(program), 2)
      let closure = @context.stage_requirement_operations(program.requirements)
      let mut resources = 0
      let mut envelopes = 0
      let mut nearest = 0
      let mut complete = 0
      for i in 0..<@context.operation_closure_count(closure) {
        match @context.operation_closure_at(closure, i) {
          Some(ExecutionCheck(RankingExecution(check))) => {
            assert_true(
              physical_equal(check.site.pipeline, program.units[0].pipeline),
            )
            assert_eq(check.site.step, 4)
            assert_eq(@context.ranking_execution_input_count(check), 3)
            for j in 0..<3 {
              let (edge, shape) = @context.ranking_execution_input_at(check, j).unwrap()
              assert_eq(edge.role, @pipeline.Sample(j))
              assert_eq(edge.target, @pipeline.Step(3))
              assert_true(
                @evidence.ranking_input_nearest(
                  @evidence.ranking_shape_input(shape),
                )
                is Some(_),
              )
            }
            if check.rule == RequireRankingResources {
              resources += 1
              assert_eq(@context.ranking_resource_count(check), 5)
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
            if check.rule == AdmitCompleteRankings {
              complete += 1
            }
          }
          Some(StaticResolution(RankingEnvelope(envelope))) => {
            envelopes += 1
            assert_eq(envelope.site.step, 4)
            assert_true(
              physical_equal(envelope.site.pipeline, program.units[0].pipeline),
            )
            assert_eq(envelope.minimum, 0.0)
            assert_eq(
              envelope.maximum,
              if weights == "[1,0,2]" {
                1.5
              } else {
                1.7976931348623157e308
              },
            )
          }
          Some(ExecutionCheck(NearestExecution(check))) =>
            if check.rule is ResolveNearestResources {
              nearest += 1
            }
          _ => ()
        }
      }
      assert_eq(resources, 3)
      assert_eq(envelopes, 3)
      assert_eq(complete, 3)
      assert_eq(nearest, 3)
    }
  }
}
