///|
fn native_pull_request_bridge_body() -> Bytes {
  @utf8.encode(
    "{\"data\":{\"node\":{\"__typename\":\"Repository\",\"id\":\"R_A\",\"databaseId\":1296269,\"nameWithOwner\":\"octo/hello\",\"pullRequests\":{\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":null},\"nodes\":[{\"__typename\":\"PullRequest\",\"number\":2147483647,\"id\":\"PR_A\",\"title\":\"original\",\"state\":\"MERGED\",\"body\":\"\",\"author\":null,\"assignees\":{\"totalCount\":0,\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":null},\"nodes\":[]},\"labels\":{\"totalCount\":0,\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":null},\"nodes\":[]},\"comments\":{\"totalCount\":2147483647},\"milestone\":{\"title\":\"2\"},\"createdAt\":\"2026-10-01T00:00:00Z\",\"updatedAt\":\"2026-10-02T00:00:00Z\",\"closedAt\":\"2026-10-02T00:00:00Z\",\"url\":\"https://github.com/octo/hello/pull/2147483647\",\"baseRefName\":\"main\",\"headRefName\":\"deleted/original\",\"isDraft\":false,\"mergeable\":\"UNKNOWN\",\"mergedAt\":\"2026-10-02T00:00:00Z\",\"mergedBy\":{\"login\":\"octo\"},\"reviewDecision\":\"APPROVED\"}]}}}}",
  )
}

///|
test "typed PullRequest bridge emits all declared fields without coercing native identities" {
  let read = github_pull_request_page_read_begin(
    native_pull_request_bridge_body(),
    10000,
    1000,
    32,
    100,
    3,
    "R_A",
    1296269.0,
    "octo/hello",
  ).unwrap()
  let wire = github_pull_request_page_read_finish_json(read).unwrap()
  let expected : Json = {
    "rows": [
      {
        "number": "2147483647",
        "node_id": "PR_A",
        "title": "original",
        "state": "merged",
        "state_reason": Json::null(),
        "body": "",
        "author": Json::null(),
        "assignees": [],
        "labels": [],
        "url": "https://github.com/octo/hello/pull/2147483647",
        "comments": "2147483647",
        "milestone": "2",
        "created_at": "2026-10-01T00:00:00.000Z",
        "updated_at": "2026-10-02T00:00:00.000Z",
        "closed_at": "2026-10-02T00:00:00.000Z",
        "base": "main",
        "head": "deleted/original",
        "draft": false,
        "mergeable": Json::null(),
        "merged_at": "2026-10-02T00:00:00.000Z",
        "merged_by": "octo",
        "review_decision": "approved",
      },
    ],
    "hasNextPage": false,
    "endCursor": Json::null(),
    "repository": {
      "node_id": "R_A",
      "database_id": 1296269,
      "name_with_owner": "octo/hello",
    },
  }
  assert_eq(wire, expected.stringify())
  assert_true(github_pull_request_page_read_finish_json(read) is Err(_))
  github_pull_request_page_read_close(read)
}

///|
test "typed PullRequest bridge refuses a foreign repository before exposing a page" {
  assert_true(
    github_pull_request_page_read_begin(
      native_pull_request_bridge_body(),
      10000,
      1000,
      32,
      100,
      3,
      "R_OTHER",
      1296269.0,
      "octo/hello",
    )
    is Err(_),
  )
  let request = github_pull_requests_request_json(
    "R_A",
    100,
    false,
    "",
    "merged",
    [],
  )
  assert_true(request.contains("query ActqlPullRequests("))
  assert_true(request.contains("\"states\":[\"MERGED\"]"))
  assert_true(!request.contains("stateReason"))
}
