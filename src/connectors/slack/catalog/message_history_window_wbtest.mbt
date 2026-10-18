///|
fn window_history(oldest : String?, latest : String?) -> SlackMessageHistory {
  prepare_slack_message_history_window(
    "C1",
    oldest,
    latest,
    message_limits(),
    8,
  ).unwrap()
}

///|
fn window_row(ts : String) -> String {
  "[{\"type\":\"message\",\"ts\":\"" + ts + "\",\"text\":\"original\"}]"
}

///|
test "Slack history window retains exact original decimal boundary tokens" {
  let history = window_history(Some("1.000001000"), Some("2.100000"))
  let request = begin_slack_message_history(history).unwrap()
  assert_eq(slack_message_history_request_oldest(request), Some("1.000001000"))
  assert_eq(slack_message_history_request_latest(request), Some("2.100000"))
  let page = history_admit(
    history,
    request,
    window_row("2.01"),
    ",\"has_more\":false",
  ).unwrap()
  assert_true(
    next_slack_message_history_request(history, page).unwrap() is None,
  )
  let unbounded = begin_slack_message_history(message_history()).unwrap()
  assert_true(slack_message_history_request_oldest(unbounded) is None)
  assert_true(slack_message_history_request_latest(unbounded) is None)
}

///|
test "Slack history cursor and time pagination retain the same original lower bound" {
  let history = window_history(Some("1.000001"), Some("3.000001"))
  let first = begin_slack_message_history(history).unwrap()
  let page = history_admit(
    history,
    first,
    window_row("2.100000"),
    ",\"has_more\":true,\"response_metadata\":{\"next_cursor\":\"original\"}",
  ).unwrap()
  let second = next_slack_message_history_request(history, page)
    .unwrap()
    .unwrap()
  assert_eq(slack_message_history_request_cursor(second), Some("original"))
  assert_eq(slack_message_history_request_oldest(second), Some("1.000001"))
  assert_eq(slack_message_history_request_latest(second), Some("3.000001"))
  let page = history_admit(
    history,
    second,
    window_row("2.01"),
    ",\"has_more\":true",
  ).unwrap()
  let third = next_slack_message_history_request(history, page)
    .unwrap()
    .unwrap()
  assert_true(slack_message_history_request_cursor(third) is None)
  assert_eq(slack_message_history_request_oldest(third), Some("1.000001"))
  assert_eq(slack_message_history_request_latest(third), Some("2.01"))
  let page = history_admit(
    history,
    third,
    window_row("1.000002"),
    ",\"has_more\":false",
  ).unwrap()
  assert_true(
    next_slack_message_history_request(history, page).unwrap() is None,
  )
}

///|
test "Slack history window refuses exact endpoints and outside rows before completion" {
  for
    ts in [
      "1.000001", "1.000001000", "1.000000999", "2.01", "2.010000000", "2.1",
    ] {
    let history = window_history(Some("1.000001"), Some("2.01"))
    let request = begin_slack_message_history(history).unwrap()
    assert_true(
      history_admit(history, request, window_row(ts), ",\"has_more\":false")
      is Err(InvalidPagination),
      msg=ts,
    )
    assert_false(slack_message_history_request_matches(history, request))
    assert_false(history.completed)
    assert_true(history.pages.is_empty())
    assert_true(
      history_admit(history, request, window_row("1.5"), ",\"has_more\":false")
      is Err(ForeignHistoryRequest),
    )
  }
}

///|
test "Slack history window validates complete known cells even outside its interval" {
  for ts in ["1.5", "3.0"] {
    let history = window_history(Some("1.0"), Some("2.0"))
    let request = begin_slack_message_history(history).unwrap()
    // A selection cannot skip an unused known field, whether the row lies in
    // the original interval or violates it. Page admission comes first.
    assert_true(
      history_admit(
        history,
        request,
        "[{\"type\":\"message\",\"ts\":\"" +
        ts +
        "\",\"text\":\"excluded\",\"reply_count\":false}]",
        ",\"has_more\":false",
      )
      is Err(InvalidCell("reply_count")),
    )
    assert_false(history.completed)
  }
}

///|
test "Slack history window refuses malformed inverted and over-budget originals" {
  for
    (oldest, latest) in [
      (Some("1"), None),
      (None, Some("NaN")),
      (Some("2.1"), Some("2.01")),
      (Some("1.0"), Some("1.000000000")),
      (Some("1.0000000001"), None),
    ] {
    assert_true(
      prepare_slack_message_history_window(
        "C1",
        oldest,
        latest,
        message_limits(),
        8,
      )
      is Err(_),
    )
  }
  let short = { ..message_limits(), max_value_text_bytes: 4, }
  assert_true(
    prepare_slack_message_history_window("C1", Some("1.001"), None, short, 8)
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_slack_message_history_window("C1", None, Some("2.001"), short, 8)
    is Err(BudgetExceeded),
  )
}
