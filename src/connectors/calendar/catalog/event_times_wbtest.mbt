///|
fn event_time_profile() -> @calendar_profile.Profile {
  // Synthetic immutable transition fixture, not an IANA dataset certification.
  // Canonical bytes and SHA-256 were authored with Python independently.
  let wire =
    #|{"conversion_law":"actql-calendar-boundaries/0.1","coverage_end_ms":253402300800000,"coverage_start_ms":-62135596800000,"tzdb_version":"calendar-event-test","version":"actql-tzdb-table/0.1","zones":{"Fixture/Eastern":{"initial_offset_seconds":-18000,"transitions":[{"at_ms":1772953200000,"offset_seconds":-14400},{"at_ms":1793512800000,"offset_seconds":-18000}]},"UTC":{"initial_offset_seconds":0,"transitions":[]}}}
  @calendar_profile.admit(
    @utf8.encode(wire),
    "sha256:a693071b15721fd914a7e98cf8acbf88b8b8e31b364478016220dbe8272e4043",
    "calendar-event-test",
    {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 12,
      max_zones: 2,
      max_transitions: 2,
    },
  ).unwrap()
}

///|
fn event_time_limits() -> CalendarEventTimeLimits {
  { max_bytes: 4096, max_nodes: 100, max_depth: 12, max_resolution_work: 8, }
}

///|
fn event_times(
  body : String,
) -> Result[CalendarEventTimes, CalendarEventTimeIssue] {
  project_calendar_event_times(
    @utf8.encode(body),
    "Fixture/Eastern",
    event_time_profile(),
    event_time_limits(),
  )
}

///|
test "Calendar Event explicit offsets preserve exact nanoseconds before and after epoch" {
  let body =
    #|{"kind":"calendar#event","start":{"dateTime":"2026-03-01T10:11:12.123456789+09:00"},"end":{"dateTime":"2026-03-01T10:12:13.1234+09:00"}}
  let times = event_times(body).unwrap()
  assert_eq(times.start, "2026-03-01T01:11:12.123456789Z")
  assert_eq(times.end, "2026-03-01T01:12:13.1234Z")
  assert_false(times.all_day)
  assert_eq(
    times.calendar_profile_cid,
    "sha256:a693071b15721fd914a7e98cf8acbf88b8b8e31b364478016220dbe8272e4043",
  )
  let before = event_times(
    (
      #|{"kind":"calendar#event","start":{"dateTime":"1969-12-31T23:59:59.999999999Z"},"end":{"dateTime":"1970-01-01T00:00:00Z"}}
    ),
  ).unwrap()
  assert_eq(before.start, "1969-12-31T23:59:59.999999999Z")
  assert_eq(before.end, "1970-01-01T00:00:00.000Z")
}

///|
test "Calendar Event all-day boundaries use the same selected calendar table across DST" {
  let times = event_times(
    (
      #|{"kind":"calendar#event","start":{"date":"2026-03-08"},"end":{"date":"2026-03-09"}}
    ),
  ).unwrap()
  assert_true(times.all_day)
  assert_eq(times.start, "2026-03-08T05:00:00.000Z")
  assert_eq(times.end, "2026-03-09T04:00:00.000Z")
  assert_eq(
    @admitted.timestamp_epoch_milliseconds(times.end).unwrap() -
    @admitted.timestamp_epoch_milliseconds(times.start).unwrap(),
    82800000L,
  )
}

///|
test "Calendar Event explicit local zones retain the selected fold and forward-gap law" {
  let fold = event_times(
    (
      #|{"kind":"calendar#event","start":{"dateTime":"2026-11-01T01:30:00.123456789","timeZone":"Fixture/Eastern"},"end":{"dateTime":"2026-11-01T01:45:00.123456789","timeZone":"Fixture/Eastern"}}
    ),
  ).unwrap()
  assert_eq(fold.start, "2026-11-01T05:30:00.123456789Z")
  assert_eq(fold.end, "2026-11-01T05:45:00.123456789Z")
  let gap = event_times(
    (
      #|{"kind":"calendar#event","start":{"dateTime":"2026-03-08T02:30:00.123456789","timeZone":"Fixture/Eastern"},"end":{"dateTime":"2026-03-08T03:30:00.123456789","timeZone":"Fixture/Eastern"}}
    ),
  ).unwrap()
  assert_eq(gap.start, "2026-03-08T07:00:00.000Z")
  assert_eq(gap.end, "2026-03-08T07:30:00.123456789Z")
}

