///|
fn limits() -> SlackUserListLimits {
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
fn project(text : String) -> Result[SlackUserListPage, SlackUserListIssue] {
  project_slack_user_list(@utf8.encode(text), limits())
}

///|
fn rejected(text : String) -> Unit raise {
  match project(text) {
    Err(_) => ()
    Ok(_) => fail("Expected whole Slack user page refusal")
  }
}

///|
fn issue(
  bytes : Bytes,
  bound : SlackUserListLimits,
) -> SlackUserListIssue raise {
  match project_slack_user_list(bytes, bound) {
    Err(value) => value
    Ok(_) => fail("Expected exact Slack refusal")
  }
}

///|
test "Slack user page retains exact identity profile values nullable absence and opaque continuation" {
  let body =
    #|{"ok":true,"members":[{"id":"U1","name":"original","real_name":"legacy copy","profile":{"real_name":"観測 é","display_name":"","email":null,"title":"bounded vendor extra"},"tz":"Asia/Tokyo","is_bot":false,"deleted":true},{"id":"U2","profile":null}],"response_metadata":{"next_cursor":"a+/= é"},"cache_ts":123}
  let page = project(body).unwrap()
  assert_eq(page.response_sha256, @sha.hex(@utf8.encode(body)))
  assert_eq(page.next_cursor, Some("a+/= é"))
  assert_eq(slack_user_list_ids(page), ["U1", "U2"])
  assert_eq(
    slack_user_list_rows_wire(
      page,
      slack_user_list_column_names(),
      8192,
      100,
      8,
    ).unwrap(),
    (
      #|[{"id":"U1","name":"original","real_name":"観測 é","display_name":"","email":null,"tz":"Asia/Tokyo","is_bot":false,"deleted":true},{"id":"U2","name":null,"real_name":null,"display_name":null,"email":null,"tz":null,"is_bot":null,"deleted":null}]
    ),
  )
}

///|
test "Slack user terminal empty page is distinct from a page with an opaque next cursor" {
  for
    body in [
      "{\"ok\":true,\"members\":[]}", "{\"ok\":true,\"members\":[],\"response_metadata\":{}}",
      "{\"ok\":true,\"members\":[],\"response_metadata\":{\"next_cursor\":\"\"}}",
    ] {
    let page = project(body).unwrap()
    assert_eq(page.next_cursor, None)
    assert_eq(slack_user_list_ids(page), [])
  }
  let page = project(
    "{\"ok\":true,\"members\":[],\"response_metadata\":{\"next_cursor\":\"original\"}}",
  ).unwrap()
  assert_eq(page.next_cursor, Some("original"))
}

///|
test "Slack API errors malformed members and ambiguous continuation do not become empty success" {
  for
    body in [
      "{}", "null", "{\"ok\":false,\"members\":[]}", "{\"ok\":true}", "{\"ok\":true,\"members\":null}",
      "{\"ok\":true,\"members\":{}}", "{\"ok\":true,\"members\":[],\"error\":\"ratelimited\"}",
      "{\"ok\":true,\"members\":[],\"response_metadata\":null}", "{\"ok\":true,\"members\":[],\"response_metadata\":{\"next_cursor\":null}}",
      "{\"ok\":true,\"members\":[],\"response_metadata\":{\"next_cursor\":3}}", "{\"ok\":true,\"members\":[],\"ok\":false}",
      "{\"ok\":true,\"members\":[{\"id\":\"U1\",\"name\":\"one\",\"name\":\"two\"}]}",
      "{\"ok\":true,\"members\":[]}{}",
    ] {
    rejected(body)
  }
}

///|
test "Slack user every declared cell and same page key is checked before projection" {
  for
    body in [
      "{\"ok\":true,\"members\":[{}]}", "{\"ok\":true,\"members\":[{\"id\":null}]}",
      "{\"ok\":true,\"members\":[{\"id\":\"\"}]}", "{\"ok\":true,\"members\":[{\"id\":\"U1\"},{\"id\":\"U1\"}]}",
      "{\"ok\":true,\"members\":[{\"id\":\"U1\",\"profile\":[]}]}", "{\"ok\":true,\"members\":[{\"id\":\"U1\",\"profile\":{\"email\":false}}]}",
      "{\"ok\":true,\"members\":[{\"id\":\"U1\",\"name\":8}]}", "{\"ok\":true,\"members\":[{\"id\":\"U1\",\"is_bot\":\"false\"}]}",
      "{\"ok\":true,\"members\":[{\"id\":\"U1\",\"deleted\":0}]}",
    ] {
    rejected(body)
  }
  let page = project("{\"ok\":true,\"members\":[{\"id\":\"U1\"}]}").unwrap()
  assert_eq(
    slack_user_list_rows_wire(page, ["id"], 100, 20, 8).unwrap(),
    "[{\"id\":\"U1\"}]",
  )
  assert_eq(
    slack_user_list_rows_wire(page, ["email", "email"], 100, 20, 8),
    Err(InvalidSelection("email")),
  )
  assert_eq(
    slack_user_list_rows_wire(page, ["unknown"], 100, 20, 8),
    Err(InvalidSelection("unknown")),
  )
}

///|
test "Slack nullable fields never infer scope permission or fabricate booleans and names" {
  let page = project(
    "{\"ok\":true,\"members\":[{\"id\":\"U1\",\"real_name\":\"not profile\",\"deleted\":null}]}",
  ).unwrap()
  assert_eq(
    slack_user_list_rows_wire(
      page,
      ["real_name", "email", "is_bot", "deleted"],
      200,
      20,
      8,
    ).unwrap(),
    "[{\"real_name\":null,\"email\":null,\"is_bot\":null,\"deleted\":null}]",
  )
  assert_eq(
    slack_user_list_schema_wire(2048, 100, 8).unwrap(),
    (
      #|{"deleted":{"nullable":true,"type":"boolean"},"display_name":{"nullable":true,"type":"string"},"email":{"nullable":true,"type":"string"},"id":{"nullable":false,"type":"string"},"is_bot":{"nullable":true,"type":"boolean"},"name":{"nullable":true,"type":"string"},"real_name":{"nullable":true,"type":"string"},"tz":{"nullable":true,"type":"string"}}
    ),
  )
  assert_eq(
    slack_user_list_facts_wire(),
    "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}",
  )
}

///|
test "Slack user original raw cursor value and output budgets fail before partial rows" {
  let body = @utf8.encode("{\"ok\":true,\"members\":[{\"id\":\"U1\"}]}")
  assert_eq(issue(body, { ..limits(), max_bytes: 1, }), BudgetExceeded)
  assert_eq(issue(body, { ..limits(), max_nodes: 1, }), BudgetExceeded)
  assert_eq(issue(body, { ..limits(), max_value_nodes: 7, }), BudgetExceeded)
  assert_eq(
    issue(body, { ..limits(), max_value_text_bytes: 1, }),
    BudgetExceeded,
  )
  assert_eq(issue(body, { ..limits(), max_rows: 0, }), InvalidLimits)
  let cursor = @utf8.encode(
    "{\"ok\":true,\"members\":[],\"response_metadata\":{\"next_cursor\":\"é\"}}",
  )
  assert_eq(issue(cursor, { ..limits(), max_cursor_bytes: 1, }), BudgetExceeded)
  let page = project_slack_user_list(body, limits()).unwrap()
  assert_eq(
    slack_user_list_rows_wire(page, ["id"], 1, 100, 8),
    Err(BudgetExceeded),
  )
}
