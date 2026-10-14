///|
fn series_fixture(
  table : Table,
  start : String,
  end : String,
  quantum : Int,
) -> (Array[(String, String)], Int) raise {
  let cursor = start_series(
    table,
    @value.timestamp_epoch_milliseconds(start).unwrap(),
    @value.timestamp_epoch_milliseconds(end).unwrap(),
    Day,
    week_start=None,
    max_rows=4,
    max_work=10000,
  ).unwrap()
  let rows = []
  let mut work = 0
  for _ in 0..<10000 {
    match advance_series(cursor, quantum).unwrap() {
      CalendarSeriesContinue(work=used) => work += used
      CalendarSeriesComplete(work=used) => return (rows, work + used)
      CalendarSeriesRow(start_ms~, end_ms~, work=used) => {
        work += used
        rows.push(
          (
            @value.epoch_milliseconds_timestamp(start_ms).unwrap(),
            @value.epoch_milliseconds_timestamp(end_ms).unwrap(),
          ),
        )
      }
      CalendarSeriesFailed(_, ..) =>
        fail("independent series fixture must succeed")
    }
  }
  fail("bounded series fixture must terminate")
}

///|
test "series emits full unclipped buckets in UTC order with exclusive end" {
  let table = full_utc_table()
  let expected = series_fixture(
    table, "2024-02-28T23:59:59.999Z", "2024-03-01T00:00:00.000Z", 1,
  )
  assert_eq(expected.0, [
    ("2024-02-28T00:00:00.000Z", "2024-02-29T00:00:00.000Z"),
    ("2024-02-29T00:00:00.000Z", "2024-03-01T00:00:00.000Z"),
  ])
  for quantum in [2, 7, 64] {
    assert_eq(
      series_fixture(
        table, "2024-02-28T23:59:59.999Z", "2024-03-01T00:00:00.000Z", quantum,
      ),
      expected,
    )
  }
}

///|
test "series collapses skipped day duplicates without clipping" {
  let table = admit(
    -62135596800000L,
    253402300800000L,
    -36000,
    [{ at_ms: 1325239200000L, offset_seconds: 50400, }],
    max_transitions=1,
  ).unwrap()
  let expected = series_fixture(
    table, "2011-12-29T10:00:00.000Z", "2011-12-31T10:00:00.000Z", 1,
  )
  assert_eq(expected.0, [
    ("2011-12-29T10:00:00.000Z", "2011-12-30T10:00:00.000Z"),
    ("2011-12-30T10:00:00.000Z", "2011-12-31T10:00:00.000Z"),
  ])
  assert_eq(
    series_fixture(
      table, "2011-12-29T10:00:00.000Z", "2011-12-31T10:00:00.000Z", 64,
    ),
    expected,
  )
}

///|
test "empty reversed and exhausted series retain typed terminal limits" {
  let table = full_utc_table()
  let empty = start_series(
    table,
    0L,
    0L,
    Day,
    week_start=None,
    max_rows=0,
    max_work=0,
  ).unwrap()
  assert_eq(advance_series(empty, 1), Ok(CalendarSeriesComplete(work=0)))
  assert_eq(advance_series(empty, 1), Err(SeriesTerminal))
  assert_true(
    start_series(table, 1L, 0L, Day, week_start=None, max_rows=4, max_work=100)
    is Err(InvalidSeriesRange),
  )
  let exhausted = start_series(
    table,
    0L,
    1L,
    Day,
    week_start=None,
    max_rows=0,
    max_work=100,
  ).unwrap()
  assert_eq(
    advance_series(exhausted, 1),
    Ok(CalendarSeriesFailed(SeriesRowLimit, work=0)),
  )
  let no_work = start_series(
    table,
    0L,
    1L,
    Day,
    week_start=None,
    max_rows=4,
    max_work=0,
  ).unwrap()
  assert_eq(
    advance_series(no_work, 1),
    Ok(CalendarSeriesFailed(SeriesWorkLimit, work=0)),
  )
}
