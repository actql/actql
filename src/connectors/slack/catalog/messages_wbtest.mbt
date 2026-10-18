///|
fn message_limits() -> SlackMessagePageLimits {
  {
    max_bytes: 16384,
    max_nodes: 512,
    max_depth: 16,
    max_rows: 16,
    max_cursor_bytes: 128,
    max_value_nodes: 1024,
    max_value_text_bytes: 16384,
  }
}

///|
fn message_project(
  text : String,
) -> Result[SlackMessagePage, SlackMessagePageIssue] {
  project_slack_message_page(@utf8.encode(text), "C1", message_limits())
}

///|
fn message_wire(page : SlackMessagePage, fields : Array[String]) -> String {
  slack_message_page_rows_wire(page, fields, 16384, 1024, 16).unwrap()
}

///|
test "Slack message projection preserves exact identity instant and recursive observed values" {
  let raw =
    #|{"ok":true,"has_more":true,"is_limited":false,"messages":[{"type":"message","channel":"C1","ts":"1.000001","user":"U1","text":"<@U1> é\n原文","thread_ts":"1.000000","reply_count":9007199254740993,"edited":{"user":"U2","ts":"1.000490"},"reactions":[{"name":"facepalm","count":9007199254740993,"users":["U1","U2"]}],"files":[{"id":"F1","name":"ignored description"},{"id":"F1"}]}],"response_metadata":{"next_cursor":"opaque+/= é"}}
  let page = message_project(raw).unwrap()
  assert_eq(page.response_sha256, @sha.hex(@utf8.encode(raw)))
  assert_eq(page.next_cursor, Some("opaque+/= é"))
  assert_true(page.has_more)
  assert_false(page.history_limited)
  assert_eq(slack_message_page_ids(page), ["C1:1.000001"])
  assert_eq(
    message_wire(page, slack_message_column_names()),
    (
      #|[{"id":"C1:1.000001","channel":"C1","ts":"1.000001","user":"U1","text":"<@U1> é\n原文","thread_ts":"1.000000","reply_count":"9007199254740993","reactions":[{"count":"9007199254740993","name":"facepalm","users":["U1","U2"]}],"edited":"1970-01-01T00:00:01.00049Z","files":["F1","F1"],"posted_at":"1970-01-01T00:00:01.000001Z"}]
    ),
  )
  assert_true(page.rows[0][6].value is @admitted.Signed64(9007199254740993L))
}

///|
test "Slack message decimal epochs retain nanoseconds and never rewrite raw ts" {
  for
    (raw, expected) in [
      ("0.000000", "1970-01-01T00:00:00.000Z"),
      ("0.000001", "1970-01-01T00:00:00.000001Z"),
      ("0.999999999", "1970-01-01T00:00:00.999999999Z"),
      ("-0.000001", "1969-12-31T23:59:59.999999Z"),
      ("-1.999999999", "1969-12-31T23:59:58.000000001Z"),
      ("253402300799.999999999", "9999-12-31T23:59:59.999999999Z"),
      ("-62167219200.000", "0000-01-01T00:00:00.000Z"),
    ] {
    let page = message_project(
      "{\"ok\":true,\"has_more\":false,\"messages\":[{\"type\":\"message\",\"ts\":\"" +
      raw +
      "\"}]}",
    ).unwrap()
    assert_eq(
      message_wire(page, ["ts", "posted_at"]),
      "[{\"ts\":\"" + raw + "\",\"posted_at\":\"" + expected + "\"}]",
    )
  }
  for
    raw in [
      "", "1", "1.", ".1", "+1.000", "01.000", "1e3", "1.0000000001", "253402300800.000",
      "-62167219200.000000001", "9223372036854775808.000", "1.000Z", "1.000\n",
    ] {
    assert_true(message_epoch_timestamp(raw) is None, msg=raw)
  }
}

///|
test "Slack missing observations remain null rather than guessed empty arrays or edits" {
  let page = message_project(
    "{\"ok\":true,\"has_more\":false,\"messages\":[{\"type\":\"message\",\"ts\":\"1.000000\"}]}",
  ).unwrap()
  assert_eq(
    message_wire(page, [
      "user", "text", "thread_ts", "reply_count", "reactions", "edited", "files",
    ]),
    "[{\"user\":null,\"text\":null,\"thread_ts\":null,\"reply_count\":null,\"reactions\":null,\"edited\":null,\"files\":null}]",
  )
  assert_eq(slack_message_page_row_count(page), 1)
}

///|
test "Slack optional collections preserve empty observed arrays and incomplete reaction users" {
  let page = message_project(
    (
      #|{"ok":true,"has_more":false,"messages":[{"type":"message","ts":"1.000000","reactions":[{"name":"x","count":1034,"users":["U1"]}],"files":[]}]}
    ),
  ).unwrap()
  assert_eq(
    message_wire(page, ["reactions", "files"]),
    (
      #|[{"reactions":[{"count":"1034","name":"x","users":["U1"]}],"files":[]}]
    ),
  )
  let empty = message_project(
    (
      #|{"ok":true,"has_more":false,"messages":[{"type":"message","ts":"1.000000","reactions":[],"files":[]}]}
    ),
  ).unwrap()
  assert_eq(
    message_wire(empty, ["reactions", "files"]),
    "[{\"reactions\":[],\"files\":[]}]",
  )
}

