///|
test "formal groups retain deterministic statistical laws separately from numeric observations" {
  for
    name in [
      "percentile_cont", "var_pop", "var_samp", "stddev_pop", "stddev_samp",
    ] {
    let programs : Array[CheckedProgram] = []
    let fraction = if name == "percentile_cont" {
      ",\"fraction\":0.5"
    } else {
      ""
    }
    let _ = local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      second_stage=true,
      through_check=true,
      checked_results=programs,
      second_steps="[{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"" +
        name +
        "\",\"field\":\"value\",\"filter\":\"FALSE\"" +
        fraction +
        "}}},\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=2,
    )
    let program = programs[0]
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut count = 0
    for index in 0..<@context.operation_closure_count(closure) {
      guard @context.operation_closure_at(closure, index)
        is Some(ExecutionCheck(GroupExecution(check))) &&
        check.rule is EnforceStatisticalLaw(call, law) else {
        continue
      }
      assert_eq(check.site.stage, 1)
      assert_true(
        physical_equal(check.site.pipeline, program.units[1].pipeline),
      )
      assert_true(
        physical_equal(
          call,
          @relation.aggregate_for_validation(check.group, check.site.index).unwrap(),
        ),
      )
      assert_true(@relation.aggregate_filter(call) is Some(_))
      assert_eq(
        @context.operation_execution_phase(GroupExecution(check)),
        @context.BeforeOperationOutput,
      )
      assert_eq(
        @context.operation_execution_failure(GroupExecution(check)),
        @context.RejectOperationOutput,
      )
      let actual = match law {
        PercentileInterpolation => "percentile_cont"
        PopulationVariance => "var_pop"
        SampleVariance => "var_samp"
        PopulationStandardDeviation => "stddev_pop"
        SampleStandardDeviation => "stddev_samp"
      }
      assert_eq(actual, name)
      count += 1
    }
    // A false filter does not erase the execution contract or its empty-domain law.
    assert_eq(count, 1)
  }
}
