///|
fn events_test_limits() -> CalendarEventsLimits {
  {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_rows: 10,
    max_identity_bytes: 128,
    max_cursor_bytes: 128,
    max_attendees: 100,
    max_value_nodes: 1000,
    max_value_text_bytes: 8192,
    max_resolution_work: 100,
  }
}

///|
fn events_test_query() -> CalendarEventsQuery {
  prepare_calendar_events_query(
    "calendar/é@example.test",
    "2026-03-01T10:00:00.1234+09:00",
    "2026-03-02T10:00:00.1234+09:00",
    "Fixture/Eastern",
    event_time_profile(),
    events_test_limits(),
  ).unwrap()
}

///|
fn events_envelope(
  body : String,
) -> Result[CalendarEventsEnvelope, CalendarEventsIssue] {
  project_calendar_events_envelope(
    @utf8.encode(body),
    events_test_query(),
    events_test_limits(),
  )
}

///|
test "Calendar Events query retains original bounds zone and selected Profile without request defaults" {
  let profile = event_time_profile()
  let query = prepare_calendar_events_query(
    "calendar/é@example.test",
    "2026-03-01T10:00:00.1234+09:00",
    "2026-03-02T10:00:00.1234+09:00",
    "Fixture/Eastern",
    profile,
    events_test_limits(),
  ).unwrap()
  assert_true(physical_equal(query.profile, profile))
  assert_eq(
    calendar_events_query_wire(query, 4096, 50, 8).unwrap(),
    (
      #|{"calendar_id":"calendar/é@example.test","time_min":"2026-03-01T10:00:00.1234+09:00","time_max":"2026-03-02T10:00:00.1234+09:00","time_zone":"Fixture/Eastern"}
    ),
  )
  for
    (minimum, maximum) in [
      ("2026-03-02T10:00:00Z", "2026-03-01T10:00:00Z"),
      ("2026-03-01T10:00:00Z", "2026-03-01T10:00:00Z"),
      ("2026-03-01T10:00:00", "2026-03-02T10:00:00Z"),
      ("2026-03-01T10:00:00-00:00", "2026-03-02T10:00:00Z"),
    ] {
    assert_true(
      prepare_calendar_events_query(
        "calendar",
        minimum,
        maximum,
        "Fixture/Eastern",
        profile,
        events_test_limits(),
      )
      is Err(InvalidQuery),
    )
  }
  assert_true(
    prepare_calendar_events_query(
      "calendar",
      "2026-03-01T10:00:00Z",
      "2026-03-02T10:00:00Z",
      "Unknown/Zone",
      profile,
      events_test_limits(),
    )
    is Err(TimeZoneUnavailable),
  )
  assert_true(
    calendar_events_query_wire(query, 1, 50, 8) is Err(BudgetExceeded),
  )
}

///|
test "Calendar Events envelope retains the same query original IDs and opaque cursor" {
  let query = events_test_query()
  let page = project_calendar_events_envelope(
    @utf8.encode(
      (
        #|{"kind":"calendar#events","timeZone":"Fixture/Eastern","nextPageToken":"original /+é cursor","items":[{"kind":"calendar#event","id":"event/é"},{"kind":"calendar#event","id":"event/é","status":"cancelled"}]}
      ),
    ),
    query,
    events_test_limits(),
  ).unwrap()
  assert_true(physical_equal(page.query, query))
  assert_eq(
    calendar_events_envelope_calendar_id(page),
    "calendar/é@example.test",
  )
  assert_eq(
    calendar_events_envelope_profile_cid(page),
    "sha256:a693071b15721fd914a7e98cf8acbf88b8b8e31b364478016220dbe8272e4043",
  )
  assert_eq(page.next_page_token, Some("original /+é cursor"))
  assert_eq(calendar_events_envelope_count(page), 2)
  let exposed = calendar_events_envelope_ids(page)
  exposed[0] = "replacement"
  assert_eq(calendar_events_envelope_ids(page), ["event/é", "event/é"])
  // This is deliberately only the original envelope. Complete typed row
  // admission remains separate; sparse bodies above are not Source capture.
}

///|
test "Calendar Events envelope keeps empty continuation and refuses foreign malformed or duplicate input" {
  for
    body in [
      (
        #|{"kind":"calendar#events","timeZone":"Fixture/Eastern","nextPageToken":"next"}
      ),
      (
        #|{"kind":"calendar#events","timeZone":"Fixture/Eastern","nextPageToken":"next","items":[]}
      ),
    ] {
    let page = events_envelope(body).unwrap()
    assert_eq(calendar_events_envelope_count(page), 0)
    assert_eq(page.next_page_token, Some("next"))
  }
  assert_true(
    events_envelope(
      (
        #|{"kind":"calendar#events","timeZone":"UTC","items":[]}
      ),
    )
    is Err(ForeignTimeZone),
  )
  assert_true(
    events_envelope(
      (
        #|{"kind":"calendar#events","timeZone":"Fixture/Eastern","items":[{"kind":"calendar#event","id":"same"},{"kind":"calendar#event","id":"same"}]}
      ),
    )
    is Err(DuplicateEvent("same")),
  )
  for
    body in [
      (
        #|{"kind":"calendar#events","timeZone":"Fixture/Eastern","items":null}
      ),
      (
        #|{"kind":"calendar#events","timeZone":"Fixture/Eastern","nextPageToken":null}
      ),
      (
        #|{"kind":"calendar#events","timeZone":"Fixture/Eastern","nextPageToken":""}
      ),
      (
        #|{"kind":"calendar#events","timeZone":"Fixture/Eastern","items":[{"kind":"calendar#event","id":7}]}
      ),
      (
        #|{"kind":"calendar#events","timeZone":"Fixture/Eastern","items":[{"kind":"calendar#event","id":"x","id":"y"}]}
      ),
      (
        #|{"kind":"calendar#event","timeZone":"Fixture/Eastern","items":[]}
      ),
    ] {
    assert_true(events_envelope(body) is Err(_))
  }
  let bytes = @utf8.encode(
    (
      #|{"kind":"calendar#events","timeZone":"Fixture/Eastern","items":[{"kind":"calendar#event","id":"one"},{"kind":"calendar#event","id":"two"}]}
    ),
  )
  let limits = events_test_limits()
  assert_true(
    project_calendar_events_envelope(bytes, events_test_query(), {
      ..limits,
      max_rows: 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_calendar_events_envelope(bytes, events_test_query(), {
      ..limits,
      max_bytes: bytes.length() - 1,
    })
    is Err(BudgetExceeded),
  )
}
