///|
test "Slack window bridge preserves exact request bounds and legacy absence" {
  let history = slack_prepare_message_history_window(
    "C1",
    Some("1.000000001"),
    Some("3.000000000"),
    8192,
    512,
    16,
    10,
    128,
    100,
    4096,
    4,
  ).unwrap()
  let request = slack_begin_message_history(history).unwrap()
  let wire = slack_message_history_request_json(request)
  assert_true(wire.contains("\"oldest\":\"1.000000001\""))
  assert_true(wire.contains("\"latest\":\"3.000000000\""))
  assert_true(slack_message_history_request_matches(history, request))
  let legacy = slack_prepare_message_history(
    "C1", 8192, 512, 16, 10, 128, 100, 4096, 4,
  ).unwrap()
  let legacy_wire = slack_message_history_request_json(
    slack_begin_message_history(legacy).unwrap(),
  )
  assert_false(legacy_wire.contains("\"oldest\""))
  assert_true(legacy_wire.contains("\"latest\":null"))
  slack_close_message_history(history)
  slack_close_message_history(legacy)
}

///|
test "Slack window bridge refuses equal exact instants without rounding" {
  assert_true(
    slack_prepare_message_history_window(
      "C1",
      Some("1.000001"),
      Some("1.000001000"),
      8192,
      512,
      16,
      10,
      128,
      100,
      4096,
      4,
    )
    is Err(_),
  )
}
