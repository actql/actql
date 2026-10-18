///|
test "Slack replies compare complete repeated admitted text without halving its value bound" {
  let (_, replies) = replies_parent()
  let rows = "[{\"type\":\"message\",\"ts\":\"1.000001\",\"text\":\"" +
    "x".repeat(9000) +
    "\"}]"
  let request = begin_slack_message_replies(replies).unwrap()
  let first = reply_page(
    replies, request, rows, ",\"has_more\":true,\"response_metadata\":{\"next_cursor\":\"next\"}",
  ).unwrap()
  assert_eq(slack_message_replies_page_row_count(first), 1)
  let next = next_slack_message_replies_request(replies, first)
    .unwrap()
    .unwrap()
  let last = reply_page(replies, next, rows, ",\"has_more\":false").unwrap()
  assert_eq(slack_message_replies_page_row_count(last), 0)
  assert_true(
    next_slack_message_replies_request(replies, last).unwrap() is None,
  )
  assert_eq(slack_message_replies_retained_page_count(replies), 2)
}

///|
test "Slack replies comparison exhaustion consumes the original pending request" {
  let (source, _) = replies_parent()
  let replies = prepare_slack_message_replies(source, 0, {
    ..replies_limits(),
    comparison: { max_nodes: 2048, max_depth: 16, max_text_bytes: 8, },
  }).unwrap()
  let request = begin_slack_message_replies(replies).unwrap()
  let rows = "[{\"type\":\"message\",\"ts\":\"1.000001\",\"text\":\"parent\"}]"
  let first = reply_page(
    replies, request, rows, ",\"has_more\":true,\"response_metadata\":{\"next_cursor\":\"next\"}",
  ).unwrap()
  let next = next_slack_message_replies_request(replies, first)
    .unwrap()
    .unwrap()
  assert_true(
    reply_page(replies, next, rows, ",\"has_more\":false")
    is Err(BudgetExceeded),
  )
  assert_false(slack_message_replies_request_matches(replies, next))
  assert_true(
    reply_page(replies, next, rows, ",\"has_more\":false")
    is Err(ForeignRepliesRequest),
  )
}

///|
test "Slack replies recover the actual parent from an originally unthreaded member and require that member" {
  for include_member in [false, true] {
    let (_, replies) = replies_source(
      "[{\"type\":\"message\",\"ts\":\"2.000001\"}]", 0,
    )
    let request = begin_slack_message_replies(replies).unwrap()
    assert_eq(slack_message_replies_request_ts(request), "2.000001")
    let rows = if include_member {
      "[{\"type\":\"message\",\"ts\":\"1.000001\",\"thread_ts\":\"1.000001\"},{\"type\":\"message\",\"ts\":\"2.000001\",\"thread_ts\":\"1.000001\"}]"
    } else {
      "[{\"type\":\"message\",\"ts\":\"1.000001\",\"thread_ts\":\"1.000001\"}]"
    }
    let page = reply_page(replies, request, rows, ",\"has_more\":false").unwrap()
    if include_member {
      assert_true(
        next_slack_message_replies_request(replies, page).unwrap() is None,
      )
    } else {
      assert_true(
        next_slack_message_replies_request(replies, page)
        is Err(InconsistentThread),
      )
    }
  }
}
