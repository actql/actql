///|
test "Calendar requests retain selection ownership through public supplementation" {
  let (text, _, absent, _, limits) = public_input_fixture(calendar_profile=true)
  let text = text
    .replace(
      old="\"params\":{\"n\":{\"type\":\"number\",\"default\":1}},",
      new="",
    )
    .replace(
      old="{\"derive\":{\"value\":\"id + $n\"},\"as\":\"derived\"}",
      new="{\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-02T00:00:00.000Z\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"grid\"},{\"select\":[{\"id\":\"start\"},{\"value\":\"end\"}],\"as\":\"derived\"}",
    )
  let program = @syntax.parse(
    text,
    limits.input,
    format=Json,
    source_path="calendar.actql",
  ).unwrap()
  guard @program_check.check_parsed(program, absent, None, limits)
    is NeedsInputs(missing) else {
    fail("Calendar selection request")
  }
  let request = @program_check.input_request_at(missing, 0).unwrap()
  assert_true(request.kind is HostCalendarSelection)
  assert_true(@program_check.input_request_source(request) is None)
  assert_eq(@program_check.input_request_path(request), [
    @source.Key("host_policy_profile"),
    @source.Key("calendar"),
  ])
  let location = @program_check.diagnostic_location(
    @program_check.input_requests_diagnostic(missing),
  ).unwrap()
  assert_eq(
    @program_check.diagnostic_location_source_path(location),
    "calendar.actql",
  )
  let body = "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"table_bytes_cid\":\"sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca\",\"tzdb_version\":\"test-fixture\",\"version\":\"actql-calendar-selection/0.1\"}"
  let (_, _, selected, _, _) = public_input_fixture(
    calendar_profile=true,
    calendar_selection=Some(
      (
        body, "sha256:a9646640cb1cf2518bc0504c6e46ab477b4486d7f8261b77bed3ef13705c6b6e",
      ),
    ),
  )
  guard @program_check.check_parsed(program, selected, None, limits)
    is NeedsInputs(material) else {
    fail("Calendar artifact request")
  }
  let artifact = @program_check.input_request_at(material, 0).unwrap()
  guard artifact.kind is CalendarProfileArtifact(selection) else {
    fail("Calendar artifact selection")
  }
  assert_eq(@environment.calendar_selection_release(selection), "test-fixture")
  let source = @program_check.input_request_source(artifact).unwrap()
  assert_true(
    physical_equal(source, @environment.calendar_selection_source(selection)),
  )
  assert_eq(
    @decode.text(source),
    Ok(@environment.calendar_selection_cid(selection)),
  )
  let table = "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"coverage_end_ms\":253402300800000,\"coverage_start_ms\":-62135596800000,\"tzdb_version\":\"test-fixture\",\"version\":\"actql-tzdb-table/0.1\",\"zones\":{\"UTC\":{\"initial_offset_seconds\":0,\"transitions\":[]}}}"
  let profile = @environment.admit_calendar_profile(
    selection,
    @utf8.encode(table),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 8,
      max_zones: 1,
      max_transitions: 0,
    },
  ).unwrap()
  let complete = @program_check.checking_environment(
    @environment.calendar_selection_environment(selection),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: true, calendar: true, text_rank: false, },
    calendar=Some(profile),
  )
  let checked = public_checked(
    @program_check.check_parsed(program, complete, None, limits),
  )
  assert_eq(@program_check.unit_count(checked), 2)
  assert_true(
    @program_check.check_document(text, complete, None, limits, format=Json)
    is Checked(_),
  )
  let (_, _, independent, _, _) = public_input_fixture(
    calendar_profile=true,
    calendar_selection=Some(
      (
        body, "sha256:a9646640cb1cf2518bc0504c6e46ab477b4486d7f8261b77bed3ef13705c6b6e",
      ),
    ),
  )
  guard @program_check.check_parsed(program, independent, None, limits)
    is NeedsInputs(other) else {
    fail("independent Calendar request")
  }
  guard @program_check.input_request_at(other, 0).unwrap().kind
    is CalendarProfileArtifact(other_selection) else {
    fail("independent Calendar selection")
  }
  let foreign = @program_check.checking_environment(
    @environment.calendar_selection_environment(other_selection),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: true, calendar: true, text_rank: false, },
    calendar=Some(profile),
  )
  guard @program_check.check_parsed(program, foreign, None, limits)
    is Rejected(diagnostic) else {
    fail("same-pin foreign Calendar artifact accepted")
  }
  assert_true(
    @program_check.diagnostic_cause(diagnostic)
    is @program_check.LocalConstructionFailure::Source(
      SourceView(Program(ForeignCalendarEnvironment))
    ),
  )
  for
    (bad, cid) in [
      (
        "null", "sha256:690a65a5fc9ee958cb8881fe4a4b4154dd84fcf1b7d401dda1ed52663e9dbc10",
      ),
      (
        "{}", "sha256:291378e25b4f81dac84c4698aa89fe3c89fbceea41be226668b64a86dc300af9",
      ),
    ] {
    let (_, _, invalid, _, _) = public_input_fixture(
      calendar_profile=true,
      calendar_selection=Some((bad, cid)),
    )
    guard @program_check.check_parsed(program, invalid, None, limits)
      is Rejected(diagnostic) else {
      fail("malformed Calendar selection became a request")
    }
    assert_true(
      @program_check.diagnostic_cause(diagnostic)
      is @program_check.LocalConstructionFailure::Source(
        SourceView(Program(CalendarSelection(InvalidComponent)))
      ),
    )
  }
  assert_true(
    @program_check.check_parsed(program, selected, None, {
      ..limits,
      compilation: { ..limits.compilation, work: 0, },
    })
    is Rejected(_),
  )
}
