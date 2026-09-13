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
            AssignMemberships(options) => {
              memberships += 1
              assert_eq(options.size, 1000L)
              assert_eq(options.offset, -1L)
              assert_true(options.size_resolution is None)
              assert_true(options.offset_resolution is None)
              let resolution = options.step_resolution.unwrap()
              guard resolution.value is Milliseconds(n) else {
                fail("not milliseconds")
              }
              assert_eq(options.step, Some(n))
              assert_eq(
                options.maximum_per_input,
                if kind == "fixed" {
                  1L
                } else {
                  1000L / n + (if 1000L % n == 0L { 0L } else { 1L })
                },
              )
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

///|
test "window execution uses exact integer factors and retains absent and unused options" {
  for
    (body, size, step, offset, factor) in [
      ("\"kind\":\"fixed\",\"size\":10", 10L, None, 0L, 1L),
      (
        "\"kind\":\"fixed\",\"size\":10,\"step\":3,\"offset\":-7",
        10L,
        Some(3L),
        -7L,
        1L,
      ),
      ("\"kind\":\"sliding\",\"size\":10,\"step\":3", 10L, Some(3L), 0L, 4L),
      ("\"kind\":\"sliding\",\"size\":10,\"step\":20", 10L, Some(20L), 0L, 1L),
      (
        "\"kind\":\"sliding\",\"size\":9007199254740991,\"step\":2",
        9007199254740991L,
        Some(2L),
        0L,
        4503599627370496L,
      ),
      (
        "\"kind\":\"sliding\",\"size\":9007199254740991,\"step\":1,\"offset\":-9007199254740991",
        9007199254740991L,
        Some(1L),
        -9007199254740991L,
        9007199254740991L,
      ),
    ] {
    let profiles = resolution_profiles(
      operation_order_fixture(
        scalar_steps("{\"row_window\":{\"time\":\"id\"," + body + "}}").replace(
          old="\"rows\":[{\"id\":2},{\"id\":1}]",
          new="\"rows\":[{\"id\":1}]",
        ),
        tea=true,
      ),
    )
    let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
    let mut found = 0
    for i in 0..<operation_resolution_count(index) {
      guard operation_resolution_at(index, i)
        is Some(Execution(WindowExecution(check))) &&
        check.rule is AssignMemberships(options) else {
        continue
      }
      found += 1
      assert_eq(
        (options.size, options.step, options.offset, options.maximum_per_input),
        (size, step, offset, factor),
      )
      assert_true(options.size_resolution is None)
      assert_true(options.step_resolution is None)
      assert_true(options.offset_resolution is None)
    }
    assert_eq(found, 3)
  }
}

///|
test "window execution retains owned repeated duration and numeric bindings" {
  for (name, n) in [("p", 1000L), ("n", 3L)] {
    let reference = "{\"$param\":\"" + name + "\"}"
    let profiles = resolution_profiles(
      operation_order_fixture(
        scalar_steps(
          "{\"row_window\":{\"time\":\"id\",\"kind\":\"sliding\",\"size\":" +
          reference +
          ",\"step\":" +
          reference +
          ",\"offset\":" +
          reference +
          "}}",
        ),
        parameters="{\"p\":{\"type\":\"string\",\"format\":\"duration\",\"default\":\"01S\"},\"n\":{\"type\":\"number\",\"default\":3}}",
        tea=true,
      ),
    )
    let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
    let mut found = 0
    for i in 0..<operation_resolution_count(index) {
      guard operation_resolution_at(index, i)
        is Some(Execution(WindowExecution(check))) &&
        check.rule is AssignMemberships(options) else {
        continue
      }
      found += 1
      assert_eq(
        (options.size, options.step, options.offset, options.maximum_per_input),
        (n, Some(n), n, 1L),
      )
      for
        resolution in [
          options.size_resolution,
          options.step_resolution,
          options.offset_resolution,
        ] {
        let resolution = resolution.unwrap()
        assert_eq(resolution.site.stage, check.site.stage)
        assert_eq(resolution.site.producer_visit, check.site.producer_visit)
        assert_eq(resolution.site.step, check.site.step)
        assert_true(
          physical_equal(resolution.site.pipeline, check.site.pipeline),
        )
        guard operation_resolution_at(index, resolution.requirement_index)
          is Some(Resolved(Scalar(original))) else {
          fail("missing scalar")
        }
        assert_true(physical_equal(original, resolution))
        assert_eq(resolution.parameter.name, name)
        if name == "p" {
          assert_true(resolution.parameter.value.value is @value.Text("01S"))
        }
      }
      assert_true(
        options.size_resolution.unwrap().requirement_index !=
        options.offset_resolution.unwrap().requirement_index,
      )
    }
    assert_eq(found, 3)
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
