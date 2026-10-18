///|
/// Repository-node-bound read only. Ref names survive deleted Ref objects.
pub let pull_requests_query : String = "query ActqlPullRequests($id: ID!, $first: Int!, $after: String, $states: [PullRequestState!], $labels: [String!]) { node(id: $id) { __typename ... on Repository { id databaseId nameWithOwner pullRequests(first: $first, after: $after, states: $states, labels: $labels) { pageInfo { hasNextPage endCursor } nodes { __typename number id title state body author { login } assignees(first: 100) { totalCount pageInfo { hasNextPage endCursor } nodes { login } } labels(first: 100) { totalCount pageInfo { hasNextPage endCursor } nodes { name } } comments { totalCount } milestone { title } createdAt updatedAt closedAt url baseRefName headRefName isDraft mergeable mergedAt mergedBy { login } reviewDecision } } } } }"

///|
/// Native Source states only; this does not change authored write-state inputs.
pub(all) struct PullRequestFilters {
  state : String
  labels : Array[String]
} derive(Eq, Debug)

///|
pub fn pull_requests_request(
  node_id : String,
  first : Int,
  after : String?,
  filters : PullRequestFilters,
) -> Result[String, GraphqlRequestIssue] {
  if node_id.is_empty() || node_id.length() > 256 {
    return Err(InvalidNodeId)
  }
  if first < 1 || first > 100 {
    return Err(InvalidPageSize)
  }
  if after is Some(cursor) && (cursor.is_empty() || cursor.length() > 1024) {
    return Err(InvalidCursor)
  }
  let states : Json = match filters.state {
    "open" => ["OPEN".to_json()]
    "closed" => ["CLOSED".to_json()]
    "merged" => ["MERGED".to_json()]
    "all" => Json::null()
    _ => return Err(InvalidState)
  }
  if filters.labels.length() > 20 ||
    filters.labels.any(label => label.is_empty() || label.length() > 256) {
    return Err(InvalidLabel)
  }
  Ok(
    (
      {
        "query": pull_requests_query.to_json(),
        "variables": {
          "id": node_id.to_json(),
          "first": first.to_json(),
          "after": optional_json(after),
          "states": states,
          "labels": if filters.labels.is_empty() {
            Json::null()
          } else {
            filters.labels.to_json()
          },
        },
      } : Json).stringify(),
  )
}

///|
/// Native PullRequest fields additional to the shared Issue-shaped columns.
/// These values are observations, not merge permission or mutation selectors.
pub(all) struct PullRequestNativeFields {
  base : String
  head : String
  draft : Bool
  mergeable : Bool?
  merged_at : String?
  merged_by : String?
  review_decision : String?
} derive(Eq, Debug)

///|
pub(all) struct PullRequestRow {
  common : IssueRow
  native : PullRequestNativeFields
} derive(Eq, Debug)

///|
pub(all) struct GraphqlPullRequestPage {
  repository : GraphqlRepository
  rows : Array[PullRequestRow]
  pending_fields : Array[IssueFieldContinuation]
  has_next_page : Bool
  end_cursor : String?
} derive(Eq, Debug)

///|
/// The existing nested-field state machine owns both native row families.
/// This wrapper keeps the additional fields with the very same outer page.
pub struct PullRequestPageRead {
  shared : IssuePageRead
  native : Array[PullRequestNativeFields]
}

///|
pub fn begin_pull_request_page_read(
  body : Bytes,
  limits : PageLimits,
  max_pages : Int,
  expected_node_id : String,
  expected_database_id : Int64,
  expected_name_with_owner : String,
) -> Result[PullRequestPageRead, GraphqlResponseIssue] {
  if max_pages < 1 {
    return Err(InvalidResponse)
  }
  let (page, native) = match
    project_issue_like_response(
      body, limits, expected_node_id, expected_database_id, expected_name_with_owner,
      true,
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
    shared: {
      page,
      pull_request: true,
      limits,
      max_pages,
      pages: 1,
      pending,
      index: 0,
      closed: false,
    },
    native,
  })
}

