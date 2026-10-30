///|
fn free_busy_original_request() -> String {
  (
    #|{"calendar_id":"calendar/é@example.test","time_min":"2026-10-17T00:00:00.0001Z","time_max":"2026-10-17T00:00:00.0002Z"}
  )
}

///|
test "Calendar free busy original Request preserves selected ID exact instants and original page correspondence" {
  let query = prepare_calendar_free_busy_request(
    free_busy_original_request(),
    free_busy_limits(),
  ).unwrap()
  assert_eq(
    calendar_free_busy_request_wire(query),
    (
      #|{"timeMin":"2026-10-17T00:00:00.0001Z","timeMax":"2026-10-17T00:00:00.0002Z","timeZone":"UTC","calendarExpansionMax":1,"items":[{"id":"calendar/é@example.test"}]}
    ),
  )
  let page = project_calendar_free_busy(
    @utf8.encode(
      (
        #|{"kind":"calendar#freeBusy","timeMin":"2026-10-17T00:00:00.0001Z","timeMax":"2026-10-17T00:00:00.0002Z","calendars":{"calendar/é@example.test":{"busy":[{"start":"2026-10-17T00:00:00.0001Z","end":"2026-10-17T00:00:00.0002Z"}]}}}
      ),
    ),
    query,
    free_busy_limits(),
  ).unwrap()
  assert_true(calendar_free_busy_matches_query(page, query))
  assert_false(
    calendar_free_busy_matches_query(
      page,
      prepare_calendar_free_busy_request(
        free_busy_original_request(),
        free_busy_limits(),
      ).unwrap(),
    ),
  )
  assert_eq(
    calendar_free_busy_rows_wire(
      page,
      ["calendar_id", "start", "end"],
      4096,
      100,
      8,
    ).unwrap(),
    (
      #|[{"calendar_id":"calendar/é@example.test","start":"2026-10-17T00:00:00.0001Z","end":"2026-10-17T00:00:00.0002Z"}]
    ),
  )
}

///|
test "Calendar free busy original Request refuses absent null extra duplicate and untyped selectors before a query" {
  for
    bad in [
      "{}",
      "[]",
      free_busy_original_request().replace(
        old="\"calendar_id\":\"calendar/é@example.test\",",
        new="",
      ),
      free_busy_original_request().replace(
        old="\"calendar/é@example.test\"",
        new="null",
      ),
      free_busy_original_request().replace(
        old="\"calendar/é@example.test\"",
        new="[]",
      ),
      free_busy_original_request().replace(old="{", new="{\"profile\":\"UTC\","),
      free_busy_original_request().replace(
        old="{",
        new="{\"calendar_id\":\"foreign\",",
      ),
      free_busy_original_request().replace(old=".0001Z", new="Z"),
      free_busy_original_request().replace(old=".0001Z", new=".0001-00:00"),
      free_busy_original_request().replace(old=".0001Z", new=".0002Z"),
      free_busy_original_request().replace(old=".0001Z", new=".0003Z"),
    ] {
    assert_true(
      prepare_calendar_free_busy_request(bad, free_busy_limits()) is Err(_),
    )
  }
  for
    limits in [
      { ..free_busy_limits(), max_request_bytes: 1, },
      { ..free_busy_limits(), max_nodes: 1, },
      { ..free_busy_limits(), max_depth: 1, },
      { ..free_busy_limits(), max_calendars: 0, },
    ] {
    assert_true(
      prepare_calendar_free_busy_request(free_busy_original_request(), limits)
      is Err(_),
    )
  }
}

///|
test "Calendar free busy original Request schema is a complete typed object and retains output limits" {
  assert_eq(
    calendar_free_busy_request_schema_wire(4096, 100, 8).unwrap(),
    (
      #|{"additional_properties":false,"fields":{"calendar_id":{"nullable":false,"type":"string"},"time_max":{"nullable":false,"type":"timestamp"},"time_min":{"nullable":false,"type":"timestamp"}},"nullable":false,"type":"object"}
    ),
  )
  assert_true(
    calendar_free_busy_request_schema_wire(1, 100, 8) is Err(BudgetExceeded),
  )
  assert_true(
    calendar_free_busy_request_schema_wire(4096, 1, 8) is Err(BudgetExceeded),
  )
  assert_true(
    calendar_free_busy_request_schema_wire(0, 100, 8) is Err(InvalidLimits),
  )
}
