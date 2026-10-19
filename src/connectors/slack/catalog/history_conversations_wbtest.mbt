///|
fn conversation_limits() -> SlackChannelListLimits {
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
test "Slack history conversations admit original IM and MPIM fields without invented channel metadata" {
  let raw =
    #|{"ok":true,"channels":[{"id":"D-original","is_im":true,"is_mpim":false},{"id":"G-original","is_im":false,"is_mpim":true,"name":"group","num_members":9007199254740993}],"response_metadata":{"next_cursor":"next+/="}}
  let page = project_slack_history_conversation_list(
    @utf8.encode(raw),
    conversation_limits(),
  ).unwrap()
  assert_eq(page.response_sha256, @sha.hex(@utf8.encode(raw)))
  assert_eq(page.next_cursor, Some("next+/="))
  assert_eq(slack_channel_list_ids(page), ["D-original", "G-original"])
  assert_eq(
    slack_channel_list_rows_wire(
      page,
      ["id", "name", "member_count"],
      4096,
      100,
      8,
    ).unwrap(),
    (
      #|[{"id":"D-original","name":null,"member_count":null},{"id":"G-original","name":"group","member_count":"9007199254740993"}]
    ),
  )
  assert_true(
    project_slack_channel_list(@utf8.encode(raw), conversation_limits())
    is Err(InvalidCell("is_im")),
  )
}

///|
test "Slack history conversations reject malformed discriminants and unselected known fields" {
  for flag in ["is_im", "is_mpim"] {
    for value in ["null", "0", "\"false\"", "[]", "{}"] {
      let raw = "{\"ok\":true,\"channels\":[{\"id\":\"D\",\"" +
        flag +
        "\":" +
        value +
        "}]}"
      match
        project_slack_history_conversation_list(
          @utf8.encode(raw),
          conversation_limits(),
        ) {
        Err(issue) => assert_eq(issue, InvalidCell(flag))
        Ok(_) => fail("Malformed conversation discriminant: " + flag)
      }
    }
  }
  for
    cell in [
      "\"name\":[]", "\"num_members\":9223372036854775808", "\"is_private\":0", "\"topic\":[]",
    ] {
    let raw = "{\"ok\":true,\"channels\":[{\"id\":\"D\",\"is_im\":true," +
      cell +
      "}]}"
    assert_true(
      project_slack_history_conversation_list(
        @utf8.encode(raw),
        conversation_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "Slack history conversation budgets duplicate ids and ordinary channel bytes stay exact" {
  let bytes = @utf8.encode(
    (
      #|{"ok":true,"channels":[{"id":"C-original","is_im":false,"is_mpim":false,"created":0}]}
    ),
  )
  let ordinary = project_slack_channel_list(bytes, conversation_limits()).unwrap()
  let history = project_slack_history_conversation_list(
    bytes,
    conversation_limits(),
  ).unwrap()
  assert_eq(ordinary.response_sha256, history.response_sha256)
  assert_eq(
    slack_channel_list_rows_wire(
      ordinary,
      slack_channel_list_column_names(),
      4096,
      100,
      8,
    ).unwrap(),
    slack_channel_list_rows_wire(
      history,
      slack_channel_list_column_names(),
      4096,
      100,
      8,
    ).unwrap(),
  )
  assert_true(
    project_slack_history_conversation_list(bytes, {
      ..conversation_limits(),
      max_bytes: bytes.length() - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_slack_history_conversation_list(bytes, {
      ..conversation_limits(),
      max_value_nodes: 7,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_slack_history_conversation_list(
      @utf8.encode(
        (
          #|{"ok":true,"channels":[{"id":"D","is_im":true},{"id":"D","is_im":true}]}
        ),
      ),
      conversation_limits(),
    )
    is Err(DuplicateChannel),
  )
}

///|
test "Slack history conversation is an exact original history selection not a copied identity" {
  let bytes = @utf8.encode(
    (
      #|{"ok":true,"channels":[{"id":"D-original","is_im":true}]}
    ),
  )
  let page = project_slack_history_conversation_list(
    bytes,
    conversation_limits(),
  ).unwrap()
  let copy = project_slack_history_conversation_list(
    bytes,
    conversation_limits(),
  ).unwrap()
  let history = prepare_slack_message_history_from_channel(
    page,
    0,
    {
      max_bytes: 8192,
      max_nodes: 512,
      max_depth: 16,
      max_rows: 10,
      max_cursor_bytes: 64,
      max_value_nodes: 100,
      max_value_text_bytes: 4096,
    },
    4,
  ).unwrap()
  assert_true(slack_message_history_matches_channel(history, page, 0))
  assert_false(slack_message_history_matches_channel(history, copy, 0))
  let request = begin_slack_message_history(history).unwrap()
  assert_eq(slack_message_history_request_channel(request), "D-original")
}
