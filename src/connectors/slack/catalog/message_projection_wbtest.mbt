///|
fn projection_limits() -> SlackMessageProjectionLimits {
  {
    max_rows: 16,
    max_occurrences: 64,
    max_work: 100000,
    comparison: { max_nodes: 2048, max_depth: 16, max_text_bytes: 32768, },
  }
}

///|
fn projection_history(rows : String) -> (SlackMessageHistory, SlackMessagePage) {
  let history = message_history()
  let request = begin_slack_message_history(history).unwrap()
  let page = history_admit(history, request, rows, ",\"has_more\":false").unwrap()
  assert_true(
    next_slack_message_history_request(history, page).unwrap() is None,
  )
  (history, page)
}

///|
fn projection_replies(
  page : SlackMessagePage,
  rows : String,
) -> SlackMessageReplies {
  let replies = prepare_slack_message_replies(page, 0, replies_limits()).unwrap()
  let request = begin_slack_message_replies(replies).unwrap()
  let received = reply_page(replies, request, rows, ",\"has_more\":false").unwrap()
  assert_true(
    next_slack_message_replies_request(replies, received).unwrap() is None,
  )
  replies
}

///|
fn projection_parent(extra : String) -> String {
  "{\"type\":\"message\",\"ts\":\"1.000001\",\"text\":\"parent\",\"reply_count\":2" +
  extra +
  "}"
}

///|
test "Slack coalescence retains first original checked row and appends new original reply keys" {
  let (history, page) = projection_history("[" + projection_parent("") + "]")
  let replies = projection_replies(
    page,
    "[" +
    projection_parent(",\"user\":\"U1\"") +
    ",{\"type\":\"message\",\"ts\":\"2.000001\",\"thread_ts\":\"1.000001\",\"text\":\"child\"}]",
  )
  close_slack_message_history(history)
  close_slack_message_replies(replies)
  let result = coalesce_slack_message_originals(
    history,
    [replies],
    projection_limits(),
  ).unwrap()
  assert_eq(slack_message_projection_row_count(result), 2)
  assert_true(physical_equal(result.rows[0], page.rows[0]))
  assert_true(result.rows[0][3].value is @admitted.Null)
  assert_true(physical_equal(result.rows[1], replies.pages[0].original.rows[1]))
  assert_eq(
    slack_message_projection_rows_wire(result, ["id", "user"], 2048, 64, 8).unwrap(),
    "[{\"id\":\"C1:1.000001\",\"user\":null},{\"id\":\"C1:2.000001\",\"user\":null}]",
  )
}

///|
test "Slack coalescence rejects explicit null and changed established values" {
  for
    (before, after) in [
      (",\"user\":null", ",\"user\":\"U1\""),
      (",\"user\":\"U1\"", ",\"user\":null"),
      (",\"user\":\"U1\"", ",\"user\":\"U2\""),
    ] {
    let (history, page) = projection_history(
      "[" + projection_parent(before) + "]",
    )
    let replies = projection_replies(page, "[" + projection_parent(after) + "]")
    assert_true(
      coalesce_slack_message_originals(history, [replies], projection_limits())
      is Err(InconsistentThread),
    )
  }
}

///|
test "Slack coalescence retains later established facts even if the first original omitted them" {
  let (history, page) = projection_history("[" + projection_parent("") + "]")
  let first = projection_replies(
    page,
    "[" + projection_parent(",\"user\":\"U1\"") + "]",
  )
  let second = projection_replies(
    page,
    "[" + projection_parent(",\"user\":\"U2\"") + "]",
  )
  assert_true(
    coalesce_slack_message_originals(
      history,
      [first, second],
      projection_limits(),
    )
    is Err(InconsistentThread),
  )
  let missing = projection_replies(page, "[" + projection_parent("") + "]")
  let result = coalesce_slack_message_originals(
    history,
    [first, missing],
    projection_limits(),
  ).unwrap()
  assert_true(physical_equal(result.rows[0], page.rows[0]))
}

///|
test "Slack coalescence tracks nested reaction users absence independently from null" {
  let absent = ",\"reactions\":[{\"name\":\"eyes\",\"count\":1}]"
  let supplied = ",\"reactions\":[{\"name\":\"eyes\",\"count\":1,\"users\":[\"U1\"]}]"
  let (history, page) = projection_history(
    "[" + projection_parent(absent) + "]",
  )
  let replies = projection_replies(
    page,
    "[" + projection_parent(supplied) + "]",
  )
  let result = coalesce_slack_message_originals(
    history,
    [replies],
    projection_limits(),
  ).unwrap()
  assert_true(physical_equal(result.rows[0], page.rows[0]))
  assert_eq(
    slack_message_projection_rows_wire(result, ["reactions"], 2048, 64, 8).unwrap(),
    "[{\"reactions\":[{\"count\":\"1\",\"name\":\"eyes\",\"users\":null}]}]",
  )
  let (history, page) = projection_history(
    "[" +
    projection_parent(
      ",\"reactions\":[{\"name\":\"eyes\",\"count\":1,\"users\":null}]",
    ) +
    "]",
  )
  let replies = projection_replies(
    page,
    "[" + projection_parent(supplied) + "]",
  )
  assert_true(
    coalesce_slack_message_originals(history, [replies], projection_limits())
    is Err(InconsistentThread),
  )
}

