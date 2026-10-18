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
