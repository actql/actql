///|
fn events_rows_test(
  items : String,
  limits? : CalendarEventsLimits = events_test_limits(),
) -> Result[CalendarEventsPage, CalendarEventsIssue] {
  project_calendar_events(
    @utf8.encode(
      "{\"kind\":\"calendar#events\",\"timeZone\":\"Fixture/Eastern\",\"items\":" +
      items +
      "}",
    ),
    events_test_query(),
    limits,
  )
}

///|
fn events_rows_test_wire(
  page : CalendarEventsPage,
  names : Array[String],
) -> String {
  calendar_events_rows_wire(page, names, 16384, 2000, 30).unwrap()
}

///|
test "Calendar Event rows retain complete typed cells original identity and nanosecond timestamps" {
  let query = events_test_query()
  let page = project_calendar_events(
    @utf8.encode(
      (
        #|{"kind":"calendar#events","timeZone":"Fixture/Eastern","nextPageToken":"next/é","items":[{"kind":"calendar#event","id":"event/é","iCalUID":"series@example.test","summary":"original title","description":"line 1\nline 2","start":{"dateTime":"2026-03-01T10:00:00.123456789+09:00"},"end":{"dateTime":"2026-03-01T11:00:00.123456789+09:00"},"location":"Room 1","status":"confirmed","organizer":{"email":"Case+tag@Example.test","displayName":"not the email"},"attendees":[{"email":"A@Example.test","responseStatus":"accepted"},{"email":"A@Example.test","responseStatus":"tentative","optional":true}],"recurringEventId":"series","created":"2026-02-01T00:00:00.1234Z","updated":"2026-02-02T00:00:00+09:00","etag":"\"original\""}]}
      ),
    ),
    query,
    events_test_limits(),
  ).unwrap()
  assert_true(calendar_events_matches_query(page, query))
  assert_false(calendar_events_matches_query(page, events_test_query()))
  assert_eq(calendar_events_row_count(page), 1)
  assert_eq(page.next_page_token, Some("next/é"))
  assert_eq(
    events_rows_test_wire(page, calendar_events_column_names()),
    (
      #|[{"id":"event/é","ical_uid":"series@example.test","calendar_id":"calendar/é@example.test","summary":"original title","description":"line 1\nline 2","start":"2026-03-01T01:00:00.123456789Z","end":"2026-03-01T02:00:00.123456789Z","all_day":false,"location":"Room 1","status":"confirmed","organizer":"Case+tag@Example.test","attendees":[{"email":"A@Example.test","optional":false,"response_status":"accepted"},{"email":"A@Example.test","optional":true,"response_status":"tentative"}],"recurring_event_id":"series","created":"2026-02-01T00:00:00.1234Z","updated":"2026-02-01T15:00:00.000Z","etag":"\"original\""}]
    ),
  )
  let ids = calendar_events_ids(page)
  ids[0] = "changed"
  assert_eq(calendar_events_ids(page), ["event/é"])
  assert_true(calendar_events_metadata_wire(page, 4096, 50, 8) is Ok(_))
  assert_eq(
    calendar_events_facts_wire(),
    "{\"relation_keys\":{\"candidate_keys\":[[\"calendar_id\",\"id\"]]}}",
  )
}

///|
test "Calendar Event rows preserve id only tombstones nullable unknowns and recurring instance IDs" {
  let page = events_rows_test(
    (
      #|[{"id":"deleted"},{"id":"cancelled","status":"cancelled","organizer":{"id":"not-email","displayName":"not-email"}},{"id":"instance1","iCalUID":"same-series","recurringEventId":"series"},{"id":"instance2","iCalUID":"same-series","recurringEventId":"series"}]
    ),
  ).unwrap()
  assert_eq(calendar_events_row_count(page), 4)
  assert_eq(
    events_rows_test_wire(page, [
      "id", "status", "start", "end", "all_day", "organizer", "attendees",
    ]),
    (
      #|[{"id":"deleted","status":null,"start":null,"end":null,"all_day":null,"organizer":null,"attendees":null},{"id":"cancelled","status":"cancelled","start":null,"end":null,"all_day":null,"organizer":null,"attendees":null},{"id":"instance1","status":null,"start":null,"end":null,"all_day":null,"organizer":null,"attendees":null},{"id":"instance2","status":null,"start":null,"end":null,"all_day":null,"organizer":null,"attendees":null}]
    ),
  )
  assert_eq(events_rows_test_wire(page, []), "[{},{},{},{}]")
}