///|
test "Slack coalescence rejects incompatible reaction structure and later observed nested facts" {
  let absent = ",\"reactions\":[{\"name\":\"eyes\",\"count\":1}]"
  for
    later in [
      ",\"reactions\":null", ",\"reactions\":[]", ",\"reactions\":[{\"name\":\"eyes\",\"count\":2}]",
      ",\"reactions\":[{\"name\":\"heart\",\"count\":1}]",
    ] {
    let (history, page) = projection_history(
      "[" + projection_parent(absent) + "]",
    )
    let replies = projection_replies(page, "[" + projection_parent(later) + "]")
    assert_true(
      coalesce_slack_message_originals(history, [replies], projection_limits())
      is Err(InconsistentThread),
    )
  }
  let (history, page) = projection_history(
    "[" + projection_parent(absent) + "]",
  )
  let first = projection_replies(
    page,
    "[" +
    projection_parent(
      ",\"reactions\":[{\"name\":\"eyes\",\"count\":1,\"users\":[\"U1\"]}]",
    ) +
    "]",
  )
  let second = projection_replies(
    page,
    "[" +
    projection_parent(
      ",\"reactions\":[{\"name\":\"eyes\",\"count\":1,\"users\":[\"U2\"]}]",
    ) +
    "]",
  )
  assert_true(
    coalesce_slack_message_originals(
      history,
      [first, second],
      projection_limits(),
    )
    is Err(InconsistentThread),
  )
}

///|
test "Slack coalescence preserves derived zero but refuses an actual distinct child" {
  let parent = "{\"type\":\"message\",\"ts\":\"1.000001\",\"text\":\"parent\"}"
  let (history, page) = projection_history("[" + parent + "]")
  let alone = projection_replies(page, "[" + parent + "]")
  let result = coalesce_slack_message_originals(
    history,
    [alone],
    projection_limits(),
  ).unwrap()
  assert_true(result.rows[0][6].value is @admitted.Signed64(0L))
  let children = projection_replies(
    page,
    "[" +
    parent +
    ",{\"type\":\"message\",\"ts\":\"2.000001\",\"thread_ts\":\"1.000001\"}]",
  )
  assert_true(
    coalesce_slack_message_originals(history, [children], projection_limits())
    is Err(InconsistentThread),
  )
}

///|
test "Slack coalescence requires original successful completions and refuses equal foreign selection" {
  let history = message_history()
  assert_true(
    coalesce_slack_message_originals(history, [], projection_limits())
    is Err(HistoryUnavailable),
  )
  let request = begin_slack_message_history(history).unwrap()
  let page = history_admit(
    history,
    request,
    "[" + projection_parent("") + "]",
    ",\"has_more\":false",
  ).unwrap()
  assert_true(
    coalesce_slack_message_originals(history, [], projection_limits())
    is Err(HistoryUnavailable),
  )
  close_slack_message_history(history)
  assert_true(
    coalesce_slack_message_originals(history, [], projection_limits())
    is Err(HistoryUnavailable),
  )
  let (history, page) = projection_history("[" + projection_parent("") + "]")
  let pending = prepare_slack_message_replies(page, 0, replies_limits()).unwrap()
  assert_true(
    coalesce_slack_message_originals(history, [pending], projection_limits())
    is Err(ForeignRepliesRequest),
  )
  let (_, equal_page) = projection_history("[" + projection_parent("") + "]")
  let foreign = projection_replies(
    equal_page,
    "[" + projection_parent("") + "]",
  )
  assert_true(
    coalesce_slack_message_originals(history, [foreign], projection_limits())
    is Err(ForeignRepliesRequest),
  )
  // A generic matching page never obtains an original history request.
  let generic = message_project(
    "{\"ok\":true,\"has_more\":false,\"messages\":[" +
    projection_parent("") +
    "]}",
  ).unwrap()
  assert_true(
    prepare_slack_message_replies(generic, 0, replies_limits())
    is Err(InvalidSelection(_)),
  )
}

///|
test "Slack coalescence bounds every occurrence and comparison without changing original protocols" {
  let (history, page) = projection_history("[" + projection_parent("") + "]")
  let replies = projection_replies(page, "[" + projection_parent("") + "]")
  for
    limits in [
      { ..projection_limits(), max_work: 1, },
      { ..projection_limits(), max_occurrences: 1, },
      {
        ..projection_limits(),
        comparison: { max_nodes: 1, max_depth: 1, max_text_bytes: 1, },
      },
    ] {
    assert_true(
      coalesce_slack_message_originals(history, [replies], limits)
      is Err(BudgetExceeded),
    )
  }
  let result = coalesce_slack_message_originals(
    history,
    [replies],
    projection_limits(),
  ).unwrap()
  assert_true(physical_equal(result.rows[0], page.rows[0]))
  assert_true(
    slack_message_projection_rows_wire(result, ["id"], 1, 1, 1)
    is Err(BudgetExceeded),
  )
}
