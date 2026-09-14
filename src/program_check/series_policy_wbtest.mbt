///|
fn calendar_policy_fixture(
  environment : @environment.WireEnvironment,
) -> @environment.SelectedCalendarProfile {
  @environment.admit_calendar_profile(
    @environment.read_calendar_selection(environment, 1000).unwrap(),
    @utf8.encode(
      "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"coverage_end_ms\":253402300800000,\"coverage_start_ms\":-62135596800000,\"tzdb_version\":\"test-fixture\",\"version\":\"actql-tzdb-table/0.1\",\"zones\":{\"UTC\":{\"initial_offset_seconds\":0,\"transitions\":[]}}}",
    ),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 8,
      max_zones: 1,
      max_transitions: 0,
    },
  ).unwrap()
}

///|
test "calendar series and bucket preserve SourceView policy and selected artifact ownership" {
  for end in ["2000-01-01T00:00:00.000Z", "2000-01-02T00:00:00.000Z"] {
    let steps = "{\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"" +
      end +
      "\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"grid\"},{\"calendar_bucket\":{\"time\":\"start\",\"into\":\"bucket\",\"unit\":\"month\",\"timezone\":\"UTC\"}},{\"derive\":{\"id\":\"1\"}},{\"select\":[\"id\"],\"as\":\"samples\"},{\"from\":\"remote\",\"select\":[\"id\"]},{\"append\":{\"with\":\"samples\"}}"
    let program = checked_direct_program_fixture(
      series_steps=steps,
      calendar_series=true,
    )
    let unit = program.units[0]
    let policy = publication_source_policy(unit.publications[0]).unwrap()
    assert_eq(publication_policy_source_count(policy), 1)
    assert_eq(publication_policy_generator_count(policy), 1)
    let bucket = publication_policy_carrier_step_at(policy, 0).unwrap()
    assert_eq(bucket.step, 1)
    assert_false(bucket.unknown_provenance)
    guard bucket.operation is Calendar(operation) else { fail("bucket lost") }
    guard @pipeline.step_at(unit.pipeline, 1).unwrap().operation
      is Calendar(original) else {
      fail("original bucket lost")
    }
    assert_true(physical_equal(operation, original))
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut checks = 0
    for i in 0..<@context.operation_closure_count(closure) {
      if @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(CalendarExecution(check))) {
        assert_true(physical_equal(check.operation, check.selection.operation))
        assert_true(physical_equal(check.site.pipeline, unit.pipeline))
        checks += 1
      }
    }
    assert_eq(checks, 6)
  }
}

///|
test "time series generation retains SourceView policy when appended" {
  for end in ["2000-01-01T00:00:00.000Z", "2000-01-01T00:00:00.010Z"] {
    let steps = "{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"" +
      end +
      "\",\"step\":3},\"as\":\"grid\"},{\"derive\":{\"id\":\"1\"}},{\"select\":[\"id\"],\"as\":\"samples\"},{\"from\":\"remote\",\"select\":[\"id\"]},{\"append\":{\"with\":\"samples\"}}"
    let program = checked_direct_program_fixture(series_steps=steps)
    let unit = program.units[0]
    let policy = publication_source_policy(unit.publications[0]).unwrap()
    assert_eq(publication_policy_source_count(policy), 1)
    assert_eq(publication_policy_generator_count(policy), 1)
    let generator = publication_policy_generator_at(policy, 0).unwrap()
    assert_eq(generator.step, 0)
    guard generator.operation is TimeSeries(series) else { fail("series lost") }
    guard @pipeline.step_at(unit.pipeline, 0).unwrap().operation
      is TimeSeries(original) else {
      fail("original series lost")
    }
    assert_true(physical_equal(series, original))
    assert_eq(
      @pipeline.input_occurrence_count(
        @pipeline.step_at(unit.pipeline, 0).unwrap(),
      ),
      0,
    )
    let mut inputs = 0
    for i in 0..<publication_policy_edge_count(policy) {
      if publication_policy_edge_at(policy, i).unwrap().step == 4 {
        inputs += 1
      }
    }
    assert_eq(inputs, 2)
  }
}