///|
test "Slack page rejects malformed known cells even if projection would omit them" {
  for
    extra in [
      "\"reply_count\":1.00000000000001", "\"reply_count\":-1", "\"reply_count\":9223372036854775808",
      "\"reply_count\":\"1\"", "\"edited\":\"1.000000\"", "\"edited\":{}", "\"edited\":{\"ts\":\"bad\"}",
      "\"files\":[\"F1\"]", "\"files\":[{}]", "\"files\":[{\"id\":\"\"}]", "\"reactions\":[{}]",
      "\"reactions\":[{\"name\":\"x\",\"count\":-1}]", "\"reactions\":[{\"name\":\"x\",\"count\":1,\"users\":[1]}]",
      "\"user\":1", "\"text\":[]", "\"thread_ts\":false", "\"channel\":\"C2\"", "\"hidden\":true",
      "\"subtype\":\"message_deleted\"", "\"subtype\":\"message_changed\"", "\"subtype\":42",
    ] {
    assert_true(
      message_project(
        "{\"ok\":true,\"has_more\":false,\"messages\":[{\"type\":\"message\",\"ts\":\"1.000000\"," +
        extra +
        "}]}",
      )
      is Err(_),
      msg=extra,
    )
  }
  for
    body in [
      "{\"ok\":false,\"has_more\":false,\"messages\":[]}", "{\"ok\":true,\"error\":\"failure\",\"has_more\":false,\"messages\":[]}",
      "{\"ok\":true,\"has_more\":false,\"messages\":[{\"type\":\"unknown\",\"ts\":\"1.000\"}]}",
      "{\"ok\":true,\"has_more\":false,\"messages\":[{\"ts\":\"1.000\"}]}", "{\"ok\":true,\"has_more\":false,\"messages\":[{\"type\":\"message\",\"ts\":null}]}",
    ] {
    assert_true(message_project(body) is Err(_), msg=body)
  }
}

///|
test "Slack history page preserves retention and both pagination signals" {
  let limited = message_project(
    "{\"ok\":true,\"has_more\":false,\"is_limited\":true,\"messages\":[]}",
  ).unwrap()
  assert_true(limited.history_limited)
  assert_false(limited.has_more)
  let time = message_project(
    "{\"ok\":true,\"has_more\":true,\"messages\":[{\"type\":\"message\",\"ts\":\"1.000000\"}]}",
  ).unwrap()
  assert_true(time.has_more)
  assert_eq(time.next_cursor, None)
  for cursor in ["", "opaque"] {
    let raw = "{\"ok\":true,\"has_more\":false,\"messages\":[],\"response_metadata\":{\"next_cursor\":\"" +
      cursor +
      "\"}}"
    let page = message_project(raw).unwrap()
    assert_eq(
      page.next_cursor,
      if cursor.is_empty() {
        None
      } else {
        Some(cursor)
      },
    )
  }
  for
    body in [
      "{\"ok\":true,\"messages\":[]}", "{\"ok\":true,\"has_more\":null,\"messages\":[]}",
      "{\"ok\":true,\"has_more\":true,\"messages\":[]}", "{\"ok\":true,\"has_more\":false,\"is_limited\":null,\"messages\":[]}",
      "{\"ok\":true,\"has_more\":false,\"messages\":[],\"response_metadata\":[]}",
      "{\"ok\":true,\"has_more\":false,\"messages\":[],\"response_metadata\":{\"next_cursor\":1}}",
    ] {
    assert_true(message_project(body) is Err(_), msg=body)
  }
}

///|
test "Slack message ids preserve raw ts distinctions and refuse duplicate records" {
  let page = message_project(
    "{\"ok\":true,\"has_more\":false,\"messages\":[{\"type\":\"message\",\"ts\":\"1.000000\"},{\"type\":\"message\",\"ts\":\"1.000\"}]}",
  ).unwrap()
  assert_eq(slack_message_page_ids(page), ["C1:1.000000", "C1:1.000"])
  assert_eq(
    message_wire(page, ["posted_at"]),
    "[{\"posted_at\":\"1970-01-01T00:00:01.000Z\"},{\"posted_at\":\"1970-01-01T00:00:01.000Z\"}]",
  )
  assert_true(
    message_project(
      "{\"ok\":true,\"has_more\":false,\"messages\":[{\"type\":\"message\",\"ts\":\"1.000000\"},{\"type\":\"message\",\"ts\":\"1.000000\"}]}",
    )
    is Err(DuplicateMessage),
  )
}

///|
test "Slack message admission and wire writing enforce exact independent byte and node budgets" {
  let raw = "{\"ok\":true,\"has_more\":false,\"messages\":[{\"type\":\"message\",\"ts\":\"1.000000\"}]}"
  let page = message_project(raw).unwrap()
  assert_true(
    slack_message_page_rows_wire(page, ["missing"], 4096, 128, 16)
    is Err(InvalidSelection("missing")),
  )
  assert_true(
    slack_message_page_rows_wire(page, ["id", "id"], 4096, 128, 16)
    is Err(InvalidSelection("id")),
  )
  let wire = message_wire(page, ["id"])
  let size = @utf8.encode(wire).length()
  assert_eq(slack_message_page_rows_wire(page, ["id"], size, 4, 3), Ok(wire))
  assert_true(
    slack_message_page_rows_wire(page, ["id"], size - 1, 4, 3)
    is Err(BudgetExceeded),
  )
  assert_true(
    slack_message_page_rows_wire(page, ["id"], size, 2, 3)
    is Err(BudgetExceeded),
  )
  let bytes = @utf8.encode(raw)
  assert_true(
    project_slack_message_page(bytes, "C1", {
      ..message_limits(),
      max_bytes: bytes.length() - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_slack_message_page(bytes, "C1", {
      ..message_limits(),
      max_value_nodes: 10,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_slack_message_page(bytes, "C1", {
      ..message_limits(),
      max_cursor_bytes: 0,
    })
    is Err(InvalidLimits),
  )
  assert_true(
    project_slack_message_page(bytes, "", message_limits())
    is Err(InvalidCell("channel")),
  )
}
