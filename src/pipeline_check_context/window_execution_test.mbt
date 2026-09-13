///|
test "window time and membership checks preserve exact owners without closing resource bounds" {
  for kind in ["fixed", "sliding"] {
    let profiles = resolution_profiles(
      operation_order_fixture(
        scalar_steps(
          "{\"row_window\":{\"time\":\"id\",\"kind\":\"" +
          kind +
          "\",\"size\":1000,\"step\":{\"$param\":\"n\"},\"offset\":-1}}",
        ),
        tea=true,
      ),
    )
    let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
    let requirements = operation_resolution_requirements(index)
    let mut times = 0
    let mut memberships = 0
    let mut resources = 0
    let mut bindings = 0
    for i in 0..<operation_resolution_count(index) {
      let site = operation_requirements_at(requirements, i).unwrap()
      guard site.requirement is @pipeline.WindowRequirement(pending) else {
        continue
      }
      match pending {
        BindMilliseconds(_, _) => {
          bindings += 1
          assert_true(operation_resolution_at(index, i) is Some(Resolved(_)))
        }
        ResolveMembershipBound | ResolvePublicationResources => {
          resources += 1
          assert_true(operation_resolution_at(index, i) is Some(Unresolved))
        }
        ValidateTimeValues | CheckedWindowArithmetic => {
          guard operation_resolution_at(index, i)
            is Some(Execution(WindowExecution(check))) else {
            fail("missing window check")
          }
          assert_true(physical_equal(check.site, site))
          assert_eq(check.step.input, Some(check.input))
          guard check.step.operation is @pipeline.Window(window) else {
            fail("not window")
          }
          assert_true(physical_equal(window, check.window))
          assert_eq(
            operation_execution_failure(WindowExecution(check)),
            RejectOperationOutput,
          )
          match check.rule {
            AdmitTimeValues => {
              times += 1
              assert_eq(
                operation_execution_phase(WindowExecution(check)),
                BeforeOperationInputUse,
              )
            }
            AssignMemberships => {
              memberships += 1
              assert_eq(
                operation_execution_phase(WindowExecution(check)),
                BeforeOperationOutput,
              )
            }
          }
        }
      }
    }
    assert_eq((times, memberships, resources, bindings), (3, 3, 6, 3))
    let work = operation_resolution_work(index)
    let count = operation_resolution_count(index)
    assert_true(
      index_program_operation_resolutions(profiles, work, count) is Ok(_),
    )
    assert_true(
      index_program_operation_resolutions(profiles, work - 1, count)
      is Err(BudgetExceeded),
    )
    assert_true(
      close_program_operations(index, 10000000, 1000)
      is Err(IncompleteResolution(_)),
    )
  }
}
