///|
fn comment_limits() -> PageLimits {
  { max_bytes: 100000, max_nodes: 10000, max_depth: 32, max_rows: 1, }
}

///|
fn classify(status : Int, body : String) -> CommentOutcome {
  classify_comment_response(
    status,
    headers([]),
    @utf8.encode(body),
    comment_limits(),
    "I_1",
  )
}

///|
fn created_reply(subject_type : String, subject_id : String) -> String {
  "{\"data\":{\"addComment\":{\"commentEdge\":{\"node\":{\"id\":\"IC_7\",\"databaseId\":7}},\"subject\":{\"__typename\":\"" +
  subject_type +
  "\",\"id\":\"" +
  subject_id +
  "\"}}}}"
}

///|
test "requests carry only the fixed documents and the exact body" {
  let body = "caf\u{65}\u{301}\r\n<b>"
  let expected : Json = {
    "query": add_comment_mutation.to_json(),
    "variables": { "subjectId": "I_1".to_json(), "body": body.to_json() },
  }
  assert_eq(add_comment_request("I_1", body), Ok(expected.stringify()))
  // No normalization: a composed spelling is a different request.
  assert_true(
    add_comment_request("I_1", "caf\u{e9}\r\n<b>") !=
    add_comment_request("I_1", body),
  )
  assert_true(add_comment_mutation.has_prefix("mutation ActqlAddComment("))
  assert_true(add_comment_mutation.contains("subjectId: $subjectId"))
  assert_true(comment_subject_query.has_prefix("query ActqlCommentSubject("))
  assert_true(!comment_subject_query.contains("mutation"))
  assert_eq(add_comment_request("", "x"), Err(InvalidSubjectId))
  assert_eq(add_comment_request("I_1", ""), Err(InvalidBody))
  let limit = String::make(max_comment_characters, 'a')
  assert_true(add_comment_request("I_1", limit) is Ok(_))
  assert_eq(add_comment_request("I_1", limit + "a"), Err(InvalidBody))
  // Characters, not UTF-16 units or bytes, are counted.
  assert_true(
    add_comment_request(
      "I_1",
      String::make(max_comment_characters, '\u{1F600}'),
    )
    is Ok(_),
  )
  assert_eq(
    comment_subject_request("I_1"),
    Ok(
      (
        {
          "query": comment_subject_query.to_json(),
          "variables": { "id": "I_1".to_json() },
        } : Json).stringify(),
    ),
  )
  assert_eq(comment_subject_request(""), Err(InvalidSubjectId))
}

///|
fn subject(type_name : String, id : String, repository : String) -> String {
  "{\"data\":{\"node\":{\"__typename\":\"" +
  type_name +
  "\",\"id\":\"" +
  id +
  "\",\"number\":1,\"repository\":" +
  repository +
  "}}}"
}

///|
fn repo(id : String, database_id : Int, name : String) -> String {
  "{\"__typename\":\"Repository\",\"id\":\"" +
  id +
  "\",\"databaseId\":" +
  database_id.to_string() +
  ",\"nameWithOwner\":\"" +
  name +
  "\"}"
}

///|
fn check_subject(body : String) -> Result[CommentSubject, GraphqlResponseIssue] {
  project_comment_subject_response(
    @utf8.encode(body),
    comment_limits(),
    "I_1",
    "R_A",
    1296269L,
    "octo/hello",
  )
}

