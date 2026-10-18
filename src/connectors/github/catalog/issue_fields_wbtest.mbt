///|
fn field_connection(
  field : String,
  values : Array[String],
  total : Int,
  next : String?,
) -> String {
  let item = if field == "assignees" { "login" } else { "name" }
  let nodes : Array[Json] = values.map(value => {
    let fields : Map[String, Json] = Map([])
    fields[item] = value.to_json()
    Json::object(fields)
  })
  (
    {
      "totalCount": total.to_json(),
      "pageInfo": {
        "hasNextPage": (next is Some(_)).to_json(),
        "endCursor": match next {
          Some(value) => value.to_json()
          None => Json::null()
        },
      },
      "nodes": nodes.to_json(),
    } : Json).stringify()
}

///|
fn fields_original() -> String {
  graphql_node(
    "R_A",
    1296269,
    "octo/hello",
    "{\"hasNextPage\":false,\"endCursor\":null}",
    graphql_issue(7, [
      ("assignees", field_connection("assignees", ["a"], 3, Some("A0"))),
      ("labels", field_connection("labels", [" é "], 3, Some("L0"))),
    ]),
  )
}

///|
fn fields_read() -> IssuePageRead {
  begin_issue_page_read(
    @utf8.encode(fields_original()),
    limits(),
    5,
    "R_A",
    1296269L,
    "octo/hello",
  ).unwrap()
}

///|
fn field_response(
  field : String,
  values : Array[String],
  total : Int,
  next : String?,
) -> String {
  "{\"data\":{\"node\":{\"__typename\":\"Repository\",\"id\":\"R_A\"," +
  "\"databaseId\":1296269,\"nameWithOwner\":\"octo/hello\",\"issue\":{" +
  "\"id\":\"I_7\",\"number\":7,\"updatedAt\":\"2026-10-02T00:00:00Z\",\"" +
  field +
  "\":" +
  field_connection(field, values, total, next) +
  "}}}}"
}

///|
test "nested Issue fields finish only after exact original repository Issue and all continuations" {
  let read = fields_read()
  let request = issue_page_read_next_request(read, 100).unwrap().unwrap()
  assert_true(request.contains("query ActqlIssueAssignees("))
  let parsed = @json.parse(request) catch { _ => abort("invalid request JSON") }
  guard parsed is Object(root) else { abort("request not object") }
  let expected : Json = {
    "id": "R_A".to_json(),
    "number": Json::number(7.0),
    "first": Json::number(100.0),
    "after": "A0".to_json(),
  }
  assert_eq(root.get("variables"), Some(expected))

  issue_page_read_accept(
    read,
    @utf8.encode(field_response("assignees", ["b"], 3, Some("A1"))),
  ).unwrap()
  assert_true(
    issue_page_read_next_request(read, 100).unwrap().unwrap().contains("A1"),
  )
  issue_page_read_accept(
    read,
    @utf8.encode(field_response("assignees", ["a"], 3, None)),
  ).unwrap()
  assert_true(
    issue_page_read_next_request(read, 100)
    .unwrap()
    .unwrap()
    .contains("ActqlIssueLabels"),
  )
  issue_page_read_accept(
    read,
    @utf8.encode(field_response("labels", ["é", " é "], 3, None)),
  ).unwrap()
  assert_eq(issue_page_read_next_request(read, 100), Ok(None))
  let page = issue_page_read_finish(read).unwrap()
  assert_eq(page.rows[0].assignees, ["a", "b", "a"])
  assert_eq(page.rows[0].labels, [" é ", "é", " é "])
  assert_eq(page.pending_fields, [])
  assert_true(issue_page_read_finish(read) is Err(_))
  assert_true(issue_page_read_next_request(read, 100) is Err(_))
}

///|
test "foreign stale partial cyclic and malformed child responses close the original decoder permanently" {
  let correct = field_response("assignees", ["b", "c"], 3, None)
  for
    body in [
      correct.replace(
        old="\"databaseId\":1296269",
        new="\"databaseId\":1296270",
      ),
      correct.replace(old="\"R_A\"", new="\"R_B\""),
      correct.replace(old="octo/hello", new="other/hello"),
      correct.replace(old="\"I_7\"", new="\"I_foreign\""),
      correct.replace(old="\"number\":7", new="\"number\":8"),
      correct.replace(old="2026-10-02T00:00:00Z", new="2026-10-03T00:00:00Z"),
      field_response("assignees", ["b"], 3, None),
      field_response("assignees", ["b", "c"], 4, None),
      field_response("assignees", ["b"], 3, Some("A0")),
      field_response("labels", ["b", "c"], 3, None),
      "{\"data\":null,\"errors\":[{\"type\":\"RATE_LIMITED\"}]}",
      "{}",
    ] {
    let read = fields_read()
    assert_true(issue_page_read_accept(read, @utf8.encode(body)) is Err(_))
    // Restoring the old bytes cannot recover a refused original read.
    assert_true(issue_page_read_accept(read, @utf8.encode(correct)) is Err(_))
    assert_true(issue_page_read_next_request(read, 100) is Err(_))
    assert_true(issue_page_read_finish(read) is Err(_))
  }
}

///|
test "incomplete or retired Issue codec state never emits completed rows" {
  let read = fields_read()
  assert_true(issue_page_read_finish(read) is Err(_))
  let closed = fields_read()
  issue_page_read_close(closed)
  assert_true(issue_page_read_next_request(closed, 100) is Err(_))
  assert_true(
    issue_page_read_accept(
      closed,
      @utf8.encode(field_response("assignees", ["b", "c"], 3, None)),
    )
    is Err(_),
  )
  assert_true(issue_page_read_finish(closed) is Err(_))
}

///|
test "the original continuation decoder retains its explicit total page ceiling" {
  let read = begin_issue_page_read(
    @utf8.encode(fields_original()),
    limits(),
    2,
    "R_A",
    1296269L,
    "octo/hello",
  ).unwrap()
  issue_page_read_accept(
    read,
    @utf8.encode(field_response("assignees", ["b"], 3, Some("A1"))),
  ).unwrap()
  assert_eq(
    issue_page_read_accept(
      read,
      @utf8.encode(field_response("assignees", ["a"], 3, None)),
    ),
    Err(BudgetExceeded),
  )
  assert_true(issue_page_read_finish(read) is Err(_))
}