///|
pub fn pull_request_page_read_next_request(
  read : PullRequestPageRead,
  first : Int,
) -> Result[String?, GraphqlResponseIssue] {
  issue_page_read_next_request(read.shared, first)
}

///|
pub fn pull_request_page_read_accept(
  read : PullRequestPageRead,
  body : Bytes,
) -> Result[Unit, GraphqlResponseIssue] {
  issue_page_read_accept(read.shared, body)
}

///|
pub fn pull_request_page_read_finish(
  read : PullRequestPageRead,
) -> Result[GraphqlPullRequestPage, GraphqlResponseIssue] {
  issue_page_read_finish(read.shared).map(page => {
    let rows = []
    for index, common in page.rows {
      rows.push({ common, native: read.native[index], })
    }
    {
      repository: page.repository,
      rows,
      pending_fields: [],
      has_next_page: page.has_next_page,
      end_cursor: page.end_cursor,
    }
  })
}

///|
/// Codec alias retirement is not physical Source, transport or RowRun ACK.
pub fn pull_request_page_read_close(read : PullRequestPageRead) -> Unit {
  issue_page_read_close(read.shared)
}

///|
/// Admit the same original repository and requested native PullRequest shape.
/// Incomplete assignee/label fields remain pending, never complete row output.
pub fn project_pull_requests_response(
  body : Bytes,
  limits : PageLimits,
  expected_node_id : String,
  expected_database_id : Int64,
  expected_name_with_owner : String,
) -> Result[GraphqlPullRequestPage, GraphqlResponseIssue] {
  project_issue_like_response(
    body, limits, expected_node_id, expected_database_id, expected_name_with_owner,
    true,
  ).map(pair => {
    let (page, native) = pair
    let rows = []
    for index, common in page.rows {
      rows.push({ common, native: native[index], })
    }
    {
      repository: page.repository,
      rows,
      pending_fields: page.pending_fields,
      has_next_page: page.has_next_page,
      end_cursor: page.end_cursor,
    }
  })
}

///|
fn graphql_nullable_actor(
  object : @decode.ObjectView,
  name : String,
) -> Result[String?, IssuePageIssue] {
  match @decode.field(object, name) {
    Missing => Err(MissingRequiredField(name))
    ExplicitNull => Ok(None)
    Present(cursor) => {
      guard @decode.open_object(cursor) is Ok(actor) else {
        return Err(InvalidField(name))
      }
      graphql_text(actor, "login").map(value => Some(value))
    }
  }
}

///|
pub fn graphql_pull_request_fields(
  object : @decode.ObjectView,
) -> Result[PullRequestNativeFields, IssuePageIssue] {
  let base = match graphql_text(object, "baseRefName") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let head = match graphql_text(object, "headRefName") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let draft_cursor = match required_field(object, "isDraft") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let draft = match @decode.boolean(draft_cursor) {
    Ok(value) => value
    Err(_) => return Err(InvalidField("isDraft"))
  }
  let mergeable = match graphql_text(object, "mergeable") {
    Ok("MERGEABLE") => Some(true)
    Ok("CONFLICTING") => Some(false)
    Ok("UNKNOWN") => None
    Ok(_) => return Err(InvalidField("mergeable"))
    Err(issue) => return Err(issue)
  }
  let merged_at = match graphql_timestamp(object, "mergedAt", true) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let merged_by = match graphql_nullable_actor(object, "mergedBy") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let review_decision = match nullable_text(object, "reviewDecision") {
    Ok(None) => None
    Ok(Some("APPROVED")) => Some("approved")
    Ok(Some("CHANGES_REQUESTED")) => Some("changes_requested")
    Ok(Some("REVIEW_REQUIRED")) => Some("review_required")
    Ok(Some(_)) => return Err(InvalidField("reviewDecision"))
    Err(issue) => return Err(issue)
  }
  Ok({ base, head, draft, mergeable, merged_at, merged_by, review_decision, })
}
