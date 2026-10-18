///|
fn comment_bridge_read() -> @catalog.IssueCommentsRead {
  github_issue_comments_read_begin(
    "R_original", 13.0, "o/r", 65536, 1000, 32, 10, 20, 10,
  ).unwrap()
}

///|
fn comment_bridge_subject_body() -> Bytes {
  @utf8.encode(
    "{\"data\":{\"node\":{\"__typename\":\"Repository\",\"id\":\"R_original\",\"databaseId\":13,\"nameWithOwner\":\"o/r\",\"issues\":{\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":null},\"nodes\":[{\"__typename\":\"Issue\",\"id\":\"S_original\",\"number\":7,\"updatedAt\":\"2026-10-01T00:00:00Z\"}]}}}}",
  )
}

///|
fn comment_bridge_page_body() -> Bytes {
  let repo = "{\"__typename\":\"Repository\",\"id\":\"R_original\",\"databaseId\":13,\"nameWithOwner\":\"o/r\"}"
  @utf8.encode(
    "{\"data\":{\"node\":{\"__typename\":\"Issue\",\"id\":\"S_original\",\"number\":7,\"updatedAt\":\"2026-10-01T00:00:00Z\",\"repository\":" +
    repo +
    ",\"comments\":{\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":null},\"nodes\":[{\"__typename\":\"IssueComment\",\"id\":\"IC_not_public_key\",\"fullDatabaseId\":\"9007199254740993\",\"author\":null,\"body\":\" é \",\"createdAt\":\"2026-10-01T00:00:00Z\",\"updatedAt\":\"2026-10-01T00:00:00Z\",\"repository\":" +
    repo +
    "}]}}}}",
  )
}

///|
test "comment bridge projects exactly six Source columns and never substitutes opaque identity" {
  let read = comment_bridge_read()
  github_issue_comments_read_next_request_json(read, 100).unwrap() |> ignore
  github_issue_comments_read_accept(read, comment_bridge_subject_body()).unwrap()
  assert_eq(
    github_issue_comments_read_page_json(read).unwrap(),
    "{\"page\":null}",
  )
  github_issue_comments_read_next_request_json(read, 100).unwrap() |> ignore
  github_issue_comments_read_accept(read, comment_bridge_page_body()).unwrap()
  let wire = github_issue_comments_read_page_json(read).unwrap()
  let expected : Json = {
    "page": {
      "rows": [
        {
          "id": "9007199254740993",
          "subject_number": "7",
          "author": Json::null(),
          "body": " é ",
          "created_at": "2026-10-01T00:00:00.000Z",
          "updated_at": "2026-10-01T00:00:00.000Z",
        },
      ],
    },
  }
  assert_eq(wire, expected.stringify())
  assert_false(wire.contains("IC_not_public_key"))
  assert_false(wire.contains("node_id"))
  github_issue_comments_read_close(read)
  assert_true(github_issue_comments_read_next_request_json(read, 100) is Err(_))
}

///|
test "comment bridge rejects nonnative repository numeric input and missing explicit bounds" {
  for id in [0.0, -1.0, 1.5, 2147483648.0] {
    assert_true(
      github_issue_comments_read_begin(
        "R_original", id, "o/r", 65536, 1000, 32, 10, 20, 10,
      )
      is Err(_),
    )
  }
  assert_true(
    github_issue_comments_read_begin(
      "R_original", 13.0, "o/r", 65536, 1000, 32, 10, 20, 0,
    )
    is Err(_),
  )
  assert_true(
    github_issue_comments_read_begin(
      "R_original", 13.0, "o/r", 65536, 1000, 32, 10, 0, 10,
    )
    is Err(_),
  )
}
