///|
fn replies_limits() -> SlackMessageRepliesLimits {
  {
    page: message_limits(),
    comparison: { max_nodes: 2048, max_depth: 16, max_text_bytes: 32768, },
    max_pages: 4,
    max_total_rows: 16,
    max_total_bytes: 32768,
    max_work: 100000,
  }
}

///|
fn replies_source(
  rows : String,
  index : Int,
) -> (SlackMessagePage, SlackMessageReplies) {
  let history = message_history()
  let request = begin_slack_message_history(history).unwrap()
  let page = history_admit(history, request, rows, ",\"has_more\":false").unwrap()
  let replies = prepare_slack_message_replies(page, index, replies_limits()).unwrap()
  (page, replies)
}

///|
fn replies_parent() -> (SlackMessagePage, SlackMessageReplies) {
  replies_source(
    "[{\"type\":\"message\",\"ts\":\"1.000001\",\"thread_ts\":\"1.000001\",\"text\":\"parent\",\"reply_count\":2}]",
    0,
  )
}

///|
fn reply_page(
  replies : SlackMessageReplies,
  request : SlackMessageRepliesRequest,
  rows : String,
  tail : String,
) -> Result[SlackMessageRepliesPage, SlackMessagePageIssue] {
  admit_slack_message_replies_page(
    replies,
    request,
    @utf8.encode("{\"ok\":true,\"messages\":" + rows + tail + "}"),
  )
}

///|
test "Slack replies selection retains exact original history page and source row" {
  let (source, replies) = replies_parent()
  assert_true(slack_message_replies_matches_original(replies, source, 0))
  let (foreign, _) = replies_parent()
  assert_false(slack_message_replies_matches_original(replies, foreign, 0))
  assert_false(slack_message_replies_matches_original(replies, source, 1))
  assert_true(
    prepare_slack_message_replies(source, -1, replies_limits())
    is Err(InvalidSelection(_)),
  )
  let generic = message_project(
    "{\"ok\":true,\"has_more\":false,\"messages\":[{\"type\":\"message\",\"ts\":\"1.000001\"}]}",
  ).unwrap()
  assert_true(
    prepare_slack_message_replies(generic, 0, replies_limits())
    is Err(InvalidSelection(_)),
  )
  let request = begin_slack_message_replies(replies).unwrap()
  assert_eq(slack_message_replies_request_channel(request), "C1")
  assert_eq(slack_message_replies_request_ts(request), "1.000001")
  assert_true(slack_message_replies_request_matches(replies, request))
  assert_true(
    begin_slack_message_replies(replies) is Err(ForeignRepliesRequest),
  )
}

///|
test "Slack replies retain full original cursor prefix and exact parent child identities" {
  let (_, replies) = replies_parent()
  let request = begin_slack_message_replies(replies).unwrap()
  let page = reply_page(
    replies, request, "[{\"type\":\"message\",\"ts\":\"1.000001\",\"thread_ts\":\"1.000001\",\"text\":\"parent\",\"reply_count\":2},{\"type\":\"message\",\"ts\":\"2.000001\",\"thread_ts\":\"1.000001\",\"text\":\"reply\"}]",
    ",\"has_more\":true,\"response_metadata\":{\"next_cursor\":\"opaque+/=\"}",
  ).unwrap()
  assert_eq(slack_message_replies_page_row_count(page), 2)
  assert_eq(slack_message_replies_retained_page_count(replies), 1)
  let next = next_slack_message_replies_request(replies, page).unwrap().unwrap()
  assert_eq(slack_message_replies_request_cursor(next), Some("opaque+/="))
  assert_eq(slack_message_replies_request_ts(next), "1.000001")
  assert_eq(slack_message_replies_request_ordinal(next), 1)
  let end = reply_page(
    replies, next, "[{\"type\":\"message\",\"ts\":\"3.000001\",\"thread_ts\":\"1.000001\",\"text\":\"last\"}]",
    ",\"has_more\":false",
  ).unwrap()
  assert_true(next_slack_message_replies_request(replies, end).unwrap() is None)
  assert_eq(slack_message_replies_retained_page_count(replies), 2)
  assert_eq(
    slack_message_replies_page_rows_wire(
      end,
      ["id", "thread_ts", "reply_count"],
      4096,
      128,
      8,
    ).unwrap(),
    "[{\"id\":\"C1:3.000001\",\"thread_ts\":\"1.000001\",\"reply_count\":null}]",
  )
  close_slack_message_replies(replies)
  assert_eq(slack_message_replies_retained_page_count(replies), 2)
  assert_eq(slack_message_replies_page_row_count(page), 2)
}

