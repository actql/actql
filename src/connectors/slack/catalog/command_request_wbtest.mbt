///|
fn command_limits() -> SlackCommandRequestLimits {
  {
    max_bytes: 262144,
    max_nodes: 64,
    max_depth: 8,
    max_value_text_bytes: 200000,
  }
}

///|
fn command_input(fields : Array[(String, String)]) -> @admitted.CheckedValue {
  let declarations = fields.map(pair => {
    let (name, _) = pair
    (name, @contract.primitive(@contract.StringType, nullable=false))
  })
  let contract = @contract.object_contract(
    declarations,
    nullable=false,
    max_fields=8,
    max_name_bytes=1024,
  ).unwrap()
  let value = @admitted.object_value(
    fields.map(pair => {
      let (name, text) = pair
      (name, @admitted.text_value(text, 200000).unwrap())
    }),
  ).unwrap()
  @admitted.recheck_runtime_value(value, contract, {
    max_nodes: 64,
    max_depth: 8,
    max_text_bytes: 200000,
  }).unwrap()
}

///|
test "Slack post request retains checked mrkdwn Unicode and explicit original item marker" {
  let input = command_input([("text", "<@U1> é 😀\n\"original\"")])
  let request = prepare_slack_command_request(
    Post,
    input,
    "C1",
    Some("item:original"),
    command_limits(),
  ).unwrap()
  assert_eq(slack_command_request_path(request), "/api/chat.postMessage")
  assert_eq(slack_command_request_kind(request), Post)
  assert_eq(slack_command_request_channel(request), "C1")
  assert_eq(slack_command_request_marker(request), Some("item:original"))
  assert_true(slack_command_request_input_matches(request, input))
  assert_eq(
    slack_command_request_body(request),
    (
      #|{"channel":"C1","metadata":{"event_payload":{"effect_item_id":"item:original"},"event_type":"actql_effect"},"text":"<@U1> é 😀\n\"original\""}
    ),
  )
}

///|
test "Slack reply and reaction retain exact timestamp String rather than binary64 or Timestamp" {
  let ts = "1512085950.218404"
  let reply = prepare_slack_command_request(
    Reply,
    command_input([("text", "reply"), ("thread_ts", ts)]),
    "G1",
    Some("item:reply"),
    command_limits(),
  ).unwrap()
  assert_eq(
    slack_command_request_body(reply),
    (
      #|{"channel":"G1","metadata":{"event_payload":{"effect_item_id":"item:reply"},"event_type":"actql_effect"},"text":"reply","thread_ts":"1512085950.218404"}
    ),
  )
  let reaction = prepare_slack_command_request(
    React,
    command_input([("name", "thumbsup::skin-tone-6"), ("ts", ts)]),
    "C1",
    None,
    command_limits(),
  ).unwrap()
  assert_eq(slack_command_request_path(reaction), "/api/reactions.add")
  assert_eq(slack_command_request_marker(reaction), None)
  assert_eq(
    slack_command_request_body(reaction),
    "{\"channel\":\"C1\",\"name\":\"thumbsup::skin-tone-6\",\"ts\":\"1512085950.218404\"}",
  )
}

///|
test "Slack archive input is the original empty object and unmarked operations reject a marker" {
  let input = command_input([])
  let archive = prepare_slack_command_request(
    ArchiveChannel,
    input,
    "C1",
    None,
    command_limits(),
  ).unwrap()
  assert_eq(slack_command_request_path(archive), "/api/conversations.archive")
  assert_eq(slack_command_request_body(archive), "{\"channel\":\"C1\"}")
  assert_true(
    prepare_slack_command_request(
      ArchiveChannel,
      input,
      "C1",
      Some("not-reconciliation-evidence"),
      command_limits(),
    )
    is Err(InvalidMarker),
  )
  assert_true(
    prepare_slack_command_request(
      Post,
      command_input([("text", "x")]),
      "C1",
      None,
      command_limits(),
    )
    is Err(InvalidMarker),
  )
}

