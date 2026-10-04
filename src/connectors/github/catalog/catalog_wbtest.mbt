///|
fn headers(entries : Array[(String, String)]) -> HeaderObservation {
  { entries, }
}

///|
fn limits() -> PageLimits {
  { max_bytes: 100000, max_nodes: 10000, max_depth: 16, max_rows: 100, }
}

///|
fn issue_json(number : Int, extra : String) -> String {
  let n = number.to_string()
  "{\"number\":" +
  n +
  ",\"node_id\":\"I_" +
  n +
  "\",\"title\":\"t" +
  n +
  "\"," +
  "\"state\":\"open\",\"body\":null,\"user\":{\"login\":\"octo\"},\"comments\":2," +
  "\"created_at\":\"2026-10-01T00:00:00Z\",\"updated_at\":\"2026-10-02T00:00:00Z\"," +
  "\"closed_at\":null,\"labels\":[]" +
  extra +
  "}"
}

///|
test "request headers state the API version and user agent, never a secret" {
  assert_eq(request_headers(), [
    ("accept", "application/vnd.github+json"),
    ("x-github-api-version", "2026-03-10"),
    ("user-agent", "actql-github-connector/0.1"),
  ])
  for header in request_headers() {
    assert_true(header.0 != "authorization")
  }
}

///|
test "rate limits are 429, or 403 with a rate-limit basis; other 403 is denial" {
  assert_eq(
    classify_failure(
      429,
      headers([("retry-after", "30"), ("x-ratelimit-resource", "core")]),
    ),
    RateLimited({
      retry_after_seconds: Some(30L),
      reset_epoch_seconds: None,
      remaining: None,
      resource: Some("core"),
    }),
  )
  assert_eq(
    classify_failure(
      403,
      headers([
        ("x-ratelimit-remaining", "0"),
        ("x-ratelimit-reset", "1790000000"),
      ]),
    ),
    RateLimited({
      retry_after_seconds: None,
      reset_epoch_seconds: Some(1790000000L),
      remaining: Some(0L),
      resource: None,
    }),
  )
  assert_eq(
    classify_failure(403, headers([("x-ratelimit-remaining", "4999")])),
    PermissionDenied,
  )
  assert_eq(classify_failure(403, headers([])), PermissionDenied)
  assert_eq(classify_failure(401, headers([])), PermissionDenied)
  assert_eq(classify_failure(404, headers([])), NotFound)
  assert_eq(classify_failure(410, headers([])), Gone)
  assert_eq(classify_failure(422, headers([])), Unprocessable)
  assert_eq(classify_failure(503, headers([])), ProviderUnavailable)
  assert_eq(classify_failure(302, headers([])), Unexpected(302))
  // A malformed basis is absent, not zero.
  assert_eq(
    classify_failure(403, headers([("x-ratelimit-remaining", "-1")])),
    PermissionDenied,
  )
}

///|
test "next page stays on the listing, advances, and refuses malformed links" {
  let origin = "https://api.github.com"
  let path = "/repos/o/r/issues"
  let next = "<https://api.github.com/repos/o/r/issues?state=open&per_page=100&page=2>; rel=\"next\", " +
    "<https://api.github.com/repos/o/r/issues?state=open&per_page=100&page=5>; rel=\"last\""
  assert_eq(
    next_page(Some(next), origin, path, 1, 2048),
    Ok(
      Some({
        path,
        query: [("state", "open"), ("per_page", "100"), ("page", "2")],
        page: 2,
      }),
    ),
  )
  // The provider stated no next page.
  assert_eq(next_page(None, origin, path, 1, 2048), Ok(None))
  assert_eq(
    next_page(
      Some("<https://api.github.com/repos/o/r/issues?page=1>; rel=\"prev\""),
      origin,
      path,
      2,
      2048,
    ),
    Ok(None),
  )
  assert_eq(
    next_page(
      Some("<https://evil.example/repos/o/r/issues?page=2>; rel=\"next\""),
      origin,
      path,
      1,
      2048,
    ),
    Err(ForeignOrigin),
  )
  assert_eq(
    next_page(
      Some("<https://api.github.com.evil.example/x?page=2>; rel=\"next\""),
      origin,
      path,
      1,
      2048,
    ),
    Err(ForeignOrigin),
  )
  assert_eq(
    next_page(
      Some("<https://api.github.com/repos/o/other/issues?page=2>; rel=\"next\""),
      origin,
      path,
      1,
      2048,
    ),
    Err(ForeignResource),
  )
  assert_eq(
    next_page(
      Some("<https://api.github.com/repos/o/r/issues?page=1>; rel=\"next\""),
      origin,
      path,
      1,
      2048,
    ),
    Err(NonAdvancingPage),
  )
  assert_eq(next_page(Some(next), origin, path, 1, 20), Err(LocatorTooLong))
  for
    malformed in [
      "https://api.github.com/repos/o/r/issues?page=2; rel=\"next\"", "<https://api.github.com/repos/o/r/issues?page=2>; title=\"x\"",
      "<https://api.github.com/repos/o/r/issues>; rel=\"next\"", "<https://api.github.com/repos/o/r/issues?page=x>; rel=\"next\"",
      "<https://api.github.com/repos/o/r/issues?page=2&page=3>; rel=\"next\"", "<https://api.github.com/repos/o/r/issues?q=a%20b&page=2>; rel=\"next\"",
      "<https://api.github.com/repos/o/r/issues?page=2>; rel=\"next\", <https://api.github.com/repos/o/r/issues?page=3>; rel=\"next\"",
    ] {
    assert_eq(
      next_page(Some(malformed), origin, path, 1, 2048),
      Err(MalformedLink),
    )
  }
}

