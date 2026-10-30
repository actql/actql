///|
fn free_busy_limits() -> CalendarFreeBusyLimits {
  {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 16,
    max_calendars: 4,
    max_rows: 10,
    max_request_bytes: 4096,
    max_value_nodes: 100,
    max_value_text_bytes: 4096,
  }
}

///|
fn free_busy_query(
  ids? : Array[String] = ["a@example.test", "b"],
) -> CalendarFreeBusyQuery {
  prepare_calendar_free_busy_query(
    ids,
    "2026-10-17T00:00:00.000Z",
    "2026-10-18T00:00:00.000Z",
    free_busy_limits(),
  ).unwrap()
}

///|
fn free_busy_response() -> String {
  (
    // Deliberately reversed map order; output follows the original calendar
    // selection, then every interval occurrence, without a fabricated key.
    #|{"kind":"calendar#freeBusy","timeMin":"2026-10-17T00:00:00Z","timeMax":"2026-10-18T00:00:00Z","calendars":{"b":{"busy":[]},"a@example.test":{"busy":[{"start":"2026-10-17T10:00:00+09:00","end":"2026-10-17T10:30:00.5000+09:00"},{"start":"2026-10-17T01:00:00Z","end":"2026-10-17T01:30:00.5Z"}]}}}
  )
}

///|
fn free_busy_page(
  text : String,
) -> Result[CalendarFreeBusyPage, CalendarFreeBusyIssue] {
  project_calendar_free_busy(
    @utf8.encode(text),
    free_busy_query(),
    free_busy_limits(),
  )
}

///|
test "Calendar free busy keeps original calendar order interval multiplicity and UTC instants" {
  let query = free_busy_query()
  let original = free_busy_response()
  let page = project_calendar_free_busy(
    @utf8.encode(original),
    query,
    free_busy_limits(),
  ).unwrap()
  assert_eq(page.response_sha256, @sha.hex(@utf8.encode(original)))
  assert_eq(calendar_free_busy_row_count(page), 2)
  assert_true(calendar_free_busy_matches_query(page, query))
  assert_false(calendar_free_busy_matches_query(page, free_busy_query()))
  assert_eq(
    calendar_free_busy_rows_wire(
      page,
      ["calendar_id", "start", "end"],
      4096,
      100,
      8,
    ).unwrap(),
    (
      #|[{"calendar_id":"a@example.test","start":"2026-10-17T01:00:00.000Z","end":"2026-10-17T01:30:00.500Z"},{"calendar_id":"a@example.test","start":"2026-10-17T01:00:00.000Z","end":"2026-10-17T01:30:00.500Z"}]
    ),
  )
  assert_eq(
    calendar_free_busy_rows_wire(page, ["end"], 4096, 100, 8).unwrap(),
    (
      #|[{"end":"2026-10-17T01:30:00.500Z"},{"end":"2026-10-17T01:30:00.500Z"}]
    ),
  )
}

///|
test "Calendar free busy query snapshots ordered calendar selection and emits explicit UTC request" {
  let ids = ["b", "a@example.test"]
  let query = free_busy_query(ids~)
  ids[0] = "substitution"
  assert_eq(
    calendar_free_busy_request_wire(query),
    (
      #|{"timeMin":"2026-10-17T00:00:00.000Z","timeMax":"2026-10-18T00:00:00.000Z","timeZone":"UTC","calendarExpansionMax":2,"items":[{"id":"b"},{"id":"a@example.test"}]}
    ),
  )
  for selected in [[], [""], ["a", "a"], ["a", "b", "c", "d", "e"]] {
    assert_true(
      prepare_calendar_free_busy_query(
        selected,
        "2026-10-17T00:00:00.000Z",
        "2026-10-18T00:00:00.000Z",
        free_busy_limits(),
      )
      is Err(InvalidQuery),
    )
  }
  for
    (start, end) in [
      ("2026-10-17T00:00:00Z", "2026-10-18T00:00:00.000Z"),
      ("2026-10-18T00:00:00.000Z", "2026-10-18T00:00:00.000Z"),
      ("2026-10-19T00:00:00.000Z", "2026-10-18T00:00:00.000Z"),
      ("2026-02-30T00:00:00.000Z", "2026-10-18T00:00:00.000Z"),
    ] {
    assert_true(
      prepare_calendar_free_busy_query(["a"], start, end, free_busy_limits())
      is Err(InvalidQuery),
    )
  }
  assert_true(
    prepare_calendar_free_busy_query(
      ["a"],
      "2026-10-17T00:00:00.000Z",
      "2026-10-18T00:00:00.000Z",
      { ..free_busy_limits(), max_request_bytes: 1, },
    )
    is Err(BudgetExceeded),
  )
}

