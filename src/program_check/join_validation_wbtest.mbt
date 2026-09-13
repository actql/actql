///|
test "formal join retains authored tuple checks even with static key evidence" {
  for cardinality in ["one_to_one", "many_to_one", "one_to_many"] {
    for reject_null in [false, true] {
      for right in ["again", "rows"] {
        let checked : Array[CheckedProgram] = []
        let _ = local_construction_fixture(
          { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
          second_stage=true,
          through_check=true,
          checked_results=checked,
          second_steps="[{\"join\":{\"with\":\"" +
            right +
            "\",\"kind\":\"inner\",\"on\":[\"id\",\"id\"],\"cardinality\":\"" +
            cardinality +
            "\",\"null_key\":\"" +
            (if reject_null { "fail" } else { "no_match" }) +
            "\",\"select\":{\"id\":\"left.id\",\"value\":\"left.value\"}},\"as\":\"selected\"}]",
          second_result_from="selected",
          extra_step_budget=2,
          second_join_capacity=true,
        )
        let program = checked[0]
        let pipeline = unit_pipeline(program, 1).unwrap()
        let closure = @context.stage_requirement_operations(
          requirements(program),
        )
        let mut assertions = 0
        let mut nulls = 0
        for i in 0..<@context.operation_closure_count(closure) {
          if @context.operation_closure_at(closure, i)
            is Some(ExecutionCheck(JoinInputValidation(check))) {
            assert_eq(check.site.stage, 1)
            assert_true(physical_equal(check.site.pipeline, pipeline))
            assert_true(
              physical_equal(
                check.step,
                @pipeline.step_at(pipeline, 0).unwrap(),
              ),
            )
            assert_eq(check.left, @pipeline.Input(0))
            assert_eq(
              check.right,
              @pipeline.Input(if right == "rows" { 0 } else { 1 }),
            )
            assert_eq(@join.key_count(check.operation), 2)
            assert_eq(
              @context.operation_execution_phase(JoinInputValidation(check)),
              BeforeOperationInputUse,
            )
            assert_eq(
              @context.operation_execution_failure(JoinInputValidation(check)),
              RejectOperationOutput,
            )
            match check.rule {
              AssertCardinality(c) => {
                assertions += 1
                assert_eq(@join.assertion(check.operation), Some(c))
                assert_eq(
                  match c {
                    OneToOne => "one_to_one"
                    ManyToOne => "many_to_one"
                    OneToMany => "one_to_many"
                  },
                  cardinality,
                )
              }
              RejectNullKeyComponents => {
                nulls += 1
                assert_true(reject_null)
              }
            }
          }
        }
        assert_eq(assertions, 1)
        assert_eq(nulls, if reject_null { 1 } else { 0 })
      }
    }
  }
}
