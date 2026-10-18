///|
fn comment_read_subject(kind? : String = "Issue") -> IssueCommentSubject {
  {
    node_id: "S_original",
    number: 7L,
    native_type: kind,
    updated_at: "2026-10-01T00:00:00.000Z",
    repository: {
      node_id: "R_original",
      database_id: 13L,
      name_with_owner: "o/r",
    },
  }
}

///|
fn comment_read_body(
  kind? : String = "Issue",
  key? : String = "9007199254740993",
) -> String {
  let repository = "{\"__typename\":\"Repository\",\"id\":\"R_original\",\"databaseId\":13,\"nameWithOwner\":\"o/r\"}"
  "{\"data\":{\"node\":{\"__typename\":\"" +
  kind +
  "\",\"id\":\"S_original\",\"number\":7,\"updatedAt\":\"2026-10-01T00:00:00Z\",\"repository\":" +
  repository +
  ",\"comments\":{\"pageInfo\":{\"hasNextPage\":false,\"endCursor\":null},\"nodes\":[{\"__typename\":\"IssueComment\",\"id\":\"IC_opaque\",\"fullDatabaseId\":\"" +
  key +
  "\",\"databaseId\":123,\"author\":{\"login\":\" é \"},\"body\":\"  é\\n é  \",\"createdAt\":\"2026-09-30T12:00:00Z\",\"updatedAt\":\"2026-10-01T00:00:00Z\",\"repository\":" +
  repository +
  "}]}}}}"
}

///|
fn read_comment_page(
  body : String,
  subject? : IssueCommentSubject = comment_read_subject(),
) -> Result[GraphqlIssueCommentPage, GraphqlResponseIssue] {
  project_issue_comments_response(
    @utf8.encode(body),
    { max_bytes: 65536, max_nodes: 1000, max_depth: 32, max_rows: 100, },
    subject,
  )
}

///|
test "comment Source preserves numeric key separately from opaque ID and exact text" {
  for kind in ["Issue", "PullRequest"] {
    let page = read_comment_page(
      comment_read_body(kind~),
      subject=comment_read_subject(kind~),
    ).unwrap()
    assert_eq(page.rows.length(), 1)
    let row = page.rows[0]
    assert_eq(row.id, 9007199254740993L)
    assert_eq(row.node_id, "IC_opaque")
    assert_eq(row.subject_number, 7L)
    assert_eq(row.author, Some(" é "))
    assert_eq(row.body, "  é\n é  ")
    assert_eq(row.created_at, "2026-09-30T12:00:00.000Z")
    assert_false(page.has_next_page)
    assert_eq(page.end_cursor, None)
  }
}

///|
test "comment Source BigInt uses only canonical positive Signed64 text with no databaseId fallback" {
  let maximum = read_comment_page(comment_read_body(key="9223372036854775807")).unwrap()
  assert_eq(maximum.rows[0].id, 9223372036854775807L)
  for
    key in [
      "0", "-1", "01", "+1", "1.0", "1e2", "9223372036854775808", " 7 ", "IC_opaque",
      "",
    ] {
    assert_true(read_comment_page(comment_read_body(key~)) is Err(_))
  }
  for replacement in ["null", "7", "true"] {
    assert_true(
      read_comment_page(
        comment_read_body().replace(
          old="\"fullDatabaseId\":\"9007199254740993\"",
          new="\"fullDatabaseId\":" + replacement,
        ),
      )
      is Err(_),
    )
  }
  assert_true(
    read_comment_page(
      comment_read_body().replace(
        old="\"fullDatabaseId\":\"9007199254740993\",",
        new="",
      ),
    )
    is Err(_),
  )
}