///|
test "Calendar free busy requires every original calendar and rejects foreign and expanded members" {
  let original = free_busy_response()
  for
    body in [
      original.replace(old="\"b\":{\"busy\":[]},", new=""),
      original.replace(old="\"b\":", new="\"other\":"),
      original.replace(old="\"b\":{", new="\"foreign\":{},\"b\":{"),
      original.replace(
        old="\"calendars\":",
        new="\"groups\":{\"g\":{\"calendars\":[\"b\"]}},\"calendars\":",
      ),
      original.replace(
        old="\"calendars\":",
        new="\"groups\":null,\"calendars\":",
      ),
    ] {
    assert_true(free_busy_page(body) is Err(ForeignCalendars))
  }
  assert_true(
    free_busy_page(
      original.replace(old="\"calendars\":", new="\"groups\":{},\"calendars\":"),
    )
    is Ok(_),
  )
  // Duplicate raw keys fail in the existing bounded source parser, before any
  // map lookup or calendar-count comparison could hide a substituted member.
  assert_true(
    free_busy_page(original.replace(old="\"b\":{", new="\"b\":{},\"b\":{"))
    is Err(_),
  )
}

///|
test "Calendar free busy refuses per-calendar errors rather than publishing a partial relation" {
  for
    errors in [
      "[{\"reason\":\"notFound\",\"domain\":\"calendar\"}]", "null", "{}", "[{}]",
    ] {
    let body = free_busy_response().replace(
      old="\"b\":{",
      new="\"b\":{\"errors\":" + errors + ",",
    )
    assert_true(free_busy_page(body) is Err(CalendarRejected("b")))
  }
  let body = free_busy_response().replace(
    old="\"b\":{",
    new="\"b\":{\"errors\":[],",
  )
  assert_true(free_busy_page(body) is Ok(_))
}

///|
test "Calendar free busy empty busy may be omitted but explicit null and malformed intervals refuse" {
  let original = free_busy_response()
  assert_true(
    free_busy_page(original.replace(old="\"b\":{\"busy\":[]}", new="\"b\":{}"))
    is Ok(_),
  )
  for value in ["null", "{}", "false", "7"] {
    assert_true(
      free_busy_page(
        original.replace(
          old="\"b\":{\"busy\":[]}",
          new="\"b\":{\"busy\":" + value + "}",
        ),
      )
      is Err(InvalidResponse),
    )
  }
  for value in ["null", "true", "7", "{}", "[]", "\"\""] {
    assert_true(
      free_busy_page(
        original.replace(
          old="\"start\":\"2026-10-17T10:00:00+09:00\"",
          new="\"start\":" + value,
        ),
      )
      is Err(InvalidInterval),
    )
  }
  assert_true(
    free_busy_page(
      original.replace(
        old="2026-10-17T10:30:00.5000+09:00",
        new="2026-10-17T10:00:00+09:00",
      ),
    )
    is Err(InvalidInterval),
  )
}

///|
test "Calendar free busy response window must match the original requested instants" {
  let original = free_busy_response()
  assert_true(
    free_busy_page(
      original.replace(
        old="2026-10-17T00:00:00Z",
        new="2026-10-17T09:00:00+09:00",
      ),
    )
    is Ok(_),
  )
  for
    body in [
      original.replace(old="calendar#freeBusy", new="calendar#events"),
      original.replace(old="2026-10-18T00:00:00Z", new="2026-10-19T00:00:00Z"),
      original.replace(old="\"timeMin\":\"2026-10-17T00:00:00Z\",", new=""),
      original.replace(
        old="\"timeMin\":\"2026-10-17T00:00:00Z\"",
        new="\"timeMin\":null",
      ),
    ] {
    assert_true(free_busy_page(body) is Err(InvalidResponse))
  }
}

///|
test "Calendar RFC3339 conversion keeps exact precision explicit offsets and valid dates" {
  for
    (input, expected) in [
      ("2026-10-17T10:00:00+09:00", "2026-10-17T01:00:00.000Z"),
      ("2026-10-17T01:00:00-02:30", "2026-10-17T03:30:00.000Z"),
      ("2026-10-17t01:00:00.123000z", "2026-10-17T01:00:00.123Z"),
      ("2026-10-17T00:00:00.1+00:00", "2026-10-17T00:00:00.100Z"),
      ("2026-10-17T00:00:00.12Z", "2026-10-17T00:00:00.120Z"),
      ("2024-03-01T00:30:00+01:00", "2024-02-29T23:30:00.000Z"),
    ] {
    assert_eq(calendar_rfc3339(input), Some(expected))
  }
  for
    input in [
      "2026-02-29T00:00:00Z", "2026-10-17T25:00:00Z", "2026-10-17T00:00:60Z", "2026-10-17T00:00:00.0001Z",
      "2026-10-17T00:00:00.Z", "2026-10-17T00:00:00-00:00", "2026-10-17T00:00:00+24:00",
      "2026-10-17T00:00:00+00:60", "2026-10-17T00:00:00", "0000-01-01T00:00:00+01:00",
      "9999-12-31T23:59:59-01:00",
    ] {
    assert_eq(calendar_rfc3339(input), None)
  }
}

