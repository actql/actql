///|
fn confirmation_fixture(
  logical? : String = "cafe\u{301}\r\n東京",
) -> CommentConfirmation {
  let tag = "sha256:" + String::make(64, 'a')
  let physical = logical + "\n\n<!-- actql:effect:" + tag + " -->"
  let wire = add_comment_request("I_1", physical).unwrap()
  prepare_comment_confirmation(
    { node_id: "R_1", database_id: 11L, name_with_owner: "owner/repo", },
    "I_1",
    logical,
    tag,
    wire,
    200,
    true,
    headers([]),
    @utf8.encode(
      "{\"data\":{\"addComment\":{\"commentEdge\":{\"node\":{\"id\":\"IC_7\",\"databaseId\":7}},\"subject\":{\"__typename\":\"Issue\",\"id\":\"I_1\"}}}}",
    ),
    comment_limits(),
    comment_limits(),
  ).unwrap()
}

///|
fn confirmation_reply(body : String) -> String {
  let repo : Json = {
    "__typename": "Repository",
    "id": "R_1",
    "databaseId": 11,
    "nameWithOwner": "owner/repo",
  }
  (
    {
      "data": {
        "node": {
          "__typename": "IssueComment",
          "id": "IC_7",
          "fullDatabaseId": "7",
          "body": body.to_json(),
          "repository": repo,
          "issue": { "__typename": "Issue", "id": "I_1", "repository": repo },
          "pullRequest": Json::null(),
        },
      },
    } : Json).stringify()
}

///|
test "Comment confirmation retains exact original marker body and point address" {
  for logical in ["cafe\u{301}\r\n東京", ""] {
    let held = confirmation_fixture(logical~)
    let expected_query = "query ActqlConfirmCreatedIssueComment($id: ID!) { node(id: $id) { __typename ... on IssueComment { id fullDatabaseId body repository { __typename id databaseId nameWithOwner } issue { __typename id repository { __typename id databaseId nameWithOwner } } pullRequest { id } } } }"
    let expected : Json = {
      "query": expected_query.to_json(),
      "variables": { "id": "IC_7" },
    }
    assert_eq(comment_confirmation_request(held), Some(expected.stringify()))
    let physical = logical +
      "\n\n<!-- actql:effect:sha256:" +
      String::make(64, 'a') +
      " -->"
    assert_eq(
      project_comment_confirmation(
        held,
        200,
        @utf8.encode(confirmation_reply(physical)),
      ),
      Ok((7L, "IC_7")),
    )
    assert_true(
      project_comment_confirmation(
        held,
        200,
        @utf8.encode(confirmation_reply(logical)),
      )
      is Err(_),
    )
  }
}

///|
test "Comment confirmation refuses foreign objects subjects repositories bodies and partial reads" {
  let held = confirmation_fixture()
  let physical = "cafe\u{301}\r\n東京\n\n<!-- actql:effect:sha256:" +
    String::make(64, 'a') +
    " -->"
  let original = confirmation_reply(physical)
  for
    (old, replacement) in [
      ("\"IC_7\"", "\"IC_foreign\""),
      ("\"I_1\"", "\"I_foreign\""),
      ("\"R_1\"", "\"R_foreign\""),
      ("\"owner/repo\"", "\"owner/other\""),
      ("\"databaseId\":11", "\"databaseId\":12"),
      ("\"fullDatabaseId\":\"7\"", "\"fullDatabaseId\":\"07\""),
      ("\"fullDatabaseId\":\"7\"", "\"fullDatabaseId\":7"),
      ("\"pullRequest\":null", "\"pullRequest\":{\"id\":\"PR_1\"}"),
      ("\"__typename\":\"Issue\"", "\"__typename\":\"PullRequest\""),
      ("actql:effect:sha256:aaaa", "actql:effect:sha256:baaa"),
    ] {
    let changed = original.replace(old~, new=replacement)
    assert_true(changed != original)
    assert_true(
      project_comment_confirmation(held, 200, @utf8.encode(changed)) is Err(_),
    )
  }
  for
    body in [
      "{\"data\":{\"node\":null}}", "{\"data\":null}", "{\"errors\":[],\"data\":{}}",
      "{\"errors\":[{\"message\":\"partial\"}],\"data\":{}}",
    ] {
    assert_true(
      project_comment_confirmation(held, 200, @utf8.encode(body)) is Err(_),
    )
  }
  assert_true(
    project_comment_confirmation(held, 403, @utf8.encode(original)) is Err(_),
  )
  assert_true(
    project_comment_confirmation(
      held,
      200,
      @utf8.encode(
        confirmation_reply(physical.replace(old="cafe\u{301}", new="caf\u{e9}")),
      ),
    )
    is Err(_),
  )
}

///|
test "Comment confirmation checks final original request and leaves unconfirmed mutation uncertain" {
  let repo : GraphqlRepository = {
    node_id: "R_1",
    database_id: 11L,
    name_with_owner: "owner/repo",
  }
  let tag = "sha256:" + String::make(64, 'a')
  let wire = add_comment_request("I_1", "\n\n<!-- actql:effect:" + tag + " -->").unwrap()
  for
    changed in [
      wire.replace(old="I_1", new="I_other"),
      wire.replace(old="ActqlAddComment", new="OtherMutation"),
      wire.replace(old="effect:sha256:a", new="effect:sha256:b"),
    ] {
    assert_true(
      prepare_comment_confirmation(
        repo,
        "I_1",
        "",
        tag,
        changed,
        200,
        true,
        headers([]),
        b"{}",
        comment_limits(),
        comment_limits(),
      )
      is Err(_),
    )
  }
  for
    (status, known, body) in [
      (403, false, "{}"),
      (500, true, "{}"),
      (
        200, true, "{\"errors\":[{\"message\":\"unknown\",\"type\":\"RATE_LIMITED\"}]}",
      ),
      (200, true, "{\"data\":null,\"errors\":[{\"message\":\"partial\"}]}"),
    ] {
    let held = prepare_comment_confirmation(
      repo,
      "I_1",
      "",
      tag,
      wire,
      status,
      known,
      headers([]),
      @utf8.encode(body),
      comment_limits(),
      comment_limits(),
    ).unwrap()
    assert_eq(comment_confirmation_request(held), None)
    assert_true(project_comment_confirmation(held, 200, b"{}") is Err(_))
  }
}
