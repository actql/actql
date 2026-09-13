///|
test "session checks retain the selected gap and its exact bound occurrence" {
  for gap in ["1000", "\"01S\"", "{\"$param\":\"n\"}", "{\"$param\":\"p\"}"] {
    let profiles = resolution_profiles(
      operation_order_fixture(
        scalar_steps(
          "{\"session\":{\"id\":\"id\",\"time\":\"id\",\"by\":[\"id\",\"id\"],\"gap\":" +
          gap +
          "}}",
        ),
        tea=true,
        parameters="{\"p\":{\"type\":\"string\",\"format\":\"duration\",\"default\":\"01S\"},\"n\":{\"type\":\"number\",\"default\":1000}}",
      ),
    )
    let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
    let requirements = operation_resolution_requirements(index)
    let mut arithmetic = 0
    let mut identities = 0
    let mut resources = 0
    for i in 0..<operation_resolution_count(index) {
      if operation_resolution_at(index, i) is Some(Unresolved) &&
        operation_requirements_at(requirements, i).unwrap().requirement
        is @pipeline.EventRequirement(ResolveEventResources) {
        resources += 1
      }
      guard operation_resolution_at(index, i)
        is Some(Execution(SessionExecution(check))) else {
        continue
      }
      assert_true(
        physical_equal(
          check.site,
          operation_requirements_at(requirements, i).unwrap(),
        ),
      )
      assert_true(
        physical_equal(
          check.step,
          @pipeline.step_at(check.site.pipeline, check.site.step).unwrap(),
        ),
      )
      assert_eq(check.input, @pipeline.Step(1))
      assert_eq(check.gap_ms, 1000L)
      assert_eq(check.gap_resolution is Some(_), gap.contains("$param"))
      guard @event.options(check.operation) is Session(spec) else {
        fail("session")
      }
      assert_eq(@event.session_keys(spec).length(), 2)
      if check.gap_resolution is Some(scalar) {
        guard operation_resolution_at(index, scalar.requirement_index)
          is Some(Resolved(Scalar(original))) else {
          fail("gap resolution")
        }
        assert_true(physical_equal(scalar, original))
        assert_true(physical_equal(scalar.site.pipeline, check.site.pipeline))
        assert_eq(scalar.site.producer_visit, check.site.producer_visit)
        assert_eq(scalar.site.step, check.site.step)
      }
      match check.rule {
        AssignSessionBoundaries => arithmetic += 1
        DeriveSessionIdentity => identities += 1
      }
      assert_eq(
        operation_execution_phase(SessionExecution(check)),
        BeforeOperationOutput,
      )
      assert_eq(
        operation_execution_failure(SessionExecution(check)),
        RejectOperationOutput,
      )
    }
    assert_eq(arithmetic, 3)
    assert_eq(identities, 3)
    assert_eq(resources, 3)
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