///|
test "Calendar free busy applies complete response cell and projection budgets independently" {
  let bytes = @utf8.encode(free_busy_response())
  for
    limits in [
      { ..free_busy_limits(), max_bytes: bytes.length() - 1, },
      { ..free_busy_limits(), max_nodes: 3, },
      { ..free_busy_limits(), max_depth: 2, },
      { ..free_busy_limits(), max_rows: 1, },
      { ..free_busy_limits(), max_calendars: 1, },
      { ..free_busy_limits(), max_value_nodes: 5, },
      { ..free_busy_limits(), max_value_text_bytes: 1, },
    ] {
    assert_true(
      project_calendar_free_busy(bytes, free_busy_query(), limits)
      is Err(BudgetExceeded),
    )
  }
  for
    limits in [
      { ..free_busy_limits(), max_rows: 0, },
      { ..free_busy_limits(), max_calendars: 51, },
    ] {
    assert_true(
      project_calendar_free_busy(bytes, free_busy_query(), limits)
      is Err(InvalidLimits),
    )
  }
  let page = free_busy_page(free_busy_response()).unwrap()
  for names in [["missing"], ["start", "start"]] {
    assert_true(
      calendar_free_busy_rows_wire(page, names, 4096, 100, 8)
      is Err(InvalidSelection(_)),
    )
  }
  for (bytes, nodes, depth) in [(1, 100, 8), (4096, 1, 8), (4096, 100, 1)] {
    assert_true(
      calendar_free_busy_rows_wire(page, ["end"], bytes, nodes, depth)
      is Err(BudgetExceeded),
    )
  }
  assert_eq(calendar_free_busy_column_names(), ["calendar_id", "start", "end"])
  assert_eq(calendar_free_busy_facts_wire(), "{}")
  assert_eq(
    calendar_free_busy_schema_wire(1024, 64, 8).unwrap(),
    (
      #|{"calendar_id":{"nullable":false,"type":"string"},"end":{"nullable":false,"type":"timestamp"},"start":{"nullable":false,"type":"timestamp"}}
    ),
  )
  assert_true(calendar_free_busy_schema_wire(1, 64, 8) is Err(BudgetExceeded))
}

///|
test "Calendar free busy preserves canonical submillisecond Request bounds without a clock projection" {
  for
    (start, end) in [
      ("2026-10-17T00:00:00.0001Z", "2026-10-17T00:00:00.0002Z"),
      ("1969-12-31T23:59:59.999999999Z", "1970-01-01T00:00:00.000Z"),
    ] {
    let query = prepare_calendar_free_busy_query(
      ["original@example.test"],
      start,
      end,
      free_busy_limits(),
    ).unwrap()
    assert_eq(
      calendar_free_busy_request_wire(query),
      "{\"timeMin\":\"" +
      start +
      "\",\"timeMax\":\"" +
      end +
      "\",\"timeZone\":\"UTC\",\"calendarExpansionMax\":1,\"items\":[{\"id\":\"original@example.test\"}]}",
    )
  }
}

///|
test "Calendar free busy response retains distinct original data keys without NFC aliasing" {
  let query = free_busy_query(ids=["calendar/é", "calendar/é"])
  let page = project_calendar_free_busy(
    @utf8.encode(
      (
        #|{"kind":"calendar#freeBusy","timeMin":"2026-10-17T00:00:00Z","timeMax":"2026-10-18T00:00:00Z","calendars":{"calendar/é":{"busy":[{"start":"2026-10-17T01:00:00Z","end":"2026-10-17T02:00:00Z"}]},"calendar/é":{"busy":[{"start":"2026-10-17T03:00:00Z","end":"2026-10-17T04:00:00Z"}]}}}
      ),
    ),
    query,
    free_busy_limits(),
  ).unwrap()
  assert_eq(
    calendar_free_busy_rows_wire(
      page,
      ["calendar_id", "start", "end"],
      4096,
      100,
      8,
    ).unwrap(),
    (
      #|[{"calendar_id":"calendar/é","start":"2026-10-17T01:00:00.000Z","end":"2026-10-17T02:00:00.000Z"},{"calendar_id":"calendar/é","start":"2026-10-17T03:00:00.000Z","end":"2026-10-17T04:00:00.000Z"}]
    ),
  )
}
