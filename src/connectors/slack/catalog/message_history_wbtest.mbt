///|
fn message_history() -> SlackMessageHistory {
  prepare_slack_message_history("C1", message_limits(), 4).unwrap()
}

///|
fn history_admit(
  history : SlackMessageHistory,
  request : SlackMessageHistoryRequest,
  rows : String,
  tail : String,
) -> Result[SlackMessagePage, SlackMessagePageIssue] {
  admit_slack_message_history_page(
    history,
    request,
    @utf8.encode("{\"ok\":true,\"messages\":" + rows + tail + "}"),
  )
}

///|
test "Slack original history admits missing non-thread count as exact signed zero" {
  let history = message_history()
  let request = begin_slack_message_history(history).unwrap()
  assert_true(slack_message_history_request_matches(history, request))
  let raw = "[{\"type\":\"message\",\"ts\":\"1.000001\",\"text\":\"original question\"}]"
  let page = history_admit(history, request, raw, ",\"has_more\":false").unwrap()
  assert_true(page.rows[0][5].value is @admitted.Null)
  assert_true(page.rows[0][6].value is @admitted.Signed64(0L))
  assert_eq(
    message_wire(page, ["thread_ts", "reply_count", "reactions", "files"]),
    "[{\"thread_ts\":null,\"reply_count\":\"0\",\"reactions\":null,\"files\":null}]",
  )
  assert_false(slack_message_history_request_matches(history, request))
  assert_true(
    next_slack_message_history_request(history, page).unwrap() is None,
  )
  // Generic/partial response DATA cannot claim this history occurrence.
  let generic = message_project(
    "{\"ok\":true,\"messages\":" + raw + ",\"has_more\":false}",
  ).unwrap()
  assert_true(generic.rows[0][6].value is @admitted.Null)
}

///|
test "Slack explicit reply counts win without inventing a thread contradiction" {
  for token in ["0", "2", "9223372036854775807", "null"] {
    let history = message_history()
    let request = begin_slack_message_history(history).unwrap()
    let page = history_admit(
      history,
      request,
      "[{\"type\":\"message\",\"ts\":\"1.000000\",\"text\":\"x\",\"reply_count\":" +
      token +
      "}]",
      ",\"has_more\":false",
    ).unwrap()
    let expected = if token == "null" { "null" } else { "\"" + token + "\"" }
    assert_eq(
      message_wire(page, ["reply_count"]),
      "[{\"reply_count\":" + expected + "}]",
    )
  }
  for token in ["-1", "1.01", "9223372036854775808", "\"0\"", "false"] {
    let history = message_history()
    let request = begin_slack_message_history(history).unwrap()
    assert_true(
      history_admit(
        history,
        request,
        "[{\"type\":\"message\",\"ts\":\"1.000000\",\"text\":\"x\",\"reply_count\":" +
        token +
        "}]",
        ",\"has_more\":false",
      )
      is Err(_),
      msg=token,
    )
  }
}

///|
test "Slack retained parents replies null membership and partial records never infer zero" {
  for
    row in [
      "{\"type\":\"message\",\"ts\":\"1.000000\",\"text\":\"parent\",\"thread_ts\":\"1.000000\"}",
      "{\"type\":\"message\",\"ts\":\"2.000000\",\"text\":\"reply\",\"thread_ts\":\"1.000000\"}",
      "{\"type\":\"message\",\"ts\":\"1.000000\",\"text\":\"unknown membership\",\"thread_ts\":null}",
      "{\"type\":\"message\",\"ts\":\"1.000000\"}", "{\"type\":\"message\",\"ts\":\"1.000000\",\"text\":\"partial\",\"event_ts\":\"2.000000\"}",
      "{\"type\":\"message\",\"ts\":\"1.000000\",\"text\":\"unknown subtype\",\"subtype\":\"future_subtype\"}",
    ] {
    let history = message_history()
    let request = begin_slack_message_history(history).unwrap()
    let page = history_admit(
      history,
      request,
      "[" + row + "]",
      ",\"has_more\":false",
    ).unwrap()
    assert_true(page.rows[0][6].value is @admitted.Null, msg=row)
  }
  let history = message_history()
  let request = begin_slack_message_history(history).unwrap()
  let page = history_admit(
    history, request, "[{\"type\":\"message\",\"ts\":\"1.000000\",\"text\":\"replies deleted\",\"thread_ts\":\"1.000000\",\"reply_count\":0}]",
    ",\"has_more\":false",
  ).unwrap()
  assert_eq(
    message_wire(page, ["thread_ts", "reply_count"]),
    "[{\"thread_ts\":\"1.000000\",\"reply_count\":\"0\"}]",
  )
}

