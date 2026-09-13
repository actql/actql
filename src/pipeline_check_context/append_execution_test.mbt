///|
test "append binds input admission and ordered concatenation without closing missing envelopes" {
  let requirements = operation_order_fixture(
    (
      #|[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"derive":{"x":"concat($p, to_string($n))"},"as":"ready"},{"append":{"with":"ready"}}]
    ),
  )
  let profiles = resolution_profiles(requirements)
  let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
  let mut admissions = 0
  let mut ordering = 0
  let mut envelopes = 0
  for i in 0..<operation_resolution_count(index) {
    let site = operation_requirements_at(requirements, i).unwrap()
    match operation_resolution_at(index, i).unwrap() {
      Execution(AppendRows(check)) => {
        assert_true(physical_equal(check.site, site))
        assert_eq(check.left, @pipeline.Step(1))
        assert_eq(check.right, @pipeline.Step(1))
        assert_eq(
          operation_execution_failure(AppendRows(check)),
          RejectOperationOutput,
        )
        match check.rule {
          AdmitBothInputs => {
            admissions += 1
            assert_eq(
              operation_execution_phase(AppendRows(check)),
              BeforeOperationInputUse,
            )
          }
          PreserveLeftThenRight => {
            ordering += 1
            assert_eq(
              operation_execution_phase(AppendRows(check)),
              BeforeOperationOutput,
            )
          }
        }
      }
      Unresolved =>
        if site.requirement
          is @pipeline.AppendRequirement(ResolveOutputEnvelope) {
          envelopes += 1
        }
      _ => ()
    }
  }
  assert_true(admissions > 0)
  assert_eq(admissions, ordering)
  assert_eq(envelopes, admissions)
  check_operation_closure(index)
  let work = operation_resolution_work(index)
  assert_true(
    index_program_operation_resolutions(profiles, work, 1000) is Ok(_),
  )
  assert_true(
    index_program_operation_resolutions(profiles, work - 1, 1000)
    is Err(BudgetExceeded),
  )
}
