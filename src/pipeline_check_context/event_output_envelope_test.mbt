///|
test "event output envelopes follow the Carrier and retain the selected policy" {
  for
    tail in [
      "{\"session\":{\"id\":\"id\",\"time\":\"id\",\"by\":[],\"gap\":1}}", "{\"to_events\":{\"id\":\"id\",\"time\":\"id\"}},{\"events\":true}",
      "{\"to_events\":{\"id\":\"id\",\"time\":\"id\"}},{\"watermark_events\":{\"watermark_ms\":100,\"policy\":\"drop\"}},{\"events\":true}",
      "{\"to_events\":{\"id\":\"id\",\"time\":\"id\"}},{\"session\":{\"by\":[],\"gap\":1}},{\"events\":true}",
      "{\"to_events\":{\"id\":\"id\",\"time\":\"id\"}},{\"dedupe_events\":{\"by\":[],\"order_by\":[{\"id\":\"asc\"}]}},{\"events\":true}",
    ] {
    let selected = policy()
    let profiles = resolution_profiles(
      operation_order_fixture(
        scalar_steps(tail),
        tea=true,
        capacity_policy=selected,
      ),
    )
    let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
    let mut found = 0
    for i in 0..<operation_resolution_count(index) {
      guard operation_resolution_at(index, i)
        is Some(Execution(EventEnvelope(check))) else {
        continue
      }
      found += 1
      assert_true(physical_equal(check.policy, selected))
      assert_true(
        physical_equal(@policy.ceiling_policy(check.ceiling), selected),
      )
      let field = if tail.contains("to_events") {
        "max_temporal_output_rows"
      } else {
        "max_relation_output_rows"
      }
      assert_eq(@policy.ceiling_field(check.ceiling), field)
      assert_eq(@policy.ceiling_value(check.ceiling), 1L)
      assert_true(
        physical_equal(
          check.site,
          operation_requirements_at(operation_resolution_requirements(index), i).unwrap(),
        ),
      )
      assert_true(
        physical_equal(
          check.step,
          @pipeline.step_at(check.site.pipeline, check.site.step).unwrap(),
        ),
      )
      assert_eq(check.input, @pipeline.Step(check.site.step - 1))
      assert_eq(
        operation_execution_phase(EventEnvelope(check)),
        BeforeOperationOutput,
      )
      assert_eq(
        operation_execution_failure(EventEnvelope(check)),
        RejectOperationOutput,
      )
    }
    assert_eq(
      found,
      if tail.contains("watermark_events") ||
        tail.contains("dedupe_events") ||
        (tail.contains("to_events") && tail.contains("session")) {
        6
      } else {
        3
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
