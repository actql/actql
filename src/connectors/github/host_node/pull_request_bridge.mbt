// Pure typed projection from the existing GitHub Catalog Owner. Exchanges,
// original Credential membership, accounting and cleanup stay at the Site.

///|
#export_name("githubPullRequestsRequestJson")
pub fn github_pull_requests_request_json(
  node_id : String,
  first : Int,
  has_after : Bool,
  after : String,
  state : String,
  labels : Array[String],
) -> String {
  let value : Json = match
    @catalog.pull_requests_request(
      node_id,
      first,
      if has_after {
        Some(after)
      } else {
        None
      },
      { state, labels, },
    ) {
    Ok(body) => { "body": body.to_json() }
    Err(issue) => {
      let name = match issue {
        InvalidNodeId => "InvalidNodeId"
        InvalidPageSize => "InvalidPageSize"
        InvalidCursor => "InvalidCursor"
        InvalidState => "InvalidState"
        InvalidLabel => "InvalidLabel"
        InvalidSince => "InvalidSince"
      }
      { "refused": name.to_json() }
    }
  }
  value.stringify()
}

///|
#export_name("githubPullRequestPageReadBegin")
pub fn github_pull_request_page_read_begin(
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_pages : Int,
  expected_node_id : String,
  expected_database_id : Double,
  expected_name_with_owner : String,
) -> Result[@catalog.PullRequestPageRead, @catalog.GraphqlResponseIssue] {
  @catalog.begin_pull_request_page_read(
    body,
    { max_bytes, max_nodes, max_depth, max_rows, },
    max_pages,
    expected_node_id,
    expected_database_id.to_int64(),
    expected_name_with_owner,
  )
}

///|
#export_name("githubPullRequestPageReadNextRequestJson")
pub fn github_pull_request_page_read_next_request_json(
  read : @catalog.PullRequestPageRead,
  first : Int,
) -> Result[String, @catalog.GraphqlResponseIssue] {
  @catalog.pull_request_page_read_next_request(read, first).map(request => {
    ({ "body": optional_text(request) } : Json).stringify()
  })
}

///|
#export_name("githubPullRequestPageReadAccept")
pub fn github_pull_request_page_read_accept(
  read : @catalog.PullRequestPageRead,
  body : Bytes,
) -> Result[Unit, @catalog.GraphqlResponseIssue] {
  @catalog.pull_request_page_read_accept(read, body)
}

///|
fn pull_request_row_json(row : @catalog.PullRequestRow) -> Json {
  let common = row.common
  let native = row.native
  {
    "number": common.number.to_string().to_json(),
    "node_id": common.node_id.to_json(),
    "title": common.title.to_json(),
    "state": common.state.to_json(),
    "state_reason": optional_text(common.state_reason),
    "body": optional_text(common.body),
    "author": optional_text(common.author),
    "assignees": common.assignees.to_json(),
    "labels": common.labels.to_json(),
    "url": common.url.to_json(),
    "comments": common.comments.to_string().to_json(),
    "milestone": optional_text(common.milestone),
    "created_at": common.created_at.to_json(),
    "updated_at": common.updated_at.to_json(),
    "closed_at": optional_text(common.closed_at),
    "base": native.base.to_json(),
    "head": native.head.to_json(),
    "draft": native.draft.to_json(),
    "mergeable": match native.mergeable {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "merged_at": optional_text(native.merged_at),
    "merged_by": optional_text(native.merged_by),
    "review_decision": optional_text(native.review_decision),
  }
}

///|
#export_name("githubPullRequestPageReadFinishJson")
pub fn github_pull_request_page_read_finish_json(
  read : @catalog.PullRequestPageRead,
) -> Result[String, @catalog.GraphqlResponseIssue] {
  @catalog.pull_request_page_read_finish(read).map(page => {
    (
      {
        "rows": page.rows.map(pull_request_row_json).to_json(),
        "hasNextPage": page.has_next_page.to_json(),
        "endCursor": optional_text(page.end_cursor),
        "repository": graphql_repository_json(page.repository),
      } : Json).stringify()
  })
}

///|
#export_name("githubPullRequestPageReadClose")
pub fn github_pull_request_page_read_close(
  read : @catalog.PullRequestPageRead,
) -> Unit {
  @catalog.pull_request_page_read_close(read)
}