///|
test "Slack unthreaded replies response cannot inherit history zero inference" {
  let (_, replies) = replies_source(
    "[{\"type\":\"message\",\"ts\":\"1.000001\",\"text\":\"ordinary\"}]", 0,
  )
  let request = begin_slack_message_replies(replies).unwrap()
  let page = reply_page(
    replies, request, "[{\"type\":\"message\",\"ts\":\"1.000001\",\"text\":\"ordinary\"}]",
    ",\"has_more\":false",
  ).unwrap()
  assert_eq(
    slack_message_replies_page_rows_wire(page, ["reply_count"], 4096, 128, 8).unwrap(),
    "[{\"reply_count\":null}]",
  )
  assert_true(
    next_slack_message_replies_request(replies, page).unwrap() is None,
  )
}

///|
test "Slack selected original reply chooses its retained parent without inventing a row" {
  let (_, replies) = replies_source(
    "[{\"type\":\"message\",\"ts\":\"2.000001\",\"thread_ts\":\"1.000001\",\"text\":\"selected reply\"}]",
    0,
  )
  let request = begin_slack_message_replies(replies).unwrap()
  assert_eq(slack_message_replies_request_ts(request), "1.000001")
  let page = reply_page(
    replies, request, "[{\"type\":\"message\",\"ts\":\"1.000001\",\"thread_ts\":\"1.000001\",\"text\":\"actual parent\"},{\"type\":\"message\",\"ts\":\"2.000001\",\"thread_ts\":\"1.000001\",\"text\":\"selected reply\"}]",
    ",\"has_more\":false",
  ).unwrap()
  assert_true(
    next_slack_message_replies_request(replies, page).unwrap() is None,
  )
}

///|
test "Slack replies completion requires actual parent source and same-thread observations" {
  for
    rows in [
      "[]", "[{\"type\":\"message\",\"ts\":\"2.000001\",\"thread_ts\":\"1.000001\"}]",
      "[{\"type\":\"message\",\"ts\":\"1.000001\",\"thread_ts\":\"foreign\"}]", "[{\"type\":\"message\",\"ts\":\"1.000001\"},{\"type\":\"message\",\"ts\":\"3.000001\",\"thread_ts\":\"4.000001\"}]",
    ] {
    let (_, replies) = replies_parent()
    let request = begin_slack_message_replies(replies).unwrap()
    match reply_page(replies, request, rows, ",\"has_more\":false") {
      Ok(page) =>
        assert_true(next_slack_message_replies_request(replies, page) is Err(_))
      Err(_) => ()
    }
    assert_false(slack_message_replies_request_matches(replies, request))
  }
}

///|
test "Slack repeated exact response rows retain original pages while conflicting repeats refuse" {
  for changed in [false, true] {
    let (_, replies) = replies_parent()
    let first = begin_slack_message_replies(replies).unwrap()
    let page = reply_page(
      replies, first, "[{\"type\":\"message\",\"ts\":\"1.000001\",\"text\":\"parent\"}]",
      ",\"has_more\":false,\"response_metadata\":{\"next_cursor\":\"next\"}",
    ).unwrap()
    let next = next_slack_message_replies_request(replies, page)
      .unwrap()
      .unwrap()
    let text = if changed { "changed" } else { "parent" }
    let result = reply_page(
      replies,
      next,
      "[{\"type\":\"message\",\"ts\":\"1.000001\",\"text\":\"" + text + "\"}]",
      ",\"has_more\":false",
    )
    if changed {
      assert_true(result is Err(InconsistentThread))
    } else {
      let end = result.unwrap()
      assert_eq(slack_message_replies_page_row_count(end), 0)
      assert_true(
        next_slack_message_replies_request(replies, end).unwrap() is None,
      )
      assert_eq(slack_message_replies_retained_page_count(replies), 2)
    }
  }
}

