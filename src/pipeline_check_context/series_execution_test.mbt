///|
test "series execution retains exact bound ranges and counts without generating rows" {
  let a = "2000-01-01T00:00:00.000Z"
  for empty in [false, true] {
    let z = if empty { a } else { "2000-01-01T00:00:00.010Z" }
    for mode in ["literal", "step", "endpoints", "all", "duration"] {
      let endpoints = mode == "endpoints" || mode == "all"
      let symbolic_step = mode == "step" || mode == "all" || mode == "duration"
      let steps = "[{\"time_series\":{\"start\":" +
        (if endpoints { "{\"$param\":\"a\"}" } else { "\"" + a + "\"" }) +
        ",\"end\":" +
        (if endpoints { "{\"$param\":\"z\"}" } else { "\"" + z + "\"" }) +
        ",\"step\":" +
        (if mode == "duration" {
          "{\"$param\":\"p\"}"
        } else if symbolic_step {
          "{\"$param\":\"n\"}"
        } else {
          "3"
        }) +
        "},\"as\":\"grid\"},{\"derive\":{\"x\":\"concat($p,to_string($n))\"}}]"
      let profiles = resolution_profiles(
        operation_order_fixture(
          steps,
          tea=true,
          parameters="{\"p\":{\"type\":\"string\",\"format\":\"duration\",\"default\":\"3ms\"},\"n\":{\"type\":\"number\",\"default\":3}" +
            (if endpoints {
              ",\"a\":{\"type\":\"timestamp\",\"default\":\"" +
              a +
              "\"},\"z\":{\"type\":\"timestamp\",\"default\":\"" +
              z +
              "\"}"
            } else {
              ""
            }) +
            "}",
        ),
      )
      let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
      let mut generated = 0
      let mut counted = 0
      let mut enforced = 0
      for i in 0..<operation_resolution_count(index) {
        guard operation_resolution_at(index, i)
          is Some(Execution(SeriesExecution(check))) else {
          continue
        }
        assert_true(
          physical_equal(
            check.site,
            operation_requirements_at(
              operation_resolution_requirements(index),
              i,
            ).unwrap(),
          ),
        )
        assert_true(check.step.input is None)
        assert_eq(@pipeline.input_occurrence_count(check.step), 0)
        assert_eq(check.step_ms, 3L)
        assert_eq(check.row_count, if empty { 0L } else { 4L })
        assert_eq(check.range.start, a)
        assert_eq(check.range.end, z)
        assert_eq(check.range.start_parameter is Some(_), endpoints)
        assert_eq(check.range.end_parameter is Some(_), endpoints)
        guard operation_resolution_at(index, check.range.requirement_index)
          is Some(Resolved(Range(range))) else {
          fail("range")
        }
        assert_true(physical_equal(range, check.range))
        assert_eq(check.step_resolution is Some(_), symbolic_step)
        if check.step_resolution is Some(scalar) {
          guard operation_resolution_at(index, scalar.requirement_index)
            is Some(Resolved(Scalar(original))) else {
            fail("scalar")
          }
          assert_true(physical_equal(scalar, original))
          assert_eq(scalar.site.producer_visit, check.site.producer_visit)
        }
        assert_eq(
          @policy.ceiling_field(check.ceiling),
          "max_relation_output_rows",
        )
        assert_true(
          physical_equal(@policy.ceiling_policy(check.ceiling), check.policy),
        )
        assert_eq(
          operation_execution_phase(SeriesExecution(check)),
          BeforeOperationOutput,
        )
        assert_eq(
          operation_execution_failure(SeriesExecution(check)),
          RejectOperationOutput,
        )
        match check.rule {
          GenerateTimeGrid => generated += 1
          EnforceSeriesRowCount => counted += 1
          EnforceSeriesOutputEnvelope => enforced += 1
        }
      }
      assert_eq(generated, 3)
      assert_eq(enforced, 3)
      assert_eq(
        counted,
        if endpoints || (symbolic_step && !empty) {
          3
        } else {
          0
        },
      )
      let work = operation_resolution_work(index)
      assert_true(
        index_program_operation_resolutions(profiles, work, 1000) is Ok(_),
      )
      assert_true(
        index_program_operation_resolutions(profiles, work - 1, 1000)
        is Err(BudgetExceeded),
      )
    }
  }
}