///|
test "a comment subject must be an Issue of the published repository" {
  let home = repo("R_A", 1296269, "octo/hello")
  assert_eq(
    check_subject(subject("Issue", "I_1", home)),
    Ok({
      node_id: "I_1",
      number: 1L,
      repository: {
        node_id: "R_A",
        database_id: 1296269L,
        name_with_owner: "octo/hello",
      },
    }),
  )
  // A pull request accepts addComment too; it is not an Issue comment.
  assert_eq(
    check_subject(subject("PullRequest", "I_1", home)),
    Err(WrongType("PullRequest")),
  )
  assert_eq(
    check_subject(subject("Issue", "I_1", repo("R_B", 424242, "octo/hello"))),
    Err(ForeignRepository),
  )
  assert_eq(
    check_subject(subject("Issue", "I_1", repo("R_A2", 1296269, "octo/hello"))),
    Err(IdRepresentationChanged),
  )
  assert_eq(
    check_subject(subject("Issue", "I_1", repo("R_A", 1296269, "octo/moved"))),
    Err(BindingChanged),
  )
  assert_eq(check_subject(subject("Issue", "I_2", home)), Err(ForeignSubject))
  assert_eq(
    check_subject("{\"data\":{\"node\":null}}"),
    Err(SubjectUnavailable),
  )
  assert_eq(
    check_subject("{\"data\":null,\"errors\":[{\"type\":\"RATE_LIMITED\"}]}"),
    Err(RateLimited),
  )
}

///|
test "a comment settles only on documented outcomes" {
  assert_eq(
    classify(200, created_reply("Issue", "I_1")),
    Created(id=7L, node_id="IC_7"),
  )
  // A reply naming another subject or a pull request is not a success.
  assert_eq(classify(200, created_reply("Issue", "I_2")), Unknown)
  assert_eq(classify(200, created_reply("PullRequest", "I_1")), Unknown)
  // Errors before execution (no `data` member) applied nothing.
  assert_eq(
    classify(200, "{\"errors\":[{\"type\":\"NOT_FOUND\",\"message\":\"x\"}]}"),
    Rejected(kind="NOT_FOUND"),
  )
  assert_eq(
    classify(200, "{\"errors\":[{\"message\":\"parse error\"}]}"),
    Rejected(kind="UNKNOWN"),
  )
  // A malformed error list is not a request error: it stays unknown.
  for
    body in [
      "{\"errors\":[{}]}", "{\"errors\":[{\"message\":42}]}", "{\"errors\":[{\"message\":null}]}",
      "{\"errors\":[\"text\"]}", "{\"errors\":[{\"message\":\"x\",\"type\":null}]}",
      "{\"errors\":[{\"message\":\"x\",\"type\":7}]}", "{\"errors\":{\"message\":\"x\"}}",
      "{\"errors\":[{\"message\":\"x\",\"type\":\"NOT_FOUND\"},{}]}",
    ] {
    assert_eq(classify(200, body), Unknown)
  }
  // Once execution began, or on a rate limit, the send stays unknown.
  assert_eq(
    classify(
      200, "{\"data\":{\"addComment\":null},\"errors\":[{\"type\":\"FORBIDDEN\"}]}",
    ),
    Unknown,
  )
  assert_eq(
    classify(200, "{\"data\":null,\"errors\":[{\"type\":\"NOT_FOUND\"}]}"),
    Unknown,
  )
  assert_eq(
    classify(200, "{\"errors\":[{\"type\":\"RATE_LIMITED\"}]}"),
    Unknown,
  )
  assert_eq(classify(200, "{\"errors\":[]}"), Unknown)
  assert_eq(classify(200, "not json"), Unknown)
  assert_eq(
    classify(
      200, "{\"data\":{\"addComment\":{\"commentEdge\":null,\"subject\":{\"__typename\":\"Issue\",\"id\":\"I_1\"}}}}",
    ),
    Unknown,
  )
  for status in [401, 403, 404, 410, 422] {
    assert_eq(classify(status, "{}"), Refused(status~))
  }
  assert_eq(
    classify_comment_response(
      403,
      headers([("retry-after", "60")]),
      b"{}",
      comment_limits(),
      "I_1",
    ),
    Unknown,
  )
  assert_eq(classify(429, "{}"), Unknown)
  assert_eq(classify(502, ""), Unknown)
  assert_eq(classify(201, created_reply("Issue", "I_1")), Unknown)
  assert_eq(
    classify_comment_response(
      200,
      headers([]),
      @utf8.encode(created_reply("Issue", "I_1")),
      { ..comment_limits(), max_bytes: 8, },
      "I_1",
    ),
    Unknown,
  )
}
