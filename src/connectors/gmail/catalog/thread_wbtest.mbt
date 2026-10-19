///|
fn thread_limits() -> GmailThreadLimits {
  {
    max_bytes: 16384,
    max_nodes: 2048,
    max_depth: 16,
    max_messages: 20,
    max_labels: 100,
    max_headers: 100,
    max_header_units: 1024,
    max_comment_depth: 8,
    max_value_nodes: 100,
    max_value_text_bytes: 8192,
  }
}

///|
fn thread_project(
  text : String,
) -> Result[GmailThreadProjection, GmailThreadIssue] {
  let page = thread_list_page("{\"threads\":[{\"id\":\"t/+\"}]}").unwrap()
  project_gmail_thread(@utf8.encode(text), page, 0, thread_limits())
}

///|
fn thread_values_wire(thread : GmailThreadProjection) -> String raise {
  let writer = @encode.writer(16384, 200, 16)
  @encode.begin_array(writer)
  for index in 0..<5 {
    @admitted.emit_checked_wire_value(
      gmail_thread_value_at(thread, index).unwrap(),
      writer,
    )
  }
  @encode.end_array(writer)
  @encode.finish(writer)
}

///|
test "Gmail full thread projects first subject exact count label union and maximum public date" {
  let original =
    #|{"id":"t/+","messages":[{"id":"m1","threadId":"t/+","internalDate":"0","labelIds":["INBOX","Label_1","INBOX"],"payload":{"headers":[{"name":"sUbJeCt","value":"Original é"},{"name":"Date","value":"1 Jan 2000 00:00 +0000"}]}},{"id":"m2","threadId":"t/+","internalDate":"9999999999999","labelIds":["Label_1","inbox"],"payload":{"headers":[{"name":"Subject","value":"Later subject"},{"name":"Date","value":"31 Dec 1999 23:59 +0000"}]}}]}
  let thread = thread_project(original).unwrap()
  assert_eq(thread.response_sha256, @sha.hex(@utf8.encode(original)))
  assert_eq(thread.target_index, 0)
  assert_eq(gmail_thread_list_id_at(thread.targets, 0), Some("t/+"))
  assert_eq(
    thread_values_wire(thread),
    (
      #|["t/+",["INBOX","Label_1","inbox"],"2000-01-01T00:00:00.000Z","2","Original é"]
    ),
  )
  assert_true(gmail_thread_value_at(thread, -1) is None)
  assert_true(gmail_thread_value_at(thread, 5) is None)
  assert_eq(
    gmail_thread_rows_wire(thread, ["subject", "message_count"], 1024, 20, 8).unwrap(),
    (
      #|[{"subject":"Original é","message_count":"2"}]
    ),
  )
  assert_true(
    gmail_thread_rows_wire(thread, ["id", "id"], 1024, 20, 8)
    is Err(InvalidSelection("id")),
  )
  assert_true(
    gmail_thread_rows_wire(thread, ["foreign"], 1024, 20, 8)
    is Err(InvalidSelection("foreign")),
  )
}

///|
test "Gmail complete empty thread is nullable but absent partial or null messages is not empty" {
  assert_eq(
    gmail_thread_schema_wire(4096, 100, 8).unwrap(),
    (
      #|{"id":{"nullable":false,"type":"string"},"labels":{"items":{"nullable":false,"type":"string"},"nullable":false,"type":"array"},"last_message_date":{"nullable":true,"type":"timestamp"},"message_count":{"nullable":false,"type":"int64"},"subject":{"nullable":true,"type":"string"}}
    ),
  )
  assert_eq(
    thread_values_wire(
      thread_project("{\"id\":\"t/+\",\"messages\":[]}").unwrap(),
    ),
    (
      #|["t/+",[],null,"0",null]
    ),
  )
  for
    body in [
      "{\"id\":\"t/+\"}", "{\"id\":\"t/+\",\"messages\":null}", "{\"id\":\"t/+\",\"messages\":[{}]}",
    ] {
    assert_true(thread_project(body) is Err(_))
  }
}

