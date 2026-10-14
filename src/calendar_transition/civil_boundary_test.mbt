///|
fn interval_fixture(
  table : Table,
  instant : String,
  unit : @options.CalendarUnit,
  quantum : Int,
  week_start? : @options.WeekStart? = None,
) -> (Result[(String, String), IntervalIssue], Int) raise {
  let cursor = start_interval(
    table,
    @value.timestamp_epoch_milliseconds(instant).unwrap(),
    unit,
    week_start~,
    max_work=100000,
  ).unwrap()
  let mut work = 0
  for _ in 0..<100000 {
    match advance_interval(cursor, quantum).unwrap() {
      IntervalContinue(work=used) => work += used
      IntervalReady(start_ms~, end_ms~, work=used) =>
        return (
          Ok(
            (
              @value.epoch_milliseconds_timestamp(start_ms).unwrap(),
              @value.epoch_milliseconds_timestamp(end_ms).unwrap(),
            ),
          ),
          work + used,
        )
      IntervalFailed(issue, work=used) => return (Err(issue), work + used)
    }
  }
  fail("bounded calendar fixture must terminate")
}

///|
fn full_utc_table() -> Table raise {
  admit(calendar_domain_start, calendar_domain_end, 0, [], max_transitions=0).unwrap()
}

///|
test "civil month quarter year and weekly origins preserve independent boundaries" {
  let table = full_utc_table()
  let cases : Array[
    (@options.CalendarUnit, @options.WeekStart?, String, String, String),
  ] = [
    (
      Day,
      None,
      "2024-02-29T12:00:00.000Z",
      "2024-02-29T00:00:00.000Z",
      "2024-03-01T00:00:00.000Z",
    ),
    (
      Day,
      None,
      "1900-02-28T23:59:59.999Z",
      "1900-02-28T00:00:00.000Z",
      "1900-03-01T00:00:00.000Z",
    ),
    (
      Month,
      None,
      "2000-02-29T00:00:00.000Z",
      "2000-02-01T00:00:00.000Z",
      "2000-03-01T00:00:00.000Z",
    ),
    (
      Quarter,
      None,
      "2024-04-01T00:00:00.000Z",
      "2024-04-01T00:00:00.000Z",
      "2024-07-01T00:00:00.000Z",
    ),
    (
      Year,
      None,
      "2024-12-31T23:59:59.999Z",
      "2024-01-01T00:00:00.000Z",
      "2025-01-01T00:00:00.000Z",
    ),
    (
      Week,
      Some(Monday),
      "2025-01-01T00:00:00.000Z",
      "2024-12-30T00:00:00.000Z",
      "2025-01-06T00:00:00.000Z",
    ),
    (
      Week,
      Some(Sunday),
      "2025-01-01T00:00:00.000Z",
      "2024-12-29T00:00:00.000Z",
      "2025-01-05T00:00:00.000Z",
    ),
  ]
  for (unit, week, instant, start, end) in cases {
    let expected = interval_fixture(table, instant, unit, 1, week_start=week)
    assert_eq(expected.0, Ok((start, end)))
    for quantum in [2, 7, 64] {
      assert_eq(
        interval_fixture(table, instant, unit, quantum, week_start=week),
        expected,
      )
    }
  }
}

///|
test "selected offset transitions make short and long civil days" {
  // Exact independently pinned New York transition instants for these two
  // boundary vectors. This small table is synthetic, not a provenance claim.
  let table = admit(
    calendar_domain_start,
    calendar_domain_end,
    -18000,
    [
      { at_ms: 1710054000000L, offset_seconds: -14400, },
      { at_ms: 1730613600000L, offset_seconds: -18000, },
    ],
    max_transitions=2,
  ).unwrap()
  assert_eq(
    interval_fixture(table, "2024-03-10T07:00:00.000Z", Day, 1).0,
    Ok(("2024-03-10T05:00:00.000Z", "2024-03-11T04:00:00.000Z")),
  )
  assert_eq(
    interval_fixture(table, "2024-11-03T06:30:00.000Z", Day, 7).0,
    Ok(("2024-11-03T04:00:00.000Z", "2024-11-04T05:00:00.000Z")),
  )
}

///|
test "skipped day coincident boundaries collapse into one adjacent interval" {
  let table = admit(
    calendar_domain_start,
    calendar_domain_end,
    -36000,
    [{ at_ms: 1325239200000L, offset_seconds: 50400, }],
    max_transitions=1,
  ).unwrap()
  assert_eq(
    interval_fixture(table, "2011-12-30T12:00:00.000Z", Day, 1).0,
    Ok(("2011-12-30T10:00:00.000Z", "2011-12-31T10:00:00.000Z")),
  )
}

///|
test "nonmonotone local inverses still choose UTC adjacent boundaries" {
  let table = admit(
    calendar_domain_start,
    calendar_domain_end,
    864000,
    [{ at_ms: 1728000000L, offset_seconds: -950400, }],
    max_transitions=1,
  ).unwrap()
  // Civil day 9 resolves to UTC day 20; day 10 resolves to UTC day 0.
  // The latest boundary before UTC day 20.5 is day 20, not day 19.
  let expected = interval_fixture(table, "1970-01-21T12:00:00.000Z", Day, 1)
  assert_eq(
    expected.0,
    Ok(("1970-01-21T00:00:00.000Z", "1970-02-11T00:00:00.000Z")),
  )
  assert_eq(
    interval_fixture(table, "1970-01-21T12:00:00.000Z", Day, 17),
    expected,
  )
}

///|
test "calendar domain refuses year zero missing week origin and absent adjacent boundary" {
  let table = full_utc_table()
  assert_eq(
    interval_fixture(table, "0001-01-01T00:00:00.000Z", Day, 1).0,
    Ok(("0001-01-01T00:00:00.000Z", "0001-01-02T00:00:00.000Z")),
  )
  assert_eq(
    interval_fixture(table, "9999-12-31T12:00:00.000Z", Day, 7).0,
    Err(CalendarBoundaryDomain),
  )
  assert_eq(
    interval_fixture(
      table,
      "0001-01-01T00:00:00.000Z",
      Week,
      1,
      week_start=Some(Sunday),
    ).0,
    Err(CalendarBoundaryDomain),
  )
  assert_true(
    start_interval(table, -62167219200000L, Day, week_start=None, max_work=100)
    is Err(CalendarBoundaryDomain),
  )
  assert_true(
    start_interval(table, 0L, Week, week_start=None, max_work=100)
    is Err(InvalidWeekOrigin),
  )
  assert_true(
    start_interval(table, 0L, Day, week_start=Some(Monday), max_work=100)
    is Err(InvalidWeekOrigin),
  )
}

///|
test "interval scan has quantum invariant work and typed exhaustion" {
  let table = full_utc_table()
  let cursor = start_interval(table, 0L, Day, week_start=None, max_work=1).unwrap()
  assert_eq(advance_interval(cursor, 1), Ok(IntervalContinue(work=1)))
  assert_eq(
    advance_interval(cursor, 1),
    Ok(IntervalFailed(IntervalWorkLimit, work=0)),
  )
  assert_eq(advance_interval(cursor, 1), Err(IntervalTerminal))
  let invalid = start_interval(table, 0L, Day, week_start=None, max_work=100).unwrap()
  assert_eq(advance_interval(invalid, 0), Err(InvalidIntervalLimits))
  assert_true(
    start_interval(table, 0L, Day, week_start=None, max_work=-1)
    is Err(InvalidIntervalLimits),
  )
}