///|
test "Slack history requests are nominal single-use and fail closed on malformed input" {
  let history = message_history()
  let foreign = message_history()
  let request = begin_slack_message_history(history).unwrap()
  let copy = begin_slack_message_history(foreign).unwrap()
  assert_false(slack_message_history_request_matches(history, copy))
  assert_true(
    admit_slack_message_history_page(history, copy, b"{}")
    is Err(ForeignHistoryRequest),
  )
  assert_true(slack_message_history_request_matches(history, request))
  assert_true(
    begin_slack_message_history(history) is Err(ForeignHistoryRequest),
  )
  assert_true(
    admit_slack_message_history_page(history, request, b"{") is Err(_),
  )
  assert_false(slack_message_history_request_matches(history, request))
  assert_true(
    admit_slack_message_history_page(
      history, request, b"{\"ok\":true,\"has_more\":false,\"messages\":[]}",
    )
    is Err(ForeignHistoryRequest),
  )
  let duplicate = message_history()
  let first = begin_slack_message_history(duplicate).unwrap()
  assert_true(
    history_admit(
      duplicate, first, "[{\"type\":\"message\",\"ts\":\"1.000000\",\"text\":\"x\",\"reply_count\":0,\"reply_count\":1}]",
      ",\"has_more\":false",
    )
    is Err(_),
  )
}

///|
test "Slack history cursor pages preserve each original and refuse duplicates or loops" {
  let history = message_history()
  let first = begin_slack_message_history(history).unwrap()
  let page = history_admit(
    history, first, "[{\"type\":\"message\",\"ts\":\"2.000000\",\"text\":\"x\"}]",
    ",\"has_more\":false,\"response_metadata\":{\"next_cursor\":\"opaque\"}",
  ).unwrap()
  let next = next_slack_message_history_request(history, page).unwrap().unwrap()
  assert_eq(slack_message_history_request_cursor(next), Some("opaque"))
  assert_eq(slack_message_history_request_ordinal(next), 1)
  assert_eq(slack_message_history_request_channel(next), "C1")
  assert_true(
    next_slack_message_history_request(history, page)
    is Err(ForeignHistoryRequest),
  )
  let end = history_admit(
    history, next, "[{\"type\":\"message\",\"ts\":\"1.000000\",\"text\":\"y\"}]",
    ",\"has_more\":false",
  ).unwrap()
  assert_true(next_slack_message_history_request(history, end).unwrap() is None)
  let duplicate = message_history()
  let first = begin_slack_message_history(duplicate).unwrap()
  let page = history_admit(
    duplicate, first, "[{\"type\":\"message\",\"ts\":\"2.000000\",\"text\":\"x\"}]",
    ",\"has_more\":true,\"response_metadata\":{\"next_cursor\":\"opaque\"}",
  ).unwrap()
  let next = next_slack_message_history_request(duplicate, page)
    .unwrap()
    .unwrap()
  assert_true(
    history_admit(
      duplicate, next, "[{\"type\":\"message\",\"ts\":\"2.000000\",\"text\":\"x\"}]",
      ",\"has_more\":false",
    )
    is Err(DuplicateMessage),
  )
}

