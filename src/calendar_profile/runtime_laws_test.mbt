///|
fn runtime_law_profile() -> @calendar_profile.Profile {
  @calendar_profile.admit(real_fixture(), real_fixture_cid(), "2025b", {
    max_bytes: 900000,
    max_nodes: 100000,
    max_depth: 8,
    max_zones: 3,
    max_transitions: 20000,
  }).unwrap()
}

///|
fn runtime_law_resolution(
  table : @transition.Table,
  text : String,
) -> String raise {
  let cursor = @transition.start_local_resolution(
    table,
    @value.timestamp_epoch_milliseconds(text + "Z").unwrap(),
    max_work=100000,
  ).unwrap()
  for _ in 0..<100000 {
    match @transition.advance_local_resolution(cursor, 127).unwrap() {
      ResolutionContinue(_) => ()
      ResolutionReady(utc_ms~, ..) =>
        return @value.epoch_milliseconds_timestamp(utc_ms).unwrap()
      ResolutionFailed(_, ..) => fail("fixed inverse law must succeed")
    }
  }
  fail("finite inverse law must terminate")
}

///|
fn runtime_law_bucket(
  table : @transition.Table,
  text : String,
  unit : @options.CalendarUnit,
  week : @options.WeekStart?,
  quantum : Int,
) -> (Result[(String, String), @transition.IntervalIssue], Int) raise {
  let cursor = @transition.start_interval(
    table,
    @value.timestamp_epoch_milliseconds(text).unwrap(),
    unit,
    week_start=week,
    max_work=1000000,
  ).unwrap()
  let mut work = 0
  for _ in 0..<1000000 {
    match @transition.advance_interval(cursor, quantum).unwrap() {
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
  fail("finite boundary law must terminate")
}

///|
fn runtime_law_series(
  table : @transition.Table,
  start : String,
  end : String,
  unit : @options.CalendarUnit,
  week : @options.WeekStart?,
  quantum : Int,
) -> (Array[(String, String)], Int) raise {
  let cursor = @transition.start_series(
    table,
    @value.timestamp_epoch_milliseconds(start).unwrap(),
    @value.timestamp_epoch_milliseconds(end).unwrap(),
    unit,
    week_start=week,
    max_rows=10,
    max_work=2000000,
  ).unwrap()
  let rows = []
  let mut work = 0
  for _ in 0..<2000000 {
    match @transition.advance_series(cursor, quantum).unwrap() {
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
      CalendarSeriesFailed(_, ..) => fail("fixed series law must succeed")
    }
  }
  fail("finite series law must terminate")
}
