///|
test "watermark execution retains bound thresholds and exact prefix-order links" {
  for
    source in [
      "\"watermark_ms\":-0.5", "\"watermark_ms\":{\"$param\":\"n\"}", "\"max_skew\":3",
      "\"max_skew\":{\"$param\":\"n\"}", "\"max_skew\":{\"$param\":\"p\"}",
    ] {
    let profiles = resolution_profiles(
      operation_order_fixture(
        scalar_steps(
          "{\"watermark_rows\":{\"time\":\"id\",\"late_policy\":\"mark\"," +
          source +
          "}}",
        ),
        parameters="{\"p\":{\"type\":\"string\",\"format\":\"duration\",\"default\":\"01S\"},\"n\":{\"type\":\"number\",\"default\":1}}",
      ),
    )
    let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
    let requirements = operation_resolution_requirements(index)
    let mut admission = 0
    let mut thresholds = 0
    for i in 0..<operation_resolution_count(index) {
      guard operation_resolution_at(index, i)
        is Some(Execution(WatermarkExecution(check))) else {
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
      assert_eq(check.late_policy, @relation.MarkLate)
      match check.rule {
        AdmitWatermarkTime => {
          admission += 1
          assert_eq(
            operation_execution_phase(WatermarkExecution(check)),
            BeforeOperationInputUse,
          )
        }
        ApplyWatermark(threshold) => {
          thresholds += 1
          assert_eq(
            operation_execution_phase(WatermarkExecution(check)),
            BeforeOperationOutput,
          )
          let scalar = match threshold {
            FixedWatermark(n, scalar) => {
              assert_false(source.contains("max_skew"))
              assert_eq(n, if source.contains("$param") { 1.0 } else { -0.5 })
              scalar
            }
            PrefixWatermark(n, scalar, order) => {
              assert_true(source.contains("max_skew"))
              assert_eq(
                n,
                if source.contains("\"p\"") {
                  1000L
                } else if source.contains("$param") {
                  1L
                } else {
                  3L
                },
              )
              guard operation_resolution_at(index, order.requirement_index)
                is Some(Resolved(Order(original))) else {
                fail("missing prefix order")
              }
              assert_true(physical_equal(order, original))
              assert_true(
                physical_equal(order.site.pipeline, check.site.pipeline),
              )
              assert_eq(order.site.step, check.site.step)
              scalar
            }
          }
          assert_eq(scalar is Some(_), source.contains("$param"))
          if scalar is Some(scalar) {
            guard operation_resolution_at(index, scalar.requirement_index)
              is Some(Resolved(Scalar(original))) else {
              fail("missing exact scalar")
            }
            assert_true(physical_equal(scalar, original))
          }
        }
      }
      assert_eq(
        operation_execution_failure(WatermarkExecution(check)),
        RejectOperationOutput,
      )
    }
    assert_eq(admission, 3)
    assert_eq(thresholds, 3)
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