///|
test "Slack history time fallback proves exact instant progress without String ordering" {
  let history = message_history()
  let first = begin_slack_message_history(history).unwrap()
  let page = history_admit(
    history, first, "[{\"type\":\"message\",\"ts\":\"10.000000001\",\"text\":\"a\"},{\"type\":\"message\",\"ts\":\"9.999999999\",\"text\":\"b\"}]",
    ",\"has_more\":true",
  ).unwrap()
  let next = next_slack_message_history_request(history, page).unwrap().unwrap()
  assert_eq(slack_message_history_request_latest(next), Some("9.999999999"))
  let end = history_admit(
    history, next, "[{\"type\":\"message\",\"ts\":\"9.000000001\",\"text\":\"a\"}]",
    ",\"has_more\":false",
  ).unwrap()
  assert_true(next_slack_message_history_request(history, end).unwrap() is None)
  let unordered = message_history()
  let request = begin_slack_message_history(unordered).unwrap()
  let page = history_admit(
    unordered, request, "[{\"type\":\"message\",\"ts\":\"1.000000\",\"text\":\"a\"},{\"type\":\"message\",\"ts\":\"2.000000\",\"text\":\"b\"}]",
    ",\"has_more\":true",
  ).unwrap()
  assert_true(
    next_slack_message_history_request(unordered, page)
    is Err(InvalidPagination),
  )
}

///|
test "Slack retention limits bounds and close cannot declare complete history" {
  let history = message_history()
  let request = begin_slack_message_history(history).unwrap()
  let page = history_admit(
    history, request, "[]", ",\"has_more\":false,\"is_limited\":true",
  ).unwrap()
  assert_true(
    next_slack_message_history_request(history, page) is Err(HistoryUnavailable),
  )
  let single = prepare_slack_message_history("C1", message_limits(), 1).unwrap()
  let first = begin_slack_message_history(single).unwrap()
  let page = history_admit(
    single, first, "[{\"type\":\"message\",\"ts\":\"1.000000\",\"text\":\"x\"}]",
    ",\"has_more\":true",
  ).unwrap()
  assert_true(
    next_slack_message_history_request(single, page) is Err(BudgetExceeded),
  )
  let closed = message_history()
  let request = begin_slack_message_history(closed).unwrap()
  close_slack_message_history(closed)
  assert_false(slack_message_history_request_matches(closed, request))
  assert_true(
    admit_slack_message_history_page(closed, request, b"{}")
    is Err(ForeignHistoryRequest),
  )
}

///|
test "Slack retained thread hints cannot turn a missing reply count into zero" {
  for
    fragment in [
      "\"reply_users\":[]", "\"reply_users_count\":0", "\"latest_reply\":\"1.000000\"",
      "\"replies\":[]", "\"parent_user_id\":\"U1\"", "\"root\":{}", "\"assistant_thread\":{}",
      "\"is_thread_broadcast\":true",
    ] {
    let history = message_history()
    let request = begin_slack_message_history(history).unwrap()
    let page = history_admit(
      history,
      request,
      "[{\"type\":\"message\",\"ts\":\"1.000000\",\"text\":\"retained thread metadata\"," +
      fragment +
      "}]",
      ",\"has_more\":false",
    ).unwrap()
    assert_true(page.rows[0][6].value is @admitted.Null, msg=fragment)
  }
}

///|
test "Slack ordinary history bot messages obey the same absence and thread hint rule" {
  let ordinary = "{\"type\":\"message\",\"subtype\":\"bot_message\",\"ts\":\"1.000001\",\"text\":\"ordinary bot\""
  for
    (extra, expected) in [
      ("", "\"0\""),
      (",\"reply_count\":2", "\"2\""),
      (",\"reply_count\":null", "null"),
      (",\"thread_ts\":null", "null"),
      (",\"thread_ts\":\"1.000001\"", "null"),
      (",\"reply_users\":[]", "null"),
      (",\"event_ts\":\"1.000001\"", "null"),
    ] {
    let history = message_history()
    let request = begin_slack_message_history(history).unwrap()
    let page = history_admit(
      history,
      request,
      "[" + ordinary + extra + "}]",
      ",\"has_more\":false",
    ).unwrap()
    assert_eq(
      message_wire(page, ["reply_count"]),
      "[{\"reply_count\":" + expected + "}]",
    )
  }
  let generic = message_project(
    "{\"ok\":true,\"has_more\":false,\"messages\":[" + ordinary + "}]}",
  ).unwrap()
  assert_true(generic.rows[0][6].value is @admitted.Null)
}
