///|
fn calendar_profile() -> @calendar_profile.Profile {
  let text = "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"coverage_end_ms\":253402300800000,\"coverage_start_ms\":-62135596800000,\"tzdb_version\":\"test-fixture\",\"version\":\"actql-tzdb-table/0.1\",\"zones\":{\"UTC\":{\"initial_offset_seconds\":0,\"transitions\":[]}}}"
  @calendar_profile.admit(
    @utf8.encode(text),
    "sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca",
    "test-fixture",
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
test "calendar bucket preserves existing boundary roles without inventing new ones" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-02T00:00:00.000Z\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"days\"},{\"row_window\":{\"kind\":\"fixed\",\"time\":\"start\",\"size\":1000}},{\"calendar_bucket\":{\"time\":\"start\",\"into\":\"bucket\",\"unit\":\"month\",\"timezone\":\"UTC\"}},{\"window_group\":{\"by\":[],\"aggregates\":{}}}]",
    ),
    [],
    None,
    None,
    limits(),
    calendar_profile=Some(calendar_profile()),
  ).unwrap()
  assert_true(
    @pipeline_typing.window_evidence(@pipeline_typing.step_at(p, 0).unwrap())
    is None,
  )
  assert_true(
    @pipeline_typing.window_evidence(@pipeline_typing.step_at(p, 2).unwrap())
    is Some(_),
  )
  assert_true(
    @pipeline_typing.window_evidence(@pipeline_typing.step_at(p, 3).unwrap())
    is Some(_),
  )
}

///|
test "calendar generator rejects a selector and requires its alias" {
  let operation = "\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-02T00:00:00.000Z\",\"unit\":\"day\",\"timezone\":\"UTC\"}"
  assert_true(
    @pipeline_typing.check_carriers(
      cursor("[{" + operation + "}]"),
      [],
      None,
      None,
      limits(),
      calendar_profile=Some(calendar_profile()),
    )
    is Err({ kind: GeneratorRequiresAlias, .. }),
  )
  assert_true(
    @pipeline_typing.check_carriers(
      cursor("[{" + operation + ",\"as\":\"days\",\"from\":\"other\"}]"),
      [],
      None,
      None,
      limits(),
      calendar_profile=Some(calendar_profile()),
    )
    is Err({ kind: GeneratorFrom, .. }),
  )
}

///|
test "calendar generator and bucket connect to ordinary relation consumers" {
  let s = cursor(
    "[{\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-02T00:00:00.000Z\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"days\"},{\"calendar_bucket\":{\"time\":\"start\",\"into\":\"bucket\",\"unit\":\"month\",\"timezone\":\"UTC\"}},{\"select\":[\"bucket\"]}]",
  )
  assert_true(
    @pipeline_typing.check_carriers(s, [], None, None, limits())
    is Err({ kind: Calendar(MissingProfile), .. }),
  )
  let p = @pipeline_typing.check_carriers(
    s,
    [],
    None,
    None,
    limits(),
    calendar_profile=Some(calendar_profile()),
  ).unwrap()
  let first = @pipeline_typing.step_at(p, 0).unwrap()
  assert_true(first.operation is Calendar(_))
  assert_true(first.input is None)
  assert_true(@pipeline_typing.input_occurrences(first).is_empty())
  let second = @pipeline_typing.step_at(p, 1).unwrap()
  assert_eq(second.input, Some(Step(0)))
  assert_eq(@pipeline_typing.input_occurrences(second).length(), 1)
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 1)
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_carriers(
      s,
      [],
      None,
      None,
      exact,
      calendar_profile=Some(calendar_profile()),
    )
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_carriers(
        s,
        [],
        None,
        None,
        cap,
        calendar_profile=Some(calendar_profile()),
      )
      is Err(_),
    )
  }
}
