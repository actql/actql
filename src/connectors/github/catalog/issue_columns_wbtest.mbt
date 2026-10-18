///|
fn full_rest_issue() -> String {
  "{\"number\":7,\"node_id\":\"I_original\",\"title\":\"t\",\"state\":\"closed\"," +
  "\"state_reason\":\"completed\",\"body\":null,\"user\":null," +
  "\"assignees\":[{\"login\":\"first\"},{\"login\":\"second\"},{\"login\":\"first\"}]," +
  "\"labels\":[{\"name\":\" é \"},{\"name\":\"é\"},{\"name\":\" é \"}]," +
  "\"comments\":3,\"milestone\":{\"title\":\"2\",\"number\":99}," +
  "\"created_at\":\"2026-10-01T00:00:00Z\",\"updated_at\":\"2026-10-02T00:00:00Z\"," +
  "\"closed_at\":null,\"html_url\":\"https://github.com/o/r/issues/7\"}"
}

///|
fn rest_columns(body : String) -> Result[IssuePage, IssuePageIssue] {
  project_issue_page(@utf8.encode("[" + body + "]"), limits())
}

///|
test "all public Issue columns preserve native arrays original text and nullable state reason" {
  let page = rest_columns(full_rest_issue()).unwrap()
  let row = page.rows[0]
  assert_eq(row.number, 7L)
  assert_eq(row.comments, 3L)
  assert_eq(row.state_reason, Some("completed"))
  assert_eq(row.assignees, ["first", "second", "first"])
  assert_eq(row.labels, [" é ", "é", " é "])
  assert_eq(row.url, "https://github.com/o/r/issues/7")
  assert_eq(row.milestone, Some("2"))
  assert_eq(row.body, None)
  assert_eq(row.author, None)
  let empty = full_rest_issue()
    .replace(old="\"state_reason\":\"completed\"", new="\"state_reason\":null")
    .replace(
      old="\"assignees\":[{\"login\":\"first\"},{\"login\":\"second\"},{\"login\":\"first\"}]",
      new="\"assignees\":[]",
    )
  assert_eq(rest_columns(empty).unwrap().rows[0].state_reason, None)
  assert_eq(rest_columns(empty).unwrap().rows[0].assignees, [])
}

///|
test "REST integer columns read exact original numeric spans rather than binary64 placeholders" {
  for
    token in ["9007199254740993", "9223372036854775807", "9.007199254740993e15"] {
    let body = full_rest_issue().replace(
      old="\"number\":7,",
      new="\"number\":" + token + ",",
    )
    let expected = if token == "9223372036854775807" {
      9223372036854775807L
    } else {
      9007199254740993L
    }
    assert_eq(rest_columns(body).unwrap().rows[0].number, expected)
  }
  let count = full_rest_issue().replace(
    old="\"comments\":3,",
    new="\"comments\":9223372036854775807,",
  )
  assert_eq(rest_columns(count).unwrap().rows[0].comments, 9223372036854775807L)
}

///|
test "invalid original integer and requested native column shapes refuse rather than synthesize" {
  for token in ["9223372036854775808", "7.5", "-1", "\"7\"", "null"] {
    let body = full_rest_issue().replace(
      old="\"number\":7,",
      new="\"number\":" + token + ",",
    )
    assert_true(rest_columns(body) is Err(_))
  }
  for
    body in [
      full_rest_issue().replace(old="\"state_reason\":\"completed\",", new=""),
      full_rest_issue().replace(
        old="\"state_reason\":\"completed\"",
        new="\"state_reason\":3",
      ),
      full_rest_issue().replace(old="{\"login\":\"first\"}", new="{}"),
      full_rest_issue().replace(old="{\"name\":\"é\"}", new="\"é\""),
      full_rest_issue().replace(
        old="\"html_url\":\"https://github.com/o/r/issues/7\"",
        new="\"html_url\":null",
      ),
    ] {
    assert_true(rest_columns(body) is Err(_))
  }
}

///|
fn full_graphql_columns(
  fields : Array[(String, String)],
) -> Result[GraphqlIssuePage, GraphqlResponseIssue] {
  project(
    graphql_node(
      "R_A",
      1296269,
      "octo/hello",
      "{\"hasNextPage\":false,\"endCursor\":null}",
      graphql_issue(7, fields),
    ),
  )
}

///|
test "GraphQL public state reasons have explicit native enum correspondence" {
  for
    (native, value) in [
      ("COMPLETED", "completed"),
      ("DUPLICATE", "duplicate"),
      ("NOT_PLANNED", "not_planned"),
      ("REOPENED", "reopened"),
    ] {
    let page = full_graphql_columns([("stateReason", "\"" + native + "\"")]).unwrap()
    assert_eq(page.rows[0].state_reason, Some(value))
  }
  assert_eq(full_graphql_columns([]).unwrap().rows[0].state_reason, None)
  assert_true(
    full_graphql_columns([("stateReason", "\"completed\"")]) is Err(_),
  )
}

///|
test "GraphQL arrays retain all observed text and do not infer completion from a bounded first page" {
  let values = "{\"totalCount\":3,\"pageInfo\":{\"hasNextPage\":true,\"endCursor\":\"opaque cursor\"},\"nodes\":[{\"name\":\" é \"},{\"name\":\"é\"}]}"
  let page = full_graphql_columns([("labels", values)]).unwrap()
  assert_eq(page.rows[0].labels, [" é ", "é"])
  assert_eq(page.pending_fields, [
    { row_index: 0, field: "labels", after: "opaque cursor", total_count: 3L, },
  ])
  assert_true(
    full_graphql_columns([
      ("labels", values.replace(old="\"opaque cursor\"", new="null")),
    ])
    is Err(_),
  )
  assert_true(
    full_graphql_columns([
      (
        "labels",
        values.replace(old="\"hasNextPage\":true", new="\"hasNextPage\":false"),
      ),
    ])
    is Err(_),
  )
  let complete = full_graphql_columns([
    (
      "labels",
      values
      .replace(old="\"totalCount\":3", new="\"totalCount\":2")
      .replace(old="\"hasNextPage\":true", new="\"hasNextPage\":false"),
    ),
  ]).unwrap()
  assert_eq(complete.pending_fields, [])
  assert_eq(complete.rows[0].labels, [" é ", "é"])
}

///|
test "GraphQL native integer count and shape violations remain refusal" {
  for token in ["-1", "1.5", "2147483648", "\"7\"", "null"] {
    assert_true(full_graphql_columns([("number", token)]) is Err(_))
  }
  for value in ["null", "[]", "{}", "{\"totalCount\":0,\"nodes\":[]}"] {
    assert_true(full_graphql_columns([("assignees", value)]) is Err(_))
  }
}
