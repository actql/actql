///|
test "SourceView watermark policy retains fixed and prefix threshold controls" {
  for prefix in [false, true] {
    for parameter in [false, true] {
      for late in ["mark", "drop"] {
        let program = checked_direct_program_fixture(
          watermark_body="{\"time\":\"id\",\"late_policy\":\"" +
            late +
            "\",\"" +
            (if prefix { "max_skew" } else { "watermark_ms" }) +
            "\":" +
            (if parameter { "{\"$param\":\"threshold\"}" } else { "1" }) +
            "}",
        )
        let policy = publication_source_policy(program.units[0].publications[0]).unwrap()
        assert_eq(publication_policy_source_count(policy), 1)
        assert_eq(publication_policy_watermark_count(policy), 1)
        assert_true(policy.unknown_provenance)
        let retained = publication_policy_watermark_at(policy, 0).unwrap()
        assert_eq(retained.step, 2)
        match retained.threshold {
          FixedThreshold(value) => {
            assert_false(prefix || parameter)
            assert_eq(value, 1.0)
          }
          ThresholdParameter(name) => {
            assert_false(prefix)
            assert_true(parameter)
            assert_eq(name, "threshold")
          }
          PrefixSkew(count, duration~) => {
            assert_true(prefix)
            assert_false(duration)
            assert_eq(
              count,
              if parameter {
                @relation.Parameter("threshold")
              } else {
                @relation.Literal(1L)
              },
            )
          }
        }
        assert_true(publication_policy_watermark_at(policy, -1) is None)
        assert_true(publication_policy_watermark_at(policy, 1) is None)
        let closure = @context.stage_requirement_operations(
          requirements(program),
        )
        let mut checks = 0
        for i in 0..<@context.operation_closure_count(closure) {
          if @context.operation_closure_at(closure, i)
            is Some(ExecutionCheck(WatermarkExecution(check))) {
            checks += 1
            assert_true(physical_equal(check.operation, retained.operation))
            assert_eq(check.site.step, retained.step)
            assert_eq(
              check.late_policy,
              if late == "mark" {
                @relation.MarkLate
              } else {
                @relation.DropLate
              },
            )
            if check.rule is ApplyWatermark(threshold) {
              assert_eq(threshold is PrefixWatermark(_, _, _), prefix)
            }
          }
        }
        assert_eq(checks, 2)
      }
    }
  }
}
