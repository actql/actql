///|
fn confirmation_repository() -> GraphqlRepository {
  { node_id: "R_original", database_id: 13L, name_with_owner: "o/r", }
}

///|
fn confirmation_reply(
  content : String,
  node_id? : String = "IC_original",
  id? : Int = 7,
  subject? : String = "I_original",
  repository? : String = "R_original",
  kind? : String = "IssueComment",
) -> String {
  (
    {
      "data": {
        "node": {
          "__typename": kind.to_json(),
          "id": node_id.to_json(),
          "databaseId": id.to_json(),
          "body": content.to_json(),
          "issue": { "__typename": "Issue", "id": subject.to_json() },
          "repository": {
            "__typename": "Repository",
            "id": repository.to_json(),
            "databaseId": 13,
            "nameWithOwner": "o/r",
          },
        },
      },
    } : Json).stringify()
}

///|
fn confirm_comment(
  reply : String,
  logical : String,
  tag? : String = "sha256:" + "a".repeat(64),
) -> Result[Unit, GraphqlResponseIssue] {
  project_comment_confirmation_response(
    @utf8.encode(reply),
    { max_bytes: 100000, max_nodes: 1000, max_depth: 32, max_rows: 1, },
    7L,
    "IC_original",
    "I_original",
    confirmation_repository(),
    logical,
    tag,
  )
}

///|
test "comment confirmation requests only the original opaque comment" {
  let expected : Json = {
    "query": "query ActqlConfirmComment($id: ID!) { node(id: $id) { __typename ... on IssueComment { id databaseId body issue { __typename id } repository { __typename id databaseId nameWithOwner } } } }",
    "variables": { "id": "IC_original" },
  }
  assert_eq(
    comment_confirmation_request("IC_original"),
    Ok(expected.stringify()),
  )
  assert_eq(comment_confirmation_request(""), Err(InvalidSubjectId))
  assert_eq(
    comment_confirmation_request("x".repeat(257)),
    Err(InvalidSubjectId),
  )
}

///|
test "comment confirmation requires exact original content and marker without normalization" {
  let logical = " e\u{301}\r\n\u{1F600} "
  let physical = logical +
    "\n\n<!-- actql:effect:sha256:" +
    "a".repeat(64) +
    " -->"
  assert_eq(confirm_comment(confirmation_reply(physical), logical), Ok(()))
  assert_eq(
    confirm_comment(confirmation_reply(physical), " é\r\n\u{1F600} "),
    Err(BindingChanged),
  )
  assert_eq(
    confirm_comment(confirmation_reply(logical), logical),
    Err(BindingChanged),
  )
  assert_eq(
    confirm_comment(
      confirmation_reply(physical),
      logical,
      tag="sha256:" + "b".repeat(64),
    ),
    Err(BindingChanged),
  )
}

///|
test "comment confirmation preserves an explicitly empty logical body" {
  let physical = "\n\n<!-- actql:effect:sha256:" + "a".repeat(64) + " -->"
  assert_eq(confirm_comment(confirmation_reply(physical), ""), Ok(()))
  assert_eq(
    confirm_comment(confirmation_reply(physical[2:].to_owned()), ""),
    Err(BindingChanged),
  )
}

///|
test "comment confirmation refuses a foreign comment subject repository or native kind" {
  let physical = "body\n\n<!-- actql:effect:sha256:" + "a".repeat(64) + " -->"
  for
    reply in [
      confirmation_reply(physical, node_id="IC_other"),
      confirmation_reply(physical, id=8),
      confirmation_reply(physical, subject="I_other"),
      confirmation_reply(physical, repository="R_other"),
      confirmation_reply(physical, kind="PullRequestReviewComment"),
    ] {
    assert_true(confirm_comment(reply, "body") is Err(_))
  }
}

///|
test "comment confirmation never treats missing partial or malformed readback as no mutation" {
  for
    reply in [
      "{}", "{\"data\":{\"node\":null}}", "{\"errors\":[{\"type\":\"NOT_FOUND\",\"message\":\"missing\"}],\"data\":null}",
    ] {
    assert_true(confirm_comment(reply, "body") is Err(_))
  }
  assert_true(
    confirm_comment("{}", "body", tag="not-an-original-key") is Err(_),
  )
  assert_true(
    confirm_comment("{}", "x".repeat(max_comment_characters))
    is Err(BudgetExceeded),
  )
  assert_true(
    project_comment_confirmation_response(
      b"{}",
      { max_bytes: 1, max_nodes: 1000, max_depth: 32, max_rows: 1, },
      7L,
      "IC_original",
      "I_original",
      confirmation_repository(),
      "body",
      "sha256:" + "a".repeat(64),
    )
    is Err(BudgetExceeded),
  )
}
