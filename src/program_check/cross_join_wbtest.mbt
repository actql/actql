///|
test "formal cross join binds product order singleton and conditional identities" {
  for lose_key in [false, true] {
    for singleton in [false, true] {
      let checked : Array[CheckedProgram] = []
      let join_step = if lose_key { 2 } else { 0 }
      let prefix = if lose_key {
        "{\"drop\":[\"id\"]},{\"derive\":{\"id\":\"value + 1\"}},"
      } else {
        ""
      }
      let _ = local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        second_stage=true,
        through_check=true,
        checked_results=checked,
        second_steps="[" +
          prefix +
          "{\"cross_join\":{\"with\":\"again\"," +
          (if singleton { "\"right_rows\":\"one\"," } else { "" }) +
          "\"select\":{\"id\":\"left.id\",\"value\":\"left.value\"}},\"as\":\"selected\"}]",
        second_result_from=if lose_key { "rows" } else { "selected" },
        second_join_capacity=true,
        second_join_step=join_step,
        extra_step_budget=2,
      )
      let program = checked[0]
      let pipeline = unit_pipeline(program, 1).unwrap()
      let closure = @context.stage_requirement_operations(requirements(program))
      let counts = Array::make(3, 0)
      let mut identities = 0
      for i in 0..<@context.operation_closure_count(closure) {
        match @context.operation_closure_at(closure, i) {
          Some(ExecutionCheck(CrossJoinRows(check))) => {
            assert_eq(check.site.stage, 1)
            assert_true(physical_equal(check.site.pipeline, pipeline))
            assert_eq(check.site.step, join_step)
            assert_eq(
              check.left,
              if lose_key {
                @pipeline.Step(1)
              } else {
                @pipeline.Input(0)
              },
            )
            assert_eq(check.right, @pipeline.Input(1))
            assert_true(
              physical_equal(
                @step_bounds.join_limit_pipeline(check.output_limit),
                pipeline,
              ),
            )
            assert_eq(
              @step_bounds.join_limit_step(check.output_limit),
              join_step,
            )
            // Neither the Host ceiling nor right_rows:one is input count evidence.
            assert_true(check.left_count is None)
            assert_true(check.right_count is None)
            assert_true(check.output_count is None)
            let n = match check.rule {
              CheckProductArithmetic => 0
              PreserveLeftMajorOrder => 1
              RequireExactlyOneRightRow => 2
            }
            counts[n] += 1
            assert_eq(
              @context.operation_execution_phase(CrossJoinRows(check)),
              if n == 1 {
                BeforeOperationOutput
              } else {
                BeforeOperationInputUse
              },
            )
            assert_eq(
              @context.operation_execution_failure(CrossJoinRows(check)),
              RejectOperationOutput,
            )
          }
          Some(ExecutionCheck(CrossJoinIdentity(check))) => {
            identities += 1
            assert_eq(check.key is None, lose_key && check.side is Left)
            assert_true(physical_equal(check.site.pipeline, pipeline))
          }
          _ => ()
        }
      }
      assert_eq(counts[0], 1)
      assert_eq(counts[1], 1)
      assert_eq(counts[2], if singleton { 1 } else { 0 })
      assert_eq(identities, 2)
    }
  }
}
