///|
test "atomic assertions retain owned execution checks without deferring static consumption" {
  for body in ["{\"where\":\"id = id\"}", "{\"unique_by\":[\"id\"]}"] {
    let profiles = resolution_profiles(
      operation_order_fixture(
        "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}},{\"assert_rows\":" +
        body +
        "}]",
      ),
    )
    let index = index_program_operation_resolutions(profiles, 10000000, 100).unwrap()
    let mut atomic_checks = 0
    let mut consumption = 0
    for i in 0..<operation_resolution_count(index) {
      let site = operation_requirements_at(
        operation_resolution_requirements(index),
        i,
      ).unwrap()
      guard site.requirement is @pipeline.RelationRequirement(pending) else {
        continue
      }
      match pending.kind {
        @relation.AtomicRowAssertion => {
          guard operation_resolution_at(index, i)
            is Some(Execution(RowAssertion(check))) else {
            fail("missing atomic check")
          }
          assert_true(physical_equal(check.site, site))
          assert_true(
            physical_equal(
              check.step,
              @pipeline.step_at(site.pipeline, site.step).unwrap(),
            ),
          )
          assert_eq(check.step.input, Some(check.input))
          assert_eq(@relation.operation(check.operation), @relation.AssertRows)
          assert_eq(
            operation_execution_phase(RowAssertion(check)),
            BeforeOperationOutput,
          )
          assert_eq(
            operation_execution_failure(RowAssertion(check)),
            RejectOperationOutput,
          )
          atomic_checks += 1
        }
        @relation.AssertionConsumption => {
          assert_true(operation_resolution_at(index, i) is Some(Unresolved))
          consumption += 1
        }
        _ => ()
      }
    }
    assert_true(atomic_checks > 0)
    assert_eq(atomic_checks, consumption)
    assert_true(
      close_program_operations(index, 10000000, 100)
      is Err(IncompleteResolution(_)),
    )
  }
}