///|
test "Calendar Event rows resolve actual all day boundaries but never expose compatibility end" {
  let page = events_rows_test(
    (
      #|[{"id":"day","start":{"date":"2026-03-08"},"end":{"date":"2026-03-09"}},{"id":"unspecified","endTimeUnspecified":true,"start":{"dateTime":"2026-03-01T10:00:00Z"},"end":{"dateTime":"2026-03-01T09:00:00Z"}}]
    ),
  ).unwrap()
  assert_eq(
    events_rows_test_wire(page, ["id", "start", "end", "all_day"]),
    (
      #|[{"id":"day","start":"2026-03-08T05:00:00.000Z","end":"2026-03-09T04:00:00.000Z","all_day":true},{"id":"unspecified","start":"2026-03-01T10:00:00.000Z","end":null,"all_day":false}]
    ),
  )
  assert_true(
    events_rows_test(
      (
        #|[{"id":"bad","endTimeUnspecified":true,"end":{"dateTime":"malformed"}}]
      ),
    )
    is Err(EventTime(_)),
  )
  assert_true(
    events_rows_test(
      (
        #|[{"id":"reversed","start":{"dateTime":"2026-03-01T10:00:00Z"},"end":{"dateTime":"2026-03-01T09:00:00Z"}}]
      ),
    )
    is Err(EventTime(ReversedInterval)),
  )
}

///|
test "Calendar Event rows distinguish complete empty and unavailable attendee lists without defaults" {
  let page = events_rows_test(
    (
      #|[{"id":"empty","attendees":[]},{"id":"absent"},{"id":"omitted","attendeesOmitted":true,"attendees":[]},{"id":"pending","attendees":[{"email":"a@b.test","responseStatus":"accepted","asyncOperation":"inProgress"}]},{"id":"missing-email","attendees":[{"responseStatus":"accepted"}]},{"id":"missing-response","attendees":[{"email":"a@b.test"}]}]
    ),
  ).unwrap()
  assert_eq(
    events_rows_test_wire(page, ["id", "attendees"]),
    (
      #|[{"id":"empty","attendees":[]},{"id":"absent","attendees":null},{"id":"omitted","attendees":null},{"id":"pending","attendees":null},{"id":"missing-email","attendees":null},{"id":"missing-response","attendees":null}]
    ),
  )
}

///|
test "Calendar Event rows refuse malformed present cells even when attendee completeness is unavailable" {
  for
    fields in [
      "\"status\":\"invented\"", "\"summary\":7", "\"organizer\":{\"email\":7}",
      "\"created\":\"2026-03-01T10:00:00-00:00\"", "\"updated\":\"not-a-timestamp\"",
      "\"attendeesOmitted\":null", "\"endTimeUnspecified\":null", "\"attendeesOmitted\":true,\"attendees\":[{\"email\":7}]",
      "\"attendeesOmitted\":true,\"attendees\":[{\"responseStatus\":\"invented\"}]",
      "\"attendeesOmitted\":true,\"attendees\":[{\"optional\":null}]", "\"attendees\":[{\"asyncOperation\":\"inProgress\",\"email\":null}]",
      "\"attendees\":[{\"email\":\"a@b.test\",\"responseStatus\":null}]", "\"attendees\":[{\"asyncOperation\":\"unknown\"}]",
      "\"attendees\":{}",
    ] {
    // Row admission happens before a later SELECT id; no bad cell can be
    // hidden by choosing a smaller downstream projection.
    assert_true(events_rows_test("[{\"id\":\"x\"," + fields + "}]") is Err(_))
  }
}

///|
test "Calendar Event rows preserve whole page bounds schema and bounded output refusal" {
  let body =
    #|[{"id":"one","summary":"title","attendees":[{"email":"a@b.test","responseStatus":"accepted"}]}]
  let limits = events_test_limits()
  let page = events_rows_test(body).unwrap()
  assert_true(
    calendar_events_rows_wire(page, ["id", "id"], 100, 100, 10)
    is Err(InvalidSelection("id")),
  )
  assert_true(
    calendar_events_rows_wire(page, ["not_declared"], 100, 100, 10)
    is Err(InvalidSelection("not_declared")),
  )
  assert_true(
    calendar_events_rows_wire(page, ["id"], 1, 100, 10) is Err(BudgetExceeded),
  )
  assert_true(
    calendar_events_metadata_wire(page, 1, 100, 10) is Err(BudgetExceeded),
  )
  assert_true(calendar_events_schema_wire(16384, 1000, 20) is Ok(_))
  assert_true(calendar_events_schema_wire(1, 1000, 20) is Err(BudgetExceeded))
  assert_true(
    events_rows_test(body, limits={ ..limits, max_attendees: 0, })
    is Err(BudgetExceeded),
  )
  assert_true(
    events_rows_test(body, limits={ ..limits, max_value_nodes: 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    events_rows_test(body, limits={ ..limits, max_value_text_bytes: 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    events_rows_test(
      (
        #|[{"id":"day","start":{"date":"2026-03-08"},"end":{"date":"2026-03-09"}}]
      ),
      limits={ ..limits, max_resolution_work: 0, },
    )
    is Err(EventTime(ResolutionWorkLimit)),
  )
}
