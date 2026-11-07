// Continuations of an Issue's nested connections belong to that exact
// repository and Issue observation. This is codec state only: the Site still
// owns every authorized request, received-byte charge and cleanup duty.

///|
pub struct IssuePageRead {
  page : GraphqlIssuePage
  pull_request : Bool
  limits : PageLimits
  max_pages : Int
  mut pages : Int
  pending : Array[IssueFieldProgress]
  mut index : Int
  mut closed : Bool
}

///|
pub struct IssueFieldProgress {
  row_index : Int
  field : String
  total_count : Int64
  mut after : String
  seen : Array[String]
}

///|
/// Admit the original outer page without exposing an incomplete row result.
pub fn begin_issue_page_read(
  body : Bytes,
  limits : PageLimits,
  max_pages : Int,
  expected_node_id : String,
  expected_database_id : Int64,
  expected_name_with_owner : String,
) -> Result[IssuePageRead, GraphqlResponseIssue] {
  if max_pages < 1 {
    return Err(InvalidResponse)
  }
  let page = match
    project_issues_response(
      body, limits, expected_node_id, expected_database_id, expected_name_with_owner,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let pending = page.pending_fields.map(field => {
    row_index: field.row_index,
    field: field.field,
    total_count: field.total_count,
    after: field.after,
    seen: [field.after],
  })
  Ok({
    page,
    pull_request: false,
    limits,
    max_pages,
    pages: 1,
    pending,
    index: 0,
    closed: false,
  })
}

///|
fn issue_field_query(field : String, pull_request : Bool) -> String {
  // These are fixed read-only documents, never caller-supplied query text.
  if pull_request {
    return if field == "assignees" {
      "query ActqlPullRequestAssignees($id: ID!, $number: Int!, $first: Int!, $after: String!) { node(id: $id) { __typename ... on Repository { id databaseId nameWithOwner pullRequest(number: $number) { __typename id number updatedAt assignees(first: $first, after: $after) { totalCount pageInfo { hasNextPage endCursor } nodes { login } } } } } }"
    } else {
      "query ActqlPullRequestLabels($id: ID!, $number: Int!, $first: Int!, $after: String!) { node(id: $id) { __typename ... on Repository { id databaseId nameWithOwner pullRequest(number: $number) { __typename id number updatedAt labels(first: $first, after: $after) { totalCount pageInfo { hasNextPage endCursor } nodes { name } } } } } }"
    }
  }
  if field == "assignees" {
    "query ActqlIssueAssignees($id: ID!, $number: Int!, $first: Int!, $after: String!) { node(id: $id) { __typename ... on Repository { id databaseId nameWithOwner issue(number: $number) { id number updatedAt assignees(first: $first, after: $after) { totalCount pageInfo { hasNextPage endCursor } nodes { login } } } } } }"
  } else {
    "query ActqlIssueLabels($id: ID!, $number: Int!, $first: Int!, $after: String!) { node(id: $id) { __typename ... on Repository { id databaseId nameWithOwner issue(number: $number) { id number updatedAt labels(first: $first, after: $after) { totalCount pageInfo { hasNextPage endCursor } nodes { name } } } } } }"
  }
}

///|
/// The next fixed request, or None only after all nested fields are complete.
/// A repository-scoped Issue number avoids following an Issue after transfer.
pub fn issue_page_read_next_request(
  read : IssuePageRead,
  first : Int,
) -> Result[String?, GraphqlResponseIssue] {
  if read.closed || first < 1 || first > 100 {
    return Err(InvalidResponse)
  }
  if read.index == read.pending.length() {
    return Ok(None)
  }
  let next = read.pending[read.index]
  if next.after.is_empty() || next.after.length() > 1024 {
    read.closed = true
    return Err(MissingCursor)
  }
  let row = read.page.rows[next.row_index]
  Ok(
    Some(
      (
        {
          "query": issue_field_query(next.field, read.pull_request).to_json(),
          "variables": {
            "id": read.page.repository.node_id.to_json(),
            // The original GraphQL Int was checked before this conversion.
            "number": row.number.to_int().to_json(),
            "first": first.to_json(),
            "after": next.after.to_json(),
          },
        } : Json).stringify(),
    ),
  )
}

///|
/// Consume one received continuation. Any refusal closes this codec state;
/// a second response cannot repair it or replace the original observation.
pub fn issue_page_read_accept(
  read : IssuePageRead,
  body : Bytes,
) -> Result[Unit, GraphqlResponseIssue] {
  if read.closed || read.index >= read.pending.length() {
    return Err(InvalidResponse)
  }
  read.closed = true
  if read.pages >= read.max_pages {
    return Err(BudgetExceeded)
  }
  let next = read.pending[read.index]
  let row = read.page.rows[next.row_index]
  let data = match admit_body(body, read.limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let node = match @decode.field(data, "node") {
    Present(value) =>
      match @decode.open_object(value) {
        Ok(object) => object
        Err(_) => return Err(InvalidResponse)
      }
    ExplicitNull => return Err(RepositoryUnavailable)
    Missing => return Err(InvalidResponse)
  }
  let repository = match repository_of(node) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if repository.database_id != read.page.repository.database_id {
    return Err(ForeignRepository)
  }
  if repository.node_id != read.page.repository.node_id {
    return Err(IdRepresentationChanged)
  }
  if repository.name_with_owner != read.page.repository.name_with_owner {
    return Err(BindingChanged)
  }
  let subject = if read.pull_request { "pullRequest" } else { "issue" }
  let issue = match @decode.field(node, subject) {
    Present(value) =>
      match @decode.open_object(value) {
        Ok(object) => object
        Err(_) => return Err(InvalidResponse)
      }
    ExplicitNull => return Err(SubjectUnavailable)
    Missing => return Err(InvalidResponse)
  }
  if read.pull_request {
    match required_text(issue, "__typename") {
      Ok("PullRequest") => ()
      Ok(other) => return Err(WrongType(other))
      Err(issue) => return Err(Row(issue))
    }
  }
  guard required_text(issue, "id") is Ok(id) &&
    id == row.node_id &&
    required_integer(issue, "number", body, read.limits.max_bytes) is Ok(number) &&
    number == row.number else {
    return Err(ForeignSubject)
  }
  guard graphql_timestamp(issue, "updatedAt", false) is Ok(Some(updated)) &&
    updated == row.updated_at else {
    return Err(BindingChanged)
  }
  let (values, after, total) = match
    graphql_text_connection(
      issue,
      next.field,
      if next.field == "assignees" {
        "login"
      } else {
        "name"
      },
      body,
      read.limits.max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Row(issue))
  }
  let original = if next.field == "assignees" {
    row.assignees
  } else {
    row.labels
  }
  let count = original.length().to_int64() + values.length().to_int64()
  if total != next.total_count || count > total {
    return Err(BindingChanged)
  }
  match after {
    Some(cursor) => {
      if cursor.length() > 1024 || next.seen.contains(cursor) || count >= total {
        return Err(MissingCursor)
      }
      next.after = cursor
      next.seen.push(cursor)
    }
    None => {
      if count != total {
        return Err(BindingChanged)
      }
      read.index += 1
    }
  }
  // Preserve provider order, duplicates, empty strings and original text.
  original.append(values)
  read.pages += 1
  read.closed = false
  Ok(())
}

///|
/// Complete rows are released once, after every requested field is complete.
pub fn issue_page_read_finish(
  read : IssuePageRead,
) -> Result[GraphqlIssuePage, GraphqlResponseIssue] {
  if read.closed || read.index != read.pending.length() {
    return Err(InvalidResponse)
  }
  read.closed = true
  Ok({ ..read.page, pending_fields: [], })
}

///|
/// Retire only codec aliases; this does not acknowledge physical retirement.
pub fn issue_page_read_close(read : IssuePageRead) -> Unit {
  read.closed = true
}

///|
// The fixed read-only documents remain the original request-builder inputs.
pub fn source_read_query_units() -> Int {
  let mut units = Int::max(issues_query.length(), pull_requests_query.length())
  for field in ["assignees", "labels"] {
    for pull_request in [false, true] {
      units = Int::max(units, issue_field_query(field, pull_request).length())
    }
  }
  Int::max(units, comment_read_query_units())
}
