///|
fn channel_limits() -> SlackChannelListLimits {
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
fn channel_project(
  text : String,
) -> Result[SlackChannelListPage, SlackChannelListIssue] {
  project_slack_channel_list(@utf8.encode(text), channel_limits())
}

///|
test "Slack channels preserve original topic purpose booleans and exact int64 wire" {
  let raw =
    #|{"ok":true,"channels":[{"id":"C1","name":"観測 é","topic":{"value":""},"purpose":{"value":"original"},"num_members":9007199254740993,"is_private":false,"is_archived":true,"created":0}],"response_metadata":{"next_cursor":"opaque+/= é"}}
  let page = channel_project(raw).unwrap()
  assert_eq(page.response_sha256, @sha.hex(@utf8.encode(raw)))
  assert_eq(page.next_cursor, Some("opaque+/= é"))
  assert_eq(slack_channel_list_ids(page), ["C1"])
  assert_eq(
    slack_channel_list_rows_wire(
      page,
      slack_channel_list_column_names(),
      8192,
      100,
      8,
    ).unwrap(),
    (
      #|[{"id":"C1","name":"観測 é","topic":"","purpose":"original","member_count":"9007199254740993","is_private":false,"is_archived":true,"created":"1970-01-01T00:00:00.000Z"}]
    ),
  )
  assert_true(page.rows[0][4].value is @admitted.Signed64(9007199254740993L))
  assert_true(
    physical_equal(page.rows[0][4].contract, page.rows[0][4].contract),
  )
}

///|
test "Slack channel integer tokens never round into a count or an instant" {
  for
    (raw, expected) in [
      ("0", "0"),
      ("9007199254740992", "9007199254740992"),
      ("9223372036854775807", "9223372036854775807"),
      ("2e1", "20"),
      ("2.000", "2"),
    ] {
    let page = channel_project(
      "{\"ok\":true,\"channels\":[{\"id\":\"C\",\"num_members\":" + raw + "}]}",
    ).unwrap()
    assert_eq(
      slack_channel_list_rows_wire(page, ["member_count"], 100, 10, 4).unwrap(),
      "[{\"member_count\":\"" + expected + "\"}]",
    )
  }
  for field in ["num_members", "created"] {
    for
      token in [
        "-1", "9223372036854775808", "1.00000000000000001", "1e-50", "true", "\"2\"",
        "-0",
      ] {
      assert_true(
        channel_project(
          "{\"ok\":true,\"channels\":[{\"id\":\"C\",\"" +
          field +
          "\":" +
          token +
          "}]}",
        )
        is Err(_),
        msg=field + token,
      )
    }
  }
  for token in ["9223372036854775", "253402300800"] {
    assert_true(
      channel_project(
        "{\"ok\":true,\"channels\":[{\"id\":\"C\",\"created\":" + token + "}]}",
      )
      is Err(InvalidCell("created")),
    )
  }
}

///|
test "Slack channel missing observations remain nullable and terminal cursors stay distinct" {
  for
    suffix in [
      "", ",\"response_metadata\":{}", ",\"response_metadata\":{\"next_cursor\":\"\"}",
      ",\"response_metadata\":{\"next_cursor\":null}",
    ] {
    let page = channel_project(
      "{\"ok\":true,\"channels\":[{\"id\":\"C1\"}]" + suffix + "}",
    ).unwrap()
    assert_eq(page.next_cursor, None)
    assert_eq(
      slack_channel_list_rows_wire(
        page,
        slack_channel_list_column_names(),
        1024,
        100,
        8,
      ).unwrap(),
      (
        #|[{"id":"C1","name":null,"topic":null,"purpose":null,"member_count":null,"is_private":null,"is_archived":null,"created":null}]
      ),
    )
  }
}

///|
test "Slack channel whole page refuses malformed unselected fields and duplicate identity" {
  for
    channel in [
      "{}", "{\"id\":\"\"}", "{\"id\":2}", "{\"id\":\"C\",\"topic\":true}", "{\"id\":\"C\",\"purpose\":{\"value\":3}}",
      "{\"id\":\"C\",\"is_archived\":\"false\"}", "{\"id\":\"C\",\"is_private\":0}",
      "{\"id\":\"C\",\"name\":[]}",
    ] {
    assert_true(
      channel_project("{\"ok\":true,\"channels\":[" + channel + "]}") is Err(_),
    )
  }
  assert_true(
    channel_project(
      "{\"ok\":true,\"channels\":[{\"id\":\"C\"},{\"id\":\"C\"}]}",
    )
    is Err(DuplicateChannel),
  )
  for
    raw in [
      "{}", "{\"ok\":false,\"channels\":[]}", "{\"ok\":true,\"channels\":[],\"error\":\"rate_limited\"}",
      "{\"ok\":true,\"channels\":[],\"response_metadata\":null}", "{\"ok\":true,\"channels\":[],\"response_metadata\":{\"next_cursor\":2}}",
      "{\"ok\":true,\"channels\":null}", "{\"ok\":true,\"channels\":[],\"channels\":[]}",
    ] {
    assert_true(channel_project(raw) is Err(_))
  }
  for flag in ["is_im", "is_mpim"] {
    for value in ["true", "null", "0", "\"false\""] {
      match
        channel_project(
          "{\"ok\":true,\"channels\":[{\"id\":\"D1\",\"" +
          flag +
          "\":" +
          value +
          "}]}",
        ) {
        Err(issue) => assert_eq(issue, InvalidCell(flag))
        Ok(_) => fail("Foreign conversation kind must refuse: " + flag)
      }
    }
  }
}

///|
test "Slack channel exact cumulative cell and response budgets are not per row allowances" {
  let raw = @utf8.encode(
    "{\"ok\":true,\"channels\":[{\"id\":\"C1\"},{\"id\":\"C2\"}]}",
  )
  let bound = {
    ..channel_limits(),
    max_bytes: raw.length(),
    max_value_nodes: 16,
    max_value_text_bytes: 4,
  }
  assert_true(project_slack_channel_list(raw, bound) is Ok(_))
  for
    limited in [
      { ..bound, max_bytes: raw.length() - 1, },
      { ..bound, max_value_nodes: 15, },
      { ..bound, max_value_text_bytes: 3, },
      { ..bound, max_nodes: 1, },
      { ..bound, max_rows: 1, },
      { ..bound, max_depth: 1, },
    ] {
    assert_true(project_slack_channel_list(raw, limited) is Err(BudgetExceeded))
  }
  let page = project_slack_channel_list(raw, bound).unwrap()
  assert_eq(
    slack_channel_list_rows_wire(page, ["id", "id"], 100, 10, 4),
    Err(InvalidSelection("id")),
  )
  assert_eq(
    slack_channel_list_rows_wire(page, ["unknown"], 100, 10, 4),
    Err(InvalidSelection("unknown")),
  )
  assert_eq(
    slack_channel_list_rows_wire(page, ["id"], 1, 10, 4),
    Err(BudgetExceeded),
  )
}

///|
test "Slack channel checked schema separates count int64 from created timestamp and permission" {
  let schema = slack_channel_list_schema_wire(8192, 1000, 16).unwrap()
  assert_true(
    schema.contains("\"member_count\":{\"nullable\":true,\"type\":\"int64\"}"),
  )
  assert_true(
    schema.contains("\"created\":{\"nullable\":true,\"type\":\"timestamp\"}"),
  )
  assert_eq(
    slack_channel_list_facts_wire(),
    "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}",
  )
}
