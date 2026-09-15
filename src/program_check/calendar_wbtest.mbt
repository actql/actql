///|
test "formal Calendar Program retains artifact ownership through series and bucket" {
  for end in ["2000-01-01T00:00:00.000Z", "2000-01-02T00:00:00.000Z"] {
    let programs : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=programs,
      second_stage=true,
      calendar=true,
      tea=true,
      second_steps="[{\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"" +
        end +
        "\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"grid\"},{\"calendar_bucket\":{\"time\":\"start\",\"into\":\"bucket\",\"unit\":\"month\",\"timezone\":\"UTC\"}},{\"select\":[{\"id\":\"start\"},{\"value\":\"end\"}],\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=3,
    )
    let p = programs[0]
    let closure = @context.stage_requirement_operations(requirements(p))
    let selected = @context.operation_calendar_profile(
      @context.operation_profile_links_calendar(
        @context.operation_resolution_profiles(
          @context.operation_closure_index(closure),
        ),
      ),
    ).unwrap()
    let mut checks = 0
    for i in 0..<@context.operation_closure_count(closure) {
      guard @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(CalendarExecution(check))) else {
        continue
      }
      checks += 1
      assert_true(
        physical_equal(check.site.pipeline, unit_pipeline(p, 1).unwrap()),
      )
      assert_eq(check.selection.stage, 1)
      assert_eq(check.selection.step, check.site.step)
      assert_true(physical_equal(check.operation, check.selection.operation))
      assert_true(physical_equal(check.selection.selected, selected))
      assert_eq(
        @policy.ceiling_field(check.ceiling),
        "max_relation_output_rows",
      )
    }
    assert_eq(checks, 6)
    assert_true(unit_publication_at(p, 1, 0) is Some(_))
    assert_true(unit_definition_cid(p, 0) != unit_definition_cid(p, 1))
  }
}

///|
test "formal Calendar refuses missing artifact before returning a Program" {
  let programs : Array[CheckedProgram] = []
  try
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=programs,
      second_stage=true,
      calendar=true,
      calendar_material=false,
      tea=true,
      second_steps="[{\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.000Z\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=1,
    )
  catch {
    Source(SourceView(Program(MissingCalendarArtifact(selection)))) =>
      assert_eq(
        @environment.calendar_selection_release(selection),
        "test-fixture",
      )
    error => raise error
  } noraise {
    _ => fail("missing Calendar artifact accepted")
  }
  assert_true(programs.is_empty())
}