///|
test "comment Source nullable author and empty body are explicit observations" {
  let body = comment_read_body()
    .replace(old="{\"login\":\" é \"}", new="null")
    .replace(old="\"  é\\n é  \"", new="\"\"")
  let row = read_comment_page(body).unwrap().rows[0]
  assert_eq(row.author, None)
  assert_eq(row.body, "")
  assert_true(
    read_comment_page(body.replace(old="\"author\":null,", new="")) is Err(_),
  )
  assert_true(
    read_comment_page(body.replace(old="\"author\":null", new="\"author\":{}"))
    is Err(_),
  )
  assert_true(
    read_comment_page(body.replace(old="\"body\":\"\"", new="\"body\":null"))
    is Err(_),
  )
}

///|
test "comment Source refuses changed original subject repository and native type" {
  for
    body in [
      comment_read_body().replace(
        old="\"id\":\"S_original\"",
        new="\"id\":\"S_foreign\"",
      ),
      comment_read_body().replace(old="\"number\":7", new="\"number\":8"),
      comment_read_body().replace(
        old="\"updatedAt\":\"2026-10-01T00:00:00Z\"",
        new="\"updatedAt\":\"2026-10-02T00:00:00Z\"",
      ),
      comment_read_body().replace(old="\"R_original\"", new="\"R_foreign\""),
      comment_read_body().replace(
        old="\"databaseId\":13",
        new="\"databaseId\":14",
      ),
      comment_read_body().replace(old="\"o/r\"", new="\"o/other\""),
      comment_read_body(kind="PullRequest"),
      comment_read_body().replace(
        old="\"IssueComment\"",
        new="\"PullRequestReviewComment\"",
      ),
    ] {
    assert_true(read_comment_page(body) is Err(_))
  }
}

///|
test "comment Source cursor and independent byte row bounds never imply completion" {
  let more = comment_read_body().replace(
    old="\"hasNextPage\":false,\"endCursor\":null",
    new="\"hasNextPage\":true,\"endCursor\":\" next-original \"",
  )
  let page = read_comment_page(more).unwrap()
  assert_true(page.has_next_page)
  assert_eq(page.end_cursor, Some(" next-original "))
  assert_true(
    read_comment_page(more.replace(old="\" next-original \"", new="null"))
    is Err(MissingCursor),
  )
  assert_true(
    project_issue_comments_response(
      @utf8.encode(more),
      { max_bytes: 20, max_nodes: 1000, max_depth: 32, max_rows: 100, },
      comment_read_subject(),
    )
    is Err(BudgetExceeded),
  )
  assert_true(
    project_issue_comments_response(
      @utf8.encode(more),
      { max_bytes: 65536, max_nodes: 1000, max_depth: 32, max_rows: 0, },
      comment_read_subject(),
    )
    is Err(_),
  )
  assert_true(
    read_comment_page("{\"errors\":[{\"type\":\"RATE_LIMITED\"}],\"data\":{}}")
    is Err(RateLimited),
  )
  assert_true(
    read_comment_page("{\"errors\":[{\"type\":\"FORBIDDEN\"}],\"data\":{}}")
    is Err(_),
  )
}

///|
test "comment Source request chooses closed native subject and fixed read query only" {
  for kind in ["Issue", "PullRequest"] {
    let request = issue_comments_request(
      comment_read_subject(kind~),
      100,
      Some("cursor-original"),
    ).unwrap()
    let json = @json.parse(request) catch { _ => abort("invalid request JSON") }
    assert_eq(json["variables"]["id"], Json::string("S_original"))
    assert_eq(json["variables"]["first"], Json::number(100))
    assert_true(request.contains("comments(first: $first"))
    assert_true(request.contains("fullDatabaseId"))
    assert_false(request.contains("mutation"))
  }
  assert_true(
    issue_comments_request(comment_read_subject(kind="Issue { evil }"), 1, None)
    is Err(InvalidState),
  )
  assert_true(
    issue_comments_request(comment_read_subject(), 101, None)
    is Err(InvalidPageSize),
  )
  assert_true(
    issue_comments_request(comment_read_subject(), 1, Some(""))
    is Err(InvalidCursor),
  )
}
