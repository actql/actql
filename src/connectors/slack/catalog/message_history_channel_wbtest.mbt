///|
fn history_channel_page(raw : String) -> SlackChannelListPage {
  project_slack_channel_list(@utf8.encode(raw), {
    max_bytes: 8192,
    max_nodes: 512,
    max_depth: 16,
    max_rows: 10,
    max_cursor_bytes: 64,
    max_value_nodes: 100,
    max_value_text_bytes: 4096,
  }).unwrap()
}

///|
fn history_channel_limits() -> SlackMessagePageLimits {
  {
    max_bytes: 8192,
    max_nodes: 512,
    max_depth: 16,
    max_rows: 10,
    max_cursor_bytes: 64,
    max_value_nodes: 100,
    max_value_text_bytes: 4096,
  }
}

///|
test "Slack channel history retains the exact admitted channel page and row" {
  let raw = "{\"ok\":true,\"channels\":[{\"id\":\"C1\"},{\"id\":\"C2\"}]}"
  let page = history_channel_page(raw)
  let equal_page = history_channel_page(raw)
  let history = prepare_slack_message_history_from_channel(
    page,
    1,
    history_channel_limits(),
    4,
  ).unwrap()
  assert_true(slack_message_history_matches_channel(history, page, 1))
  assert_false(slack_message_history_matches_channel(history, page, 0))
  assert_false(slack_message_history_matches_channel(history, equal_page, 1))
  let request = begin_slack_message_history(history).unwrap()
  assert_eq(slack_message_history_request_channel(request), "C2")
  assert_eq(slack_message_history_request_oldest(request), None)
  assert_eq(slack_message_history_request_latest(request), None)
  assert_true(slack_message_history_request_matches(history, request))
}

///|
test "Slack channel history refuses invalid indices and preserves independent history bounds" {
  let page = history_channel_page(
    "{\"ok\":true,\"channels\":[{\"id\":\"C1\"}]}",
  )
  for index in [-1, 1, 2147483647] {
    assert_true(
      prepare_slack_message_history_from_channel(
        page,
        index,
        history_channel_limits(),
        4,
      )
      is Err(InvalidSelection(_)),
    )
  }
  assert_true(
    prepare_slack_message_history_from_channel(
      page,
      0,
      { ..history_channel_limits(), max_value_text_bytes: 1, },
      4,
    )
    is Err(InvalidCell("channel")),
  )
  assert_true(
    prepare_slack_message_history_from_channel(
      page,
      0,
      history_channel_limits(),
      0,
    )
    is Err(InvalidLimits),
  )
  let direct = prepare_slack_message_history("C1", history_channel_limits(), 4).unwrap()
  assert_false(slack_message_history_matches_channel(direct, page, 0))
}
