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
