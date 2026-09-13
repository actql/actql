///|
test "Calendar execution retains selected artifacts and exact producer occurrences" {
  for bound in [false, true] {
    let lexical = calendar_program(program_calendar_host(), bound~)
    let selected = program_calendar_artifact(lexical)
    let calendar = check_program_operation_calendar(
      lexical,
      Some(selected),
      10000000,
      6,
    ).unwrap()
    let profiles = link_program_operation_profiles(calendar, 10000000, 100).unwrap()
    let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
    let requirements = operation_resolution_requirements(index)
    let mut executions = 0
    for i in 0..<operation_resolution_count(index) {
      guard operation_resolution_at(index, i)
        is Some(Execution(CalendarExecution(check))) else {
        continue
      }
      executions += 1
      let site = operation_requirements_at(requirements, i).unwrap()
      assert_true(physical_equal(check.site, site))
      assert_true(physical_equal(check.selection.selected, selected))
      assert_true(physical_equal(check.operation, check.selection.operation))
      assert_true(
        physical_equal(
          check.step,
          @pipeline.step_at(site.pipeline, site.step).unwrap(),
        ),
      )
      assert_eq(check.selection.stage, site.stage)
      assert_eq(check.selection.producer_visit, site.producer_visit)
      assert_eq(check.selection.step, site.step)
      assert_eq(
        @policy.ceiling_field(check.ceiling),
        "max_relation_output_rows",
      )
      assert_true(
        physical_equal(@policy.ceiling_policy(check.ceiling), check.policy),
      )
      if bound && site.step == 0 {
        let range = check.range.unwrap()
        assert_eq(range.end, "2000-01-02T00:00:00.000Z")
        assert_true(range.end_parameter is Some(_))
        assert_true(physical_equal(range.site.pipeline, site.pipeline))
        assert_eq(range.site.producer_visit, site.producer_visit)
        guard operation_resolution_at(index, range.requirement_index)
          is Some(Resolved(Range(original))) else {
          fail("missing original range")
        }
        assert_true(physical_equal(range, original))
      } else {
        assert_true(check.range is None)
      }
      let phase = operation_execution_phase(CalendarExecution(check))
      assert_eq(
        phase,
        if check.rule == AdmitCalendarValues && site.step == 1 {
          BeforeOperationInputUse
        } else {
          BeforeOperationOutput
        },
      )
      assert_eq(
        operation_execution_failure(CalendarExecution(check)),
        RejectOperationOutput,
      )
    }
    assert_eq(executions, 18)
    check_operation_closure(index)
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
      index_program_operation_resolutions(profiles, work, count - 1)
      is Err(BudgetExceeded),
    )
  }
}
