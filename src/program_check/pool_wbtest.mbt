///|
test "formal pooling retains member and group obligations through Result imports" {
  for vectors in [false, true] {
    for reduction in ["mean", "sum", "max"] {
      for empty in [false, true] {
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
          producer_expression="1",
          producer_suffix="," +
            (if vectors {
              "{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}}"
            } else {
              "{\"assert_rows\":{\"unique_by\":[\"id\"]}}"
            }) +
            ",{\"pool_vectors\":{\"vector\":\"embedding\",\"by\":[\"value\"],\"method\":\"" +
            reduction +
            "\",\"output_id\":\"group_id\"}},{\"vectors\":true},{\"select\":[{\"id\":\"group_id\"},{\"value\":\"member_count\"}],\"as\":\"projected\"}",
          producer_result_from="projected",
          extra_step_budget=4,
        )
        let program = programs[0]
        let closure = @context.stage_requirement_operations(
          program.requirements,
        )
        let mut resources = 0
        let mut counts = 0
        let mut encoded = 0
        for i in 0..<@context.operation_closure_count(closure) {
          if @context.operation_closure_at(closure, i)
            is Some(ExecutionCheck(PoolExecution(check))) {
            assert_true(
              physical_equal(check.site.pipeline, program.units[0].pipeline),
            )
            assert_eq(check.site.step, 3)
            assert_eq(check.input, @pipeline.Step(2))
            assert_true(
              physical_equal(
                check.step,
                @pipeline.step_at(program.units[0].pipeline, 3).unwrap(),
              ),
            )
            match check.rule {
              ResolvePoolResources => {
                resources += 1
                assert_eq(@context.pool_resource_count(check), 5)
              }
              ValidatePositiveSafeMemberCounts => counts += 1
              EncodePoolMemberKeyByScalarLengths => encoded += 1
              _ => ()
            }
          }
        }
        assert_eq(resources, 3)
        assert_eq(counts, 3)
        assert_eq(encoded, if vectors { 0 } else { 3 })
      }
    }
  }
}
