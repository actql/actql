///|
fn page_limits() -> PageLimits {
  { max_bytes: 100000, max_nodes: 10000, max_depth: 32, max_rows: 100, }
}

///|
fn graphql_node(
  id : String,
  database_id : Int,
  name : String,
  page_info : String,
  nodes : String,
) -> String {
  "{\"data\":{\"node\":{\"__typename\":\"Repository\",\"id\":\"" +
  id +
  "\",\"databaseId\":" +
  database_id.to_string() +
  ",\"nameWithOwner\":\"" +
  name +
  "\",\"issues\":{\"pageInfo\":" +
  page_info +
  ",\"nodes\":[" +
  nodes +
  "]}}}}"
}

///|
/// One GraphQL Issue node; `fields` replaces the named defaults.
fn graphql_issue(number : Int, fields : Array[(String, String)]) -> String {
  let n = number.to_string()
  let values : Array[(String, String)] = [
    ("number", n),
    ("id", "\"I_" + n + "\""),
    ("title", "\"t" + n + "\""),
    ("state", "\"OPEN\""),
    ("body", "\"\""),
    ("author", "{\"login\":\"octo\"}"),
    ("comments", "{\"totalCount\":3}"),
    ("createdAt", "\"2026-10-01T00:00:00Z\""),
    ("updatedAt", "\"2026-10-02T00:00:00Z\""),
    ("closedAt", "null"),
  ]
  let parts = values.map(entry => {
    let mut value = entry.1
    for replacement in fields {
      if replacement.0 == entry.0 {
        value = replacement.1
      }
    }
    "\"" + entry.0 + "\":" + value
  })
  "{" + parts.join(",") + "}"
}

///|
fn project(body : String) -> Result[GraphqlIssuePage, GraphqlResponseIssue] {
  project_issues_response(
    @utf8.encode(body),
    page_limits(),
    "R_A",
    1296269L,
    "octo/hello",
  )
}

///|
test "requests carry only the fixed read query and typed variables" {
  let body = issues_request("R_A", 100, None, {
    state: "all",
    labels: [],
    since: None,
  }).unwrap()
  let variables : Json = {
    "id": "R_A".to_json(),
    "first": Json::number(100.0),
    "after": Json::null(),
    "states": Json::null(),
    "labels": Json::null(),
    "since": Json::null(),
  }
  let expected : Json = {
    "query": issues_query.to_json(),
    "variables": variables,
  }
  assert_eq(body, expected.stringify())
  assert_true(!issues_query.contains("mutation"))
  assert_true(issues_query.has_prefix("query ActqlIssues("))
  assert_true(issues_query.contains("node(id: $id)"))
  assert_true(!repository_query.contains("mutation"))
  let filtered = issues_request("R_A", 50, Some("Y3Vyc29y"), {
    state: "open",
    labels: ["\u{65E5}\u{672C}"],
    since: Some("2026-10-01T00:00:00Z"),
  }).unwrap()
  assert_true(filtered.contains("\"states\":[\"OPEN\"]"))
  assert_true(filtered.contains("\"after\":\"Y3Vyc29y\""))
  assert_true(filtered.contains("\"since\":\"2026-10-01T00:00:00Z\""))
  let all : IssueFilters = { state: "all", labels: [], since: None, }
  assert_eq(issues_request("", 10, None, all), Err(InvalidNodeId))
  assert_eq(issues_request("R_A", 0, None, all), Err(InvalidPageSize))
  assert_eq(issues_request("R_A", 101, None, all), Err(InvalidPageSize))
  assert_eq(issues_request("R_A", 10, Some(""), all), Err(InvalidCursor))
  assert_eq(
    issues_request("R_A", 10, None, { ..all, state: "draft", }),
    Err(InvalidState),
  )
  assert_eq(
    issues_request("R_A", 10, None, { ..all, since: Some("yesterday"), }),
    Err(InvalidSince),
  )
}

///|
test "a page of the published repository maps to the existing Issue rows" {
  let page = project(
    graphql_node(
      "R_A",
      1296269,
      "octo/hello",
      "{\"hasNextPage\":true,\"endCursor\":\"c1\"}",
      graphql_issue(1, []) +
      "," +
      graphql_issue(2, [
        ("author", "null"),
        ("body", "\"text\""),
        ("state", "\"CLOSED\""),
        ("closedAt", "\"2026-10-03T00:00:00Z\""),
      ]),
    ),
  ).unwrap()
  assert_eq(page.has_next_page, true)
  assert_eq(page.end_cursor, Some("c1"))
  assert_eq(page.repository, {
    node_id: "R_A",
    database_id: 1296269L,
    name_with_owner: "octo/hello",
  })
  assert_eq(page.rows[0], {
    number: 1L,
    node_id: "I_1",
    title: "t1",
    state: "open",
    body: Some(""),
    author: Some("octo"),
    comments: 3L,
    created_at: "2026-10-01T00:00:00.000Z",
    updated_at: "2026-10-02T00:00:00.000Z",
    closed_at: None,
  })
  assert_eq(page.rows[1].state, "closed")
  assert_eq(page.rows[1].body, Some("text"))
  assert_eq(page.rows[1].author, None)
  assert_eq(page.rows[1].closed_at, Some("2026-10-03T00:00:00.000Z"))
  let last = project(
    graphql_node(
      "R_A", 1296269, "octo/hello", "{\"hasNextPage\":false,\"endCursor\":null}",
      "",
    ),
  ).unwrap()
  assert_eq(
    (last.has_next_page, last.end_cursor, last.rows.length()),
    (false, None, 0),
  )
}