///|
test "issue pages exclude pull requests and keep null distinct from omission" {
  let body = "[" +
    issue_json(1, "") +
    "," +
    issue_json(2, ",\"pull_request\":{\"url\":\"x\"}") +
    "," +
    issue_json(3, "") +
    "]"
  let page = project_issue_page(@utf8.encode(body), limits()).unwrap()
  assert_eq(page.provider_items, 3)
  assert_eq(page.excluded_pull_requests, 1)
  assert_eq(page.rows.map(row => row.number), [1L, 3L])
  assert_eq(page.rows[0], {
    number: 1L,
    node_id: "I_1",
    title: "t1",
    state: "open",
    body: None,
    author: Some("octo"),
    comments: 2L,
    created_at: "2026-10-01T00:00:00Z",
    updated_at: "2026-10-02T00:00:00Z",
    closed_at: None,
  })
  // An empty page is a page.
  assert_eq(
    project_issue_page(@utf8.encode("[]"), limits()),
    Ok({ rows: [], excluded_pull_requests: 0, provider_items: 0, }),
  )
  // Omitting a nullable field is not the same as null.
  let omitted = "[{\"number\":1,\"node_id\":\"I\",\"title\":\"t\",\"state\":\"open\",\"user\":null," +
    "\"comments\":0,\"created_at\":\"a\",\"updated_at\":\"b\",\"closed_at\":null}]"
  assert_eq(
    project_issue_page(@utf8.encode(omitted), limits()),
    Err(MissingRequiredField("body")),
  )
  let null_title = issue_json(1, "").replace(
    old="\"title\":\"t1\"",
    new="\"title\":null",
  )
  assert_eq(
    project_issue_page(@utf8.encode("[" + null_title + "]"), limits()),
    Err(NullRequiredField("title")),
  )
  let bad_state = issue_json(1, "").replace(
    old="\"state\":\"open\"",
    new="\"state\":\"draft\"",
  )
  assert_eq(
    project_issue_page(@utf8.encode("[" + bad_state + "]"), limits()),
    Err(InvalidField("state")),
  )
  assert_eq(
    project_issue_page(@utf8.encode("{\"message\":\"x\"}"), limits()),
    Err(InvalidResponse),
  )
  assert_eq(
    project_issue_page(@utf8.encode("[" + issue_json(1, "") + "]"), {
      ..limits(),
      max_rows: 0,
    }),
    Err(InvalidLimits),
  )
  assert_eq(
    project_issue_page(
      @utf8.encode("[" + issue_json(1, "") + "," + issue_json(2, "") + "]"),
      { ..limits(), max_rows: 1, },
    ),
    Err(BudgetExceeded),
  )
}

///|
test "comment creation settles only on documented outcomes" {
  let created = @utf8.encode(
    "{\"id\":7,\"node_id\":\"IC_7\",\"body\":\"hello\",\"user\":{\"login\":\"octo\"}}",
  )
  assert_eq(
    classify_comment_response(201, headers([]), created, 10000),
    Created(id=7L, node_id="IC_7"),
  )
  for status in [401, 403, 404, 410, 422] {
    assert_eq(
      classify_comment_response(status, headers([]), b"{}", 10000),
      Refused(status~),
    )
  }
  // A lost or ambiguous reply stays unknown: no inference from content.
  assert_eq(
    classify_comment_response(201, headers([]), b"{\"id\":7}", 10000),
    Unknown,
  )
  assert_eq(
    classify_comment_response(201, headers([]), b"not json", 10000),
    Unknown,
  )
  assert_eq(classify_comment_response(201, headers([]), created, 4), Unknown)
  assert_eq(
    classify_comment_response(
      403,
      headers([("retry-after", "60")]),
      b"{}",
      10000,
    ),
    Unknown,
  )
  assert_eq(classify_comment_response(429, headers([]), b"{}", 10000), Unknown)
  assert_eq(classify_comment_response(502, headers([]), b"", 10000), Unknown)
  assert_eq(
    classify_comment_response(200, headers([]), created, 10000),
    Unknown,
  )
}
