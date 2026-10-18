// Opaque provider codec state for the original Issue page and its nested
// connections. It neither creates a credential use nor performs an exchange.

///|
#export_name("githubIssuePageReadBegin")
pub fn github_issue_page_read_begin(
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_pages : Int,
  expected_node_id : String,
  expected_database_id : Double,
  expected_name_with_owner : String,
) -> Result[@catalog.IssuePageRead, @catalog.GraphqlResponseIssue] {
  @catalog.begin_issue_page_read(
    body,
    { max_bytes, max_nodes, max_depth, max_rows, },
    max_pages,
    expected_node_id,
    expected_database_id.to_int64(),
    expected_name_with_owner,
  )
}

///|
#export_name("githubIssuePageReadNextRequestJson")
pub fn github_issue_page_read_next_request_json(
  read : @catalog.IssuePageRead,
  first : Int,
) -> Result[String, @catalog.GraphqlResponseIssue] {
  @catalog.issue_page_read_next_request(read, first).map(request => {
    ({ "body": optional_text(request) } : Json).stringify()
  })
}

///|
#export_name("githubIssuePageReadAccept")
pub fn github_issue_page_read_accept(
  read : @catalog.IssuePageRead,
  body : Bytes,
) -> Result[Unit, @catalog.GraphqlResponseIssue] {
  @catalog.issue_page_read_accept(read, body)
}

///|
#export_name("githubIssuePageReadFinishJson")
pub fn github_issue_page_read_finish_json(
  read : @catalog.IssuePageRead,
) -> Result[String, @catalog.GraphqlResponseIssue] {
  @catalog.issue_page_read_finish(read).map(page => {
    graphql_page_json(page).stringify()
  })
}

///|
#export_name("githubIssuePageReadClose")
pub fn github_issue_page_read_close(read : @catalog.IssuePageRead) -> Unit {
  @catalog.issue_page_read_close(read)
}

///|
#export_name("githubGraphqlReadIssueJson")
pub fn github_graphql_read_issue_json(
  issue : @catalog.GraphqlResponseIssue,
) -> String {
  graphql_issue_name(issue).stringify()
}