///|
test "another repository, ID representation, binding or type is refused" {
  let info = "{\"hasNextPage\":false,\"endCursor\":null}"
  assert_eq(
    project(graphql_node("R_B", 424242, "octo/hello", info, "")),
    Err(ForeignRepository),
  )
  // The same repository (database id) under another node ID spelling needs
  // an explicit re-publication; it is not rewritten during a read.
  assert_eq(
    project(graphql_node("R_A_next", 1296269, "octo/hello", info, "")),
    Err(IdRepresentationChanged),
  )
  assert_eq(
    project(graphql_node("R_A", 1296269, "octo/renamed", info, "")),
    Err(BindingChanged),
  )
  assert_eq(
    project(
      "{\"data\":{\"node\":{\"__typename\":\"User\",\"id\":\"R_A\",\"databaseId\":1296269}}}",
    ),
    Err(WrongType("User")),
  )
  // Gone or no longer readable: never a name fallback.
  assert_eq(project("{\"data\":{\"node\":null}}"), Err(RepositoryUnavailable))
}

///|
test "HTTP 200 errors, partial data and missing cursors are never a page" {
  assert_eq(
    project(
      "{\"data\":null,\"errors\":[{\"type\":\"RATE_LIMITED\",\"message\":\"x\"}]}",
    ),
    Err(RateLimited),
  )
  assert_eq(
    project(
      graphql_node(
        "R_A",
        1296269,
        "octo/hello",
        "{\"hasNextPage\":false,\"endCursor\":null}",
        graphql_issue(1, []),
      ).replace(
        old="{\"data\"",
        new="{\"errors\":[{\"type\":\"FORBIDDEN\",\"message\":\"x\"}],\"data\"",
      ),
    ),
    Err(Errors("FORBIDDEN")),
  )
  assert_eq(project("{\"errors\":[]}"), Err(InvalidResponse))
  assert_eq(
    project(
      graphql_node(
        "R_A", 1296269, "octo/hello", "{\"hasNextPage\":true,\"endCursor\":null}",
        "",
      ),
    ),
    Err(MissingCursor),
  )
  assert_eq(
    project(
      graphql_node(
        "R_A",
        1296269,
        "octo/hello",
        "{\"hasNextPage\":false,\"endCursor\":null}",
        graphql_issue(1, [("createdAt", "\"2026-10-01T00:00:00+00:00\"")]),
      ),
    ),
    Err(Row(InvalidField("createdAt"))),
  )
  assert_eq(
    project(
      graphql_node(
        "R_A", 1296269, "octo/hello", "{\"hasNextPage\":false,\"endCursor\":null}",
        "null",
      ),
    ),
    Err(InvalidResponse),
  )
}

///|
test "a publication lookup states the repository now" {
  assert_eq(
    project_repository_response(
      @utf8.encode(
        "{\"data\":{\"repository\":{\"__typename\":\"Repository\",\"id\":\"R_A\",\"databaseId\":1296269,\"nameWithOwner\":\"octo/hello\"}}}",
      ),
      page_limits(),
    ),
    Ok({ node_id: "R_A", database_id: 1296269L, name_with_owner: "octo/hello", }),
  )
  assert_eq(
    project_repository_response(
      @utf8.encode("{\"data\":{\"repository\":null}}"),
      page_limits(),
    ),
    Err(RepositoryUnavailable),
  )
  assert_true(
    repository_request("octo", "hello").contains(
      "\"variables\":{\"owner\":\"octo\",\"name\":\"hello\"}",
    ),
  )
}

///|
test "the body is kept exactly: empty, text, missing, null or invalid" {
  let one = (fields : Array[(String, String)]) => {
    project(
      graphql_node(
        "R_A",
        1296269,
        "octo/hello",
        "{\"hasNextPage\":false,\"endCursor\":null}",
        graphql_issue(1, fields),
      ),
    )
  }
  assert_eq(one([("body", "\"\"")]).unwrap().rows[0].body, Some(""))
  assert_eq(one([("body", "\"text\"")]).unwrap().rows[0].body, Some("text"))
  assert_eq(one([("body", "null")]), Err(Row(NullRequiredField("body"))))
  assert_eq(one([("body", "7")]), Err(Row(InvalidField("body"))))
  let missing = graphql_issue(1, []).replace(old="\"body\":\"\",", new="")
  assert_eq(
    project(
      graphql_node(
        "R_A", 1296269, "octo/hello", "{\"hasNextPage\":false,\"endCursor\":null}",
        missing,
      ),
    ),
    Err(Row(MissingRequiredField("body"))),
  )
}
