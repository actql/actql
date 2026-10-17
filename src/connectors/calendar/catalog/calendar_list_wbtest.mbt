///|
fn calendar_limits() -> CalendarListLimits {
  {
    max_bytes: 8192,
    max_nodes: 1024,
    max_depth: 16,
    max_rows: 10,
    max_cursor_units: 128,
    max_value_nodes: 100,
    max_value_text_bytes: 4096,
  }
}

///|
fn list_page(text : String) -> Result[CalendarListPage, CalendarListIssue] {
  project_calendar_list(@utf8.encode(text), calendar_limits())
}

///|
fn original_list() -> String {
  (
    #|{"kind":"calendar#calendarList","nextPageToken":"opaque/+ =","items":[{"id":"sales@example.test","summary":"売上 📅","timeZone":"Asia/Tokyo","accessRole":"writer","deleted":false},{"id":"private","summary":"","timeZone":"UTC","accessRole":"freeBusyReader"}]}
  )
}

///|
test "Calendar list preserves original string identities fields empty summary and opaque cursor" {
  let original = original_list()
  let page = list_page(original).unwrap()
  assert_eq(page.response_sha256, @sha.hex(@utf8.encode(original)))
  assert_eq(page.next_page_token, Some("opaque/+ ="))
  assert_eq(calendar_list_row_count(page), 2)
  assert_eq(calendar_list_ids(page), ["sales@example.test", "private"])
  assert_eq(
    calendar_list_rows_wire(
      page,
      ["id", "summary", "time_zone", "access_role"],
      8192,
      100,
      8,
    ).unwrap(),
    (
      #|[{"id":"sales@example.test","summary":"売上 📅","time_zone":"Asia/Tokyo","access_role":"writer"},{"id":"private","summary":"","time_zone":"UTC","access_role":"freeBusyReader"}]
    ),
  )
  assert_eq(
    calendar_list_rows_wire(page, ["summary"], 8192, 100, 8).unwrap(),
    (
      #|[{"summary":"売上 📅"},{"summary":""}]
    ),
  )
}

///|
test "Calendar list empty items may be omitted but null malformed and foreign collection refuse" {
  for
    body in [
      (
        #|{"kind":"calendar#calendarList"}
      ),
      (
        #|{"kind":"calendar#calendarList","items":[]}
      ),
    ] {
    let page = list_page(body).unwrap()
    assert_eq(calendar_list_row_count(page), 0)
    assert_eq(page.next_page_token, None)
    assert_eq(calendar_list_rows_wire(page, ["id"], 100, 10, 4).unwrap(), "[]")
  }
  for
    body in [
      "{}",
      "null",
      "[]",
      (
        #|{"kind":"calendar#calendarList","items":null}
      ),
      (
        #|{"kind":"calendar#events","items":[]}
      ),
      (
        #|{"kind":"calendar#calendarList","items":{}}
      ),
    ] {
    assert_true(list_page(body) is Err(InvalidResponse))
  }
}

///|
test "Calendar list validates every declared field before any requested projection" {
  for field in ["id", "summary", "timeZone", "accessRole"] {
    let original = "{\"kind\":\"calendar#calendarList\",\"items\":[{\"id\":\"one\",\"summary\":\"title\",\"timeZone\":\"UTC\",\"accessRole\":\"reader\"}]}"
    let old = match field {
      "id" => "\"id\":\"one\""
      "summary" => "\"summary\":\"title\""
      "timeZone" => "\"timeZone\":\"UTC\""
      _ => "\"accessRole\":\"reader\""
    }
    for value in ["null", "7", "false", "[]", "{}"] {
      assert_true(
        list_page(original.replace(old~, new="\"" + field + "\":" + value))
        is Err(InvalidCell(_)),
      )
    }
    assert_true(
      list_page(
        original.replace(old=old + ",", new="").replace(old="," + old, new=""),
      )
      is Err(InvalidCell(_)),
    )
  }
}

///|
test "Calendar list rejects duplicate keys empty identity and unexpected tombstones without filtering" {
  let original = original_list()
  assert_true(
    list_page(
      original.replace(
        old="\"id\":\"private\"",
        new="\"id\":\"sales@example.test\"",
      ),
    )
    is Err(DuplicateCalendar("sales@example.test")),
  )
  assert_true(
    list_page(original.replace(old="\"id\":\"private\"", new="\"id\":\"\""))
    is Err(InvalidCell("id")),
  )
  for value in ["true", "null", "\"false\"", "{}"] {
    assert_true(
      list_page(
        original.replace(old="\"deleted\":false", new="\"deleted\":" + value),
      )
      is Err(InvalidResponse),
    )
  }
  assert_true(
    list_page(
      original.replace(
        old="\"id\":\"private\"",
        new="\"id\":\"private\",\"id\":\"other\"",
      ),
    )
    is Err(_),
  )
}

///|
test "Calendar list bounds cursor response row and admitted value budgets separately" {
  let bytes = @utf8.encode(original_list())
  for
    limits in [
      { ..calendar_limits(), max_bytes: bytes.length() - 1, },
      { ..calendar_limits(), max_rows: 1, },
      { ..calendar_limits(), max_nodes: 3, },
      { ..calendar_limits(), max_depth: 2, },
      { ..calendar_limits(), max_value_nodes: 7, },
      { ..calendar_limits(), max_value_text_bytes: 1, },
    ] {
    assert_true(project_calendar_list(bytes, limits) is Err(BudgetExceeded))
  }
  assert_true(
    project_calendar_list(bytes, { ..calendar_limits(), max_rows: 0, })
    is Err(InvalidLimits),
  )
  for value in ["null", "false", "7", "[]", "\"\""] {
    assert_true(
      list_page(
        original_list().replace(
          old="\"nextPageToken\":\"opaque/+ =\"",
          new="\"nextPageToken\":" + value,
        ),
      )
      is Err(InvalidCursor),
    )
  }
  assert_true(
    project_calendar_list(bytes, { ..calendar_limits(), max_cursor_units: 1, })
    is Err(InvalidCursor),
  )
}

///|
test "Calendar list output schema facts and projection use existing Common contracts and bounds" {
  assert_eq(
    calendar_list_schema_wire(1024, 64, 8).unwrap(),
    (
      #|{"access_role":{"nullable":false,"type":"string"},"id":{"nullable":false,"type":"string"},"summary":{"nullable":false,"type":"string"},"time_zone":{"nullable":false,"type":"string"}}
    ),
  )
  assert_eq(
    calendar_list_facts_wire(),
    "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}",
  )
  let page = list_page(original_list()).unwrap()
  for names in [["missing"], ["id", "id"]] {
    assert_true(
      calendar_list_rows_wire(page, names, 8192, 100, 8)
      is Err(InvalidSelection(_)),
    )
  }
  for (bytes, nodes, depth) in [(1, 100, 8), (8192, 1, 8), (8192, 100, 1)] {
    assert_true(
      calendar_list_rows_wire(page, ["id"], bytes, nodes, depth)
      is Err(BudgetExceeded),
    )
  }
  assert_true(calendar_list_schema_wire(1, 64, 8) is Err(BudgetExceeded))
}
