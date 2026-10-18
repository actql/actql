///|
fn pull_request_fields_fixture(
  replacements : Array[(String, Json)],
  omitted? : String = "",
) -> @decode.ObjectView {
  let values : Map[String, Json] = {
    "baseRefName": "main".to_json(),
    "headRefName": "feature/original".to_json(),
    "isDraft": false.to_json(),
    "mergeable": "UNKNOWN".to_json(),
    "mergedAt": Json::null(),
    "mergedBy": Json::null(),
    "reviewDecision": Json::null(),
  }
  for (name, value) in replacements {
    values[name] = value
  }
  values.remove(omitted) |> ignore
  let wire = Json::object(values).stringify()
  let source = @source.parse_json_bytes(@utf8.encode(wire), {
    max_input_bytes: 10000,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 100,
    max_depth: 10,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
  @decode.open_object(cursor).unwrap()
}

///|
test "PullRequest native fields retain exact ref names and undecided observations" {
  let fields = graphql_pull_request_fields(
    pull_request_fields_fixture([
      ("baseRefName", "release/\u{65E5}\u{672C}".to_json()),
      ("headRefName", "e\u0301/original".to_json()),
      ("isDraft", true.to_json()),
    ]),
  ).unwrap()
  assert_eq(fields, {
    base: "release/\u{65E5}\u{672C}",
    head: "e\u0301/original",
    draft: true,
    mergeable: None,
    merged_at: None,
    merged_by: None,
    review_decision: None,
  })
}

///|
test "PullRequest mergeability and review enums have explicit closed correspondences" {
  for
    (native, expected) in [
      ("MERGEABLE", Some(true)),
      ("CONFLICTING", Some(false)),
      ("UNKNOWN", None),
    ] {
    assert_eq(
      graphql_pull_request_fields(
        pull_request_fields_fixture([("mergeable", native.to_json())]),
      ).unwrap().mergeable,
      expected,
    )
  }
  for
    (native, expected) in [
      ("APPROVED", "approved"),
      ("CHANGES_REQUESTED", "changes_requested"),
      ("REVIEW_REQUIRED", "review_required"),
    ] {
    assert_eq(
      graphql_pull_request_fields(
        pull_request_fields_fixture([("reviewDecision", native.to_json())]),
      ).unwrap().review_decision,
      Some(expected),
    )
  }
}

///|
test "PullRequest observed merge actor and time stay separate from authority" {
  let actor : Json = { "login": "bot[bot]".to_json() }
  let fields = graphql_pull_request_fields(
    pull_request_fields_fixture([
      ("mergedBy", actor),
      ("mergedAt", "2026-10-19T01:02:03Z".to_json()),
    ]),
  ).unwrap()
  assert_eq(fields.merged_by, Some("bot[bot]"))
  assert_eq(fields.merged_at, Some("2026-10-19T01:02:03.000Z"))
}

///|
test "PullRequest malformed requested fields refuse instead of becoming SQL null" {
  for
    name in [
      "baseRefName", "headRefName", "isDraft", "mergeable", "mergedAt", "mergedBy",
      "reviewDecision",
    ] {
    assert_eq(
      graphql_pull_request_fields(pull_request_fields_fixture([], omitted=name)),
      Err(MissingRequiredField(name)),
    )
  }
  for
    (name, value) in [
      ("baseRefName", Json::null()),
      ("headRefName", (7).to_json()),
      ("isDraft", "false".to_json()),
      ("mergeable", "false".to_json()),
      ("mergeable", Json::null()),
      ("mergedAt", "yesterday".to_json()),
      ("mergedBy", "octo".to_json()),
      ("mergedBy", Json::object({})),
      ("reviewDecision", "APPROVED_FUTURE".to_json()),
    ] {
    assert_true(
      graphql_pull_request_fields(pull_request_fields_fixture([(name, value)]))
      is Err(_),
    )
  }
}

///|
fn graphql_pull_request_fixture(
  state : String,
  fields : Array[(String, String)],
) -> String {
  let common = graphql_issue(
    1,
    [("state", state.to_json().stringify()), ..fields],
  ).replace_all(old="\"stateReason\":null,", new="")
  let native = "\"__typename\":\"PullRequest\",\"baseRefName\":\"main\",\"headRefName\":\"deleted/original\",\"isDraft\":false,\"mergeable\":\"UNKNOWN\",\"mergedAt\":null,\"mergedBy\":null,\"reviewDecision\":null,"
  (native + common.view(start_offset=1).to_owned()) |> fn(row) { "{" + row }
}

///|
fn pull_request_outer_fixture(row : String) -> String {
  graphql_node(
    "R_A", 1296269, "octo/hello", "{\"hasNextPage\":false,\"endCursor\":null}", row,
  ).replace_all(old="\"issues\":", new="\"pullRequests\":")
}

///|
fn project_pull_request_fixture(
  body : String,
) -> Result[GraphqlPullRequestPage, GraphqlResponseIssue] {
  project_pull_requests_response(
    @utf8.encode(body),
    page_limits(),
    "R_A",
    1296269L,
    "octo/hello",
  )
}

///|
test "PullRequest native states stay distinct and Issue-only reason is inapplicable" {
  for
    (native, state) in [
      ("OPEN", "open"),
      ("CLOSED", "closed"),
      ("MERGED", "merged"),
    ] {
    let page = project_pull_request_fixture(
      pull_request_outer_fixture(graphql_pull_request_fixture(native, [])),
    ).unwrap()
    assert_eq(page.rows.length(), 1)
    assert_eq(page.rows[0].common.state, state)
    assert_eq(page.rows[0].common.state_reason, None)
    assert_eq(page.rows[0].native.head, "deleted/original")
    assert_eq(page.rows[0].native.mergeable, None)
  }
  // The old Issue path still requires its requested reason and rejects MERGED.
  let issue = graphql_node(
    "R_A",
    1296269,
    "octo/hello",
    "{\"hasNextPage\":false,\"endCursor\":null}",
    graphql_issue(1, []),
  )
  assert_eq(
    project(issue.replace_all(old="\"stateReason\":null,", new="")),
    Err(Row(MissingRequiredField("stateReason"))),
  )
  assert_eq(
    project(
      issue.replace_all(old="\"state\":\"OPEN\"", new="\"state\":\"MERGED\""),
    ),
    Err(Row(InvalidField("state"))),
  )
}

///|
test "PullRequest admission refuses foreign native types and malformed required state" {
  let body = pull_request_outer_fixture(
    graphql_pull_request_fixture("OPEN", []),
  )
  assert_eq(
    project_pull_request_fixture(
      body.replace_all(
        old="\"__typename\":\"PullRequest\"",
        new="\"__typename\":\"Issue\"",
      ),
    ),
    Err(WrongType("Issue")),
  )
  assert_eq(
    project_pull_request_fixture(
      body.replace_all(old="\"__typename\":\"PullRequest\",", new=""),
    ),
    Err(Row(MissingRequiredField("__typename"))),
  )
  assert_eq(
    project_pull_request_fixture(
      body.replace_all(old="\"state\":\"OPEN\"", new="\"state\":\"FUTURE\""),
    ),
    Err(Row(InvalidField("state"))),
  )
}

///|
test "PullRequest page keeps the original repository and pagination refusal boundary" {
  let body = pull_request_outer_fixture(
    graphql_pull_request_fixture("OPEN", []),
  )
  assert_eq(
    project_pull_request_fixture(
      body.replace_all(old="\"id\":\"R_A\"", new="\"id\":\"R_B\""),
    ),
    Err(IdRepresentationChanged),
  )
  assert_eq(
    project_pull_request_fixture(body.replace_all(old="1296269", new="1296270")),
    Err(ForeignRepository),
  )
  assert_eq(
    project_pull_request_fixture(
      body.replace_all(old="octo/hello", new="octo/moved"),
    ),
    Err(BindingChanged),
  )
  assert_eq(
    project_pull_request_fixture(
      body.replace_all(old="\"hasNextPage\":false", new="\"hasNextPage\":true"),
    ),
    Err(MissingCursor),
  )
}

///|
fn pull_request_nested_read(max_pages? : Int = 4) -> PullRequestPageRead {
  let body = pull_request_outer_fixture(
    graphql_pull_request_fixture("MERGED", [
      ("assignees", field_connection("assignees", ["a"], 3, Some("A0"))),
      ("labels", field_connection("labels", [" é "], 3, Some("L0"))),
    ]),
  )
  begin_pull_request_page_read(
    @utf8.encode(body),
    page_limits(),
    max_pages,
    "R_A",
    1296269L,
    "octo/hello",
  ).unwrap()
}

///|
fn pull_request_field_response(
  field : String,
  values : Array[String],
  total : Int,
  after : String?,
) -> String {
  field_response(field, values, total, after)
  .replace_all(
    old="\"issue\":{",
    new="\"pullRequest\":{\"__typename\":\"PullRequest\",",
  )
  .replace_all(old="\"I_7\"", new="\"I_1\"")
  .replace_all(old="\"number\":7", new="\"number\":1")
}

///|
test "PullRequest nested fields share the original bounded continuation machine" {
  let read = pull_request_nested_read()
  let request = pull_request_page_read_next_request(read, 100).unwrap().unwrap()
  assert_true(request.contains("query ActqlPullRequestAssignees("))
  assert_true(request.contains("pullRequest(number: $number)"))
  assert_true(!request.contains("mutation"))
  assert_true(pull_request_page_read_finish(read) is Err(_))
  pull_request_page_read_accept(
    read,
    @utf8.encode(pull_request_field_response("assignees", ["b", "a"], 3, None)),
  ).unwrap()
  assert_true(
    pull_request_page_read_next_request(read, 100)
    .unwrap()
    .unwrap()
    .contains("query ActqlPullRequestLabels("),
  )
  pull_request_page_read_accept(
    read,
    @utf8.encode(
      pull_request_field_response("labels", ["é", " é "], 3, None),
    ),
  ).unwrap()
  assert_eq(pull_request_page_read_next_request(read, 100), Ok(None))
  let page = pull_request_page_read_finish(read).unwrap()
  assert_eq(page.rows[0].common.assignees, ["a", "b", "a"])
  assert_eq(page.rows[0].common.labels, [" é ", "é", " é "])
  assert_eq(page.rows[0].common.state, "merged")
  assert_eq(page.rows[0].common.state_reason, None)
  assert_eq(page.rows[0].native.head, "deleted/original")
  assert_eq(page.pending_fields, [])
  assert_true(pull_request_page_read_finish(read) is Err(_))
}

///|
test "PullRequest nested refusal stays refused after restored response and enforces total page ceiling" {
  let response = pull_request_field_response("assignees", ["b", "a"], 3, None)
  for
    (old, replacement) in [
      ("\"__typename\":\"PullRequest\"", "\"__typename\":\"Issue\""),
      ("\"I_1\"", "\"I_other\""),
      ("2026-10-02T00:00:00Z", "2026-10-03T00:00:00Z"),
      ("octo/hello", "octo/moved"),
    ] {
    let read = pull_request_nested_read()
    assert_true(
      pull_request_page_read_accept(
        read,
        @utf8.encode(response.replace_all(old~, new=replacement)),
      )
      is Err(_),
    )
    assert_true(
      pull_request_page_read_accept(read, @utf8.encode(response)) is Err(_),
    )
    assert_true(pull_request_page_read_finish(read) is Err(_))
  }
  let bounded = pull_request_nested_read(max_pages=1)
  assert_eq(
    pull_request_page_read_accept(bounded, @utf8.encode(response)),
    Err(BudgetExceeded),
  )
  assert_true(pull_request_page_read_finish(bounded) is Err(_))
}