///|
test "Slack reply time pagination advances exact ascending exclusive boundary" {
  let (_, replies) = replies_parent()
  let first = begin_slack_message_replies(replies).unwrap()
  let page = reply_page(
    replies, first, "[{\"type\":\"message\",\"ts\":\"1.000001\"},{\"type\":\"message\",\"ts\":\"1.000001001\",\"thread_ts\":\"1.000001\"}]",
    ",\"has_more\":true",
  ).unwrap()
  let next = next_slack_message_replies_request(replies, page).unwrap().unwrap()
  assert_eq(slack_message_replies_request_oldest(next), Some("1.000001001"))
  let end = reply_page(
    replies, next, "[{\"type\":\"message\",\"ts\":\"1.000001002\",\"thread_ts\":\"1.000001\"}]",
    ",\"has_more\":false",
  ).unwrap()
  assert_true(next_slack_message_replies_request(replies, end).unwrap() is None)
}

///|
test "Slack replies foreign stale requests loops and malformed responses fail closed" {
  let (_, replies) = replies_parent()
  let (_, foreign) = replies_parent()
  let request = begin_slack_message_replies(replies).unwrap()
  let other = begin_slack_message_replies(foreign).unwrap()
  assert_true(
    admit_slack_message_replies_page(replies, other, b"{}")
    is Err(ForeignRepliesRequest),
  )
  assert_true(slack_message_replies_request_matches(replies, request))
  assert_true(
    admit_slack_message_replies_page(replies, request, b"{") is Err(_),
  )
  assert_false(slack_message_replies_request_matches(replies, request))
  assert_true(
    admit_slack_message_replies_page(replies, request, b"{}")
    is Err(ForeignRepliesRequest),
  )
  let (_, looped) = replies_parent()
  let first = begin_slack_message_replies(looped).unwrap()
  let page = reply_page(
    looped, first, "[{\"type\":\"message\",\"ts\":\"1.000001\"}]", ",\"has_more\":true,\"response_metadata\":{\"next_cursor\":\"again\"}",
  ).unwrap()
  let next = next_slack_message_replies_request(looped, page).unwrap().unwrap()
  let end = reply_page(
    looped, next, "[]", ",\"has_more\":true,\"response_metadata\":{\"next_cursor\":\"again\"}",
  ).unwrap()
  assert_true(
    next_slack_message_replies_request(looped, end) is Err(InvalidPagination),
  )
}

///|
test "Slack replies page byte row work and emitted wire bounds remain independent" {
  let (source, _) = replies_parent()
  for
    limits in [
      { ..replies_limits(), max_total_bytes: 1, },
      { ..replies_limits(), max_work: 1, },
      { ..replies_limits(), max_total_rows: 1, },
    ] {
    let replies = prepare_slack_message_replies(source, 0, limits).unwrap()
    let request = begin_slack_message_replies(replies).unwrap()
    assert_true(
      reply_page(
        replies, request, "[{\"type\":\"message\",\"ts\":\"1.000001\"},{\"type\":\"message\",\"ts\":\"2.000001\",\"thread_ts\":\"1.000001\"}]",
        ",\"has_more\":false",
      )
      is Err(BudgetExceeded),
    )
  }
  assert_true(
    prepare_slack_message_replies(source, 0, {
      ..replies_limits(),
      max_pages: 0,
    })
    is Err(InvalidLimits),
  )
  let replies = prepare_slack_message_replies(source, 0, replies_limits()).unwrap()
  let request = begin_slack_message_replies(replies).unwrap()
  let page = reply_page(
    replies, request, "[{\"type\":\"message\",\"ts\":\"1.000001\"}]", ",\"has_more\":false",
  ).unwrap()
  assert_true(
    slack_message_replies_page_rows_wire(page, ["id"], 1, 100, 8)
    is Err(BudgetExceeded),
  )
  assert_true(
    slack_message_replies_page_rows_wire(page, ["foreign"], 1024, 100, 8)
    is Err(InvalidSelection(_)),
  )
}
