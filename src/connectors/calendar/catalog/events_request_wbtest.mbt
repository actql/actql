///|
fn events_original_request() -> String {
  (
    #|{"calendar_id":"calendar/é@example.test","time_min":"2026-03-01T10:00:00.1234+09:00","time_max":"2026-03-02T10:00:00.1234+09:00","time_zone":"Fixture/Eastern"}
  )
}

///|
test "Calendar Events Source request adapter preserves all original values and the exact selected Profile" {
  let profile = event_time_profile()
  let wire = events_original_request()
  let query = prepare_calendar_events_request(
    wire,
    profile,
    events_test_limits(),
  ).unwrap()
  assert_true(physical_equal(query.profile, profile))
  assert_eq(calendar_events_query_wire(query, 4096, 100, 10).unwrap(), wire)
  // Whitespace/order on provider input do not normalize the business strings.
  let reordered =
    #| {"time_zone":"Fixture/Eastern", "time_max":"2026-03-02T10:00:00.1234+09:00","time_min":"2026-03-01T10:00:00.1234+09:00","calendar_id":"calendar/é@example.test"}
  let again = prepare_calendar_events_request(
    reordered,
    profile,
    events_test_limits(),
  ).unwrap()
  assert_true(physical_equal(again.profile, profile))
  assert_eq(calendar_events_query_wire(again, 4096, 100, 10).unwrap(), wire)
  assert_false(physical_equal(query, again))
  let page = project_calendar_events(
    @utf8.encode(
      "{\"kind\":\"calendar#events\",\"timeZone\":\"Fixture/Eastern\",\"items\":[{\"id\":\"actual-event\"}]}",
    ),
    query,
    events_test_limits(),
  ).unwrap()
  assert_true(calendar_events_matches_query(page, query))
  assert_false(calendar_events_matches_query(page, again))
}

///|
test "Calendar Events Source request adapter refuses omitted null foreign and malformed fields without defaults" {
  let profile = event_time_profile()
  let original = events_original_request()
  for
    bad in [
      "{}",
      "null",
      "[]",
      "7",
      original.replace(
        old="\"time_zone\":\"Fixture/Eastern\"",
        new="\"time_zone\":null",
      ),
      original.replace(old=",\"time_zone\":\"Fixture/Eastern\"", new=""),
      original.replace(
        old="\"time_zone\":\"Fixture/Eastern\"",
        new="\"time_zone\":7",
      ),
      original.replace(
        old="\"time_zone\":\"Fixture/Eastern\"",
        new="\"time_zone\":\"UTC\",\"unexpected\":true",
      ),
      original.replace(
        old="\"time_zone\":\"Fixture/Eastern\"",
        new="\"time_zone\":\"Unknown/Zone\"",
      ),
      original.replace(old="10:00:00.1234+09:00", new="10:00:00-00:00"),
      original.replace(
        old="\"calendar_id\":",
        new="\"calendar_id\":\"shadow\",\"calendar_id\":",
      ),
    ] {
    assert_true(
      prepare_calendar_events_request(bad, profile, events_test_limits())
      is Err(_),
    )
  }
  let limits = events_test_limits()
  for
    limits in [
      { ..limits, max_bytes: @utf8.encode(original).length() - 1, },
      { ..limits, max_nodes: 1, },
      { ..limits, max_depth: 0, },
      { ..limits, max_identity_bytes: 1, },
    ] {
    assert_true(
      prepare_calendar_events_request(original, profile, limits) is Err(_),
    )
  }
}

///|
test "Calendar Events Source request schema is one closed required object distinct from row schema" {
  assert_eq(
    calendar_events_request_schema_wire(4096, 100, 10).unwrap(),
    (
      #|{"additional_properties":false,"fields":{"calendar_id":{"nullable":false,"type":"string"},"time_max":{"nullable":false,"type":"string"},"time_min":{"nullable":false,"type":"string"},"time_zone":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"}
    ),
  )
  assert_true(
    calendar_events_request_schema_wire(1, 100, 10) is Err(BudgetExceeded),
  )
  assert_true(
    calendar_events_request_schema_wire(4096, 1, 10) is Err(BudgetExceeded),
  )
  assert_true(
    calendar_events_request_schema_wire(0, 100, 10) is Err(InvalidLimits),
  )
}