///|
test "Slack request retains nominal checked input and equal recheck is not its original" {
  let input = command_input([("text", "same")])
  let copy = @admitted.recheck_runtime_value(input.value, input.contract, {
    max_nodes: 64,
    max_depth: 8,
    max_text_bytes: 200000,
  }).unwrap()
  let request = prepare_slack_command_request(
    Post,
    input,
    "C1",
    Some("item:1"),
    command_limits(),
  ).unwrap()
  assert_false(slack_command_request_input_matches(request, copy))
  assert_false(
    slack_command_request_input_matches(
      request,
      command_input([("text", "same")]),
    ),
  )
  assert_true(slack_command_request_input_matches(request, input))
}

///|
test "Slack request checks the complete closed input and exact text types" {
  for
    input in [
      command_input([]),
      command_input([("text", "x"), ("unknown", "ignored")]),
      command_input([("thread_ts", "1512085950.218404")]),
    ] {
    assert_true(
      prepare_slack_command_request(
        Post,
        input,
        "C1",
        Some("item:1"),
        command_limits(),
      )
      is Err(_),
    )
  }
  let contract = @contract.object_contract(
    [("text", @contract.primitive(@contract.NumberType, nullable=false))],
    nullable=false,
    max_fields=1,
    max_name_bytes=32,
  ).unwrap()
  let wrong = @admitted.recheck_runtime_value(
    @admitted.object_value([("text", @admitted.number_value(1.0).unwrap())]).unwrap(),
    contract,
    { max_nodes: 8, max_depth: 2, max_text_bytes: 32, },
  ).unwrap()
  assert_true(
    prepare_slack_command_request(
      Post,
      wrong,
      "C1",
      Some("item:1"),
      command_limits(),
    )
    is Err(InvalidField("text")),
  )
  assert_true(
    prepare_slack_command_request(
      React,
      command_input([("name", ""), ("ts", "1512085950.218404")]),
      "C1",
      None,
      command_limits(),
    )
    is Err(InvalidField("name")),
  )
}

///|
test "Slack request preserves the original Text enum contract" {
  let text_contract = @contract.string_enum_contract(
    ["allowed", "allowed"],
    { max_nodes: 16, max_depth: 4, max_text_bytes: 128, },
    nullable=false,
  ).unwrap()
  let contract = @contract.object_contract(
    [("text", text_contract)],
    nullable=false,
    max_fields=1,
    max_name_bytes=32,
  ).unwrap()
  let input = @admitted.recheck_runtime_value(
    @admitted.object_value([
      ("text", @admitted.text_value("allowed", 32).unwrap()),
    ]).unwrap(),
    contract,
    { max_nodes: 16, max_depth: 4, max_text_bytes: 128, },
  ).unwrap()
  let request = prepare_slack_command_request(
    Post,
    input,
    "C1",
    Some("item:enum"),
    command_limits(),
  ).unwrap()
  assert_true(physical_equal(request.input.contract, contract))
  assert_true(slack_command_request_input_matches(request, input))
}

///|
test "Slack request refuses vendor truncation at forty thousand Unicode scalars" {
  let text = StringBuilder()
  for _ in 0..<40000 {
    text.write_string("😀")
  }
  let text = text.to_string()
  assert_true(
    prepare_slack_command_request(
      Post,
      command_input([("text", text)]),
      "C1",
      Some("item:large"),
      command_limits(),
    )
    is Ok(_),
  )
  assert_true(
    prepare_slack_command_request(
      Post,
      command_input([("text", text + "x")]),
      "C1",
      Some("item:large"),
      command_limits(),
    )
    is Err(TextWouldTruncate),
  )
}

///|
test "Slack request body and recheck bounds fail closed at their exact boundary" {
  let input = command_input([("text", "a\"b")])
  let request = prepare_slack_command_request(
    Post,
    input,
    "C1",
    Some("item:1"),
    command_limits(),
  ).unwrap()
  let size = @utf8.encode(slack_command_request_body(request)).length()
  assert_true(
    prepare_slack_command_request(Post, input, "C1", Some("item:1"), {
      ..command_limits(),
      max_bytes: size,
    })
    is Ok(_),
  )
  assert_true(
    prepare_slack_command_request(Post, input, "C1", Some("item:1"), {
      ..command_limits(),
      max_bytes: size - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_slack_command_request(Post, input, "C1", Some("item:1"), {
      ..command_limits(),
      max_nodes: 1,
    })
    is Err(BudgetExceeded),
  )
}
