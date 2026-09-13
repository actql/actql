///|
test "formal watermark closes fixed and ordered-prefix paths without claiming observations" {
  for sequence in ["fixed", "sort", "import"] {
    let prefix = sequence != "fixed"
    let sorted = sequence == "sort"
    for parameter in [false, true] {
      for late_policy in ["mark", "drop"] {
        let checked : Array[CheckedProgram] = []
        let value = if parameter { "{\"$param\":\"n\"}" } else { "1" }
        let _ = local_construction_fixture(
          { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
          through_check=true,
          checked_results=checked,
          second_stage=true,
          parameters=parameter,
          second_steps="[" +
            (if sorted { "{\"sort\":[{\"id\":\"desc\"}]}," } else { "" }) +
            "{\"watermark_rows\":{\"time\":\"id\",\"late_policy\":\"" +
            late_policy +
            "\",\"" +
            (if prefix { "max_skew" } else { "watermark_ms" }) +
            "\":" +
            value +
            "}},{\"take\":1},{\"select\":[\"id\",\"value\"],\"as\":\"selected\"}]",
          second_result_from="selected",
          extra_step_budget=4,
        )
        let p = checked[0]
        let closure = @context.stage_requirement_operations(requirements(p))
        let mut rules = 0
        for i in 0..<@context.operation_closure_count(closure) {
          guard @context.operation_closure_at(closure, i)
            is Some(ExecutionCheck(WatermarkExecution(check))) else {
            continue
          }
          rules += 1
          assert_eq(check.site.stage, 1)
          assert_eq(check.site.step, if sorted { 1 } else { 0 })
          assert_true(
            physical_equal(check.site.pipeline, unit_pipeline(p, 1).unwrap()),
          )
          assert_eq(
            check.input,
            if sorted {
              @pipeline.Step(0)
            } else {
              @pipeline.Input(0)
            },
          )
          assert_eq(check.time.field, @schema.Unqualified("id"))
          assert_false(check.timestamp)
          assert_eq(
            check.late_policy,
            if late_policy == "mark" {
              @relation.MarkLate
            } else {
              @relation.DropLate
            },
          )
          if check.rule is ApplyWatermark(threshold) {
            assert_eq(threshold is PrefixWatermark(_, _, _), prefix)
          }
        }
        assert_eq(rules, 2)
        let owner = @context.stage_requirement_owner(requirements(p))
        let (work, count) = @context.stage_requirement_usage(requirements(p))
        let limits : @context.StageRequirementLimits = {
          max_work: work,
          max_requirements: count,
          max_local_inputs: 10,
        }
        assert_true(@context.close_stage_requirements(owner, limits) is Ok(_))
        assert_true(
          @context.close_stage_requirements(owner, {
            ..limits,
            max_work: work - 1,
          })
          is Err(_),
        )
      }
    }
  }
}

///|
test "prefix watermark cannot substitute a candidate key for an existing sequence" {
  for prefix in [false, true] {
    let checked : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        checked_results=checked,
        producer_suffix=",{\"watermark_rows\":{\"time\":\"id\",\"" +
          (if prefix { "max_skew" } else { "watermark_ms" }) +
          "\":1,\"late_policy\":\"mark\"},\"as\":\"selected\"}",
        producer_result_from="selected",
        extra_step_budget=2,
      )
    catch {
      Source(_) if prefix => ()
      error => raise error
    } noraise {
      _ => assert_false(prefix)
    }
    assert_eq(checked.length(), if prefix { 0 } else { 1 })
  }
}