///|
test "Calendar Event does not invent offsets zones dates or mixed endpoint kinds" {
  for
    body in [
      (
        #|{"kind":"calendar#event","start":{"date":"2026-02-30"},"end":{"date":"2026-03-01"}}
      ),
      (
        #|{"kind":"calendar#event","start":{"date":null},"end":{"date":"2026-03-01"}}
      ),
      (
        #|{"kind":"calendar#event","start":{"date":"2026-03-01","dateTime":"2026-03-01T00:00:00Z"},"end":{"date":"2026-03-02"}}
      ),
      (
        #|{"kind":"calendar#event","start":{"dateTime":"2026-03-01T00:00:00"},"end":{"dateTime":"2026-03-01T01:00:00Z"}}
      ),
      (
        #|{"kind":"calendar#event","start":{"dateTime":"2026-03-01T00:00:00-00:00","timeZone":"UTC"},"end":{"dateTime":"2026-03-01T01:00:00Z"}}
      ),
      (
        #|{"kind":"calendar#event","start":{"dateTime":"2026-03-01T00:00:00Z","timeZone":null},"end":{"dateTime":"2026-03-01T01:00:00Z"}}
      ),
      (
        #|{"kind":"calendar#event","start":{"dateTime":"2026-03-01T00:00:00.1234567891Z"},"end":{"dateTime":"2026-03-01T01:00:00Z"}}
      ),
    ] {
    assert_true(event_times(body) is Err(InvalidTime))
  }
  assert_true(
    event_times(
      (
        #|{"kind":"calendar#event","start":{"dateTime":"2026-03-01T00:00:00","timeZone":"Unknown/Zone"},"end":{"dateTime":"2026-03-01T01:00:00Z"}}
      ),
    )
    is Err(TimeZoneUnavailable),
  )
  assert_true(
    event_times(
      (
        #|{"kind":"calendar#event","start":{"date":"2026-03-01"},"end":{"dateTime":"2026-03-02T00:00:00Z"}}
      ),
    )
    is Err(MixedTimeKinds),
  )
}

///|
test "Calendar Event shares finite resolution work and never extrapolates the original table" {
  let body = @utf8.encode(
    (
      #|{"kind":"calendar#event","start":{"date":"2026-03-08"},"end":{"date":"2026-03-09"}}
    ),
  )
  let limits = event_time_limits()
  let profile = event_time_profile()
  assert_true(
    project_calendar_event_times(body, "Fixture/Eastern", profile, {
      ..limits,
      max_resolution_work: 7,
    })
    is Err(ResolutionWorkLimit),
  )
  assert_true(
    project_calendar_event_times(body, "Fixture/Eastern", profile, {
      ..limits,
      max_bytes: body.length() - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_calendar_event_times(body, "Unknown/Zone", profile, limits)
    is Err(TimeZoneUnavailable),
  )
  assert_true(
    event_times(
      (
        #|{"kind":"calendar#event","start":{"date":"0000-01-01"},"end":{"date":"0000-01-02"}}
      ),
    )
    is Err(TimeZoneCoverage),
  )
}

///|
test "Calendar Event preserves zero-duration pairs and refuses reversed or absent originals" {
  let same = event_times(
    (
      #|{"kind":"calendar#event","start":{"dateTime":"2026-03-01T00:00:00Z"},"end":{"dateTime":"2026-03-01T00:00:00Z"}}
    ),
  ).unwrap()
  assert_eq(same.start, same.end)
  assert_true(
    event_times(
      (
        #|{"kind":"calendar#event","start":{"date":"2026-03-09"},"end":{"date":"2026-03-08"}}
      ),
    )
    is Err(ReversedInterval),
  )
  assert_true(
    event_times(
      (
        #|{"kind":"calendar#event","start":{"dateTime":"2026-03-01T02:00:00Z"},"end":{"dateTime":"2026-03-01T01:00:00Z"}}
      ),
    )
    is Err(ReversedInterval),
  )
  for
    body in [
      (
        #|{"kind":"calendar#event","id":"cancelled-original","status":"cancelled"}
      ),
      (
        #|{"kind":"calendar#event","start":{},"end":{}}
      ),
      (
        #|{"kind":"calendar#events","start":{},"end":{}}
      ),
    ] {
    assert_true(event_times(body) is Err(InvalidEvent | InvalidTime))
  }
}