///|
test "Gmail absent and empty first subject remain distinct and duplicate selected headers refuse" {
  let start = "{\"id\":\"t/+\",\"messages\":[{\"id\":\"m\",\"threadId\":\"t/+\",\"internalDate\":\"1\",\"labelIds\":[],\"payload\":{\"headers\":"
  let end = "}}]}"
  assert_eq(
    thread_values_wire(thread_project(start + "[]" + end).unwrap()),
    (
      #|["t/+",[],"1970-01-01T00:00:00.001Z","1",null]
    ),
  )
  assert_eq(
    thread_values_wire(
      thread_project(start + "[{\"name\":\"Subject\",\"value\":\"\"}]" + end).unwrap(),
    ),
    (
      #|["t/+",[],"1970-01-01T00:00:00.001Z","1",""]
    ),
  )
  assert_true(
    thread_project(
      start +
      "[{\"name\":\"Subject\",\"value\":\"x\"},{\"name\":\"SUBJECT\",\"value\":\"x\"}]" +
      end,
    )
    is Err(InvalidCell("subject")),
  )
}

///|
test "Gmail Date fallback requires malformed original and preserves valid unsupported refusal" {
  let start = "{\"id\":\"t/+\",\"messages\":[{\"id\":\"m\",\"threadId\":\"t/+\",\"internalDate\":\"-1\",\"labelIds\":[],\"payload\":{\"headers\":[{\"name\":\"Date\",\"value\":\""
  let end = "\"}]}}]}"
  assert_eq(
    thread_values_wire(thread_project(start + "not a Date" + end).unwrap()),
    (
      #|["t/+",[],"1969-12-31T23:59:59.999Z","1",null]
    ),
  )
  for date in ["31 Dec 2016 23:59:60 +0000", "1 Jan 10000 00:00 +0000"] {
    assert_true(thread_project(start + date + end) is Err(UnsupportedDate))
  }
}

///|
test "Gmail whole selected thread rejects foreign duplicate and invalid unused known message fields" {
  let good = "{\"id\":\"m\",\"threadId\":\"t/+\",\"internalDate\":\"1\",\"labelIds\":[],\"payload\":{\"headers\":[]}}"
  let start = "{\"id\":\"t/+\",\"messages\":["
  assert_true(
    thread_project(start + good + "," + good + "]}") is Err(DuplicateMessage),
  )
  for
    bad in [
      "{\"id\":\"other\",\"threadId\":\"foreign\",\"internalDate\":\"1\",\"labelIds\":[],\"payload\":{\"headers\":[]}}",
      "{\"id\":\"other\",\"threadId\":\"t/+\",\"internalDate\":\"9007199254740993\",\"labelIds\":[null],\"payload\":{\"headers\":[]}}",
      "{\"id\":\"other\",\"threadId\":\"t/+\",\"internalDate\":\"01\",\"labelIds\":[],\"payload\":{\"headers\":[{\"name\":\"Date\",\"value\":\"1 Jan 2000 00:00 +0000\"}]}}",
      "{\"id\":\"other\",\"threadId\":\"t/+\",\"internalDate\":1,\"labelIds\":[],\"payload\":{\"headers\":[]}}",
    ] {
    assert_true(thread_project(start + good + "," + bad + "]}") is Err(_))
  }
  assert_true(
    thread_project("{\"id\":\"foreign\",\"messages\":[]}") is Err(ForeignThread),
  )
}

///|
test "Gmail full thread enforces aggregate projection work and exact retained value bounds" {
  let body = b"{\"id\":\"t/+\",\"messages\":[{\"id\":\"m\",\"threadId\":\"t/+\",\"internalDate\":\"1\",\"labelIds\":[\"INBOX\",\"INBOX\"],\"payload\":{\"headers\":[{\"name\":\"Date\",\"value\":\"1 Jan 2000 00:00 +0000\"}]}}]}"
  let targets = thread_list_page("{\"threads\":[{\"id\":\"t/+\"}]}").unwrap()
  for
    limits in [
      { ..thread_limits(), max_messages: 0, },
      { ..thread_limits(), max_labels: 1, },
      { ..thread_limits(), max_headers: 0, },
      { ..thread_limits(), max_header_units: 1, },
      { ..thread_limits(), max_value_nodes: 1, },
      { ..thread_limits(), max_value_text_bytes: 1, },
    ] {
    assert_true(
      project_gmail_thread(body, targets, 0, limits) is Err(BudgetExceeded),
    )
  }
  assert_true(
    project_gmail_thread(body, targets, 1, thread_limits())
    is Err(ForeignThread),
  )
}

///|
test "thread declaration retains the original exact ID candidate key" {
  inspect(
    gmail_thread_facts_wire(),
    content="{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}",
  )
}
