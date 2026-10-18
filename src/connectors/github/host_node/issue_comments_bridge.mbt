// The existing Catalog Owner decides comment meaning and page sequencing.
// This bridge projects DATA and opaque decoder state only; it performs no I/O
// and issues no Credential, RowRun charge, permission or cleanup receipt.

///|
#export_name("githubIssueCommentsReadBegin")
pub fn github_issue_comments_read_begin(
  node_id : String,
  database_id : Double,
  name_with_owner : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_pages : Int,
  max_subjects : Int,
) -> Result[@catalog.IssueCommentsRead, @catalog.GraphqlResponseIssue] {
  // The repository's native databaseId is GraphQL Int, not BigInt. Refuse a
  // foreign JS numeric representation before conversion to the typed field.
  if !(database_id >= 1.0 &&
    database_id <= 2147483647.0 &&
    database_id.to_int().to_double() == database_id) {
    return Err(InvalidResponse)
  }
  @catalog.begin_issue_comments_read(
    { node_id, database_id: database_id.to_int64(), name_with_owner, },
    { max_bytes, max_nodes, max_depth, max_rows, },
    max_pages,
    max_subjects,
  )
}

///|
#export_name("githubIssueCommentsReadNextRequestJson")
pub fn github_issue_comments_read_next_request_json(
  read : @catalog.IssueCommentsRead,
  first : Int,
) -> Result[String, @catalog.GraphqlResponseIssue] {
  @catalog.issue_comments_read_next_request(read, first).map(request => {
    ({ "body": optional_text(request) } : Json).stringify()
  })
}

///|
#export_name("githubIssueCommentsReadAccept")
pub fn github_issue_comments_read_accept(
  read : @catalog.IssueCommentsRead,
  body : Bytes,
) -> Result[Unit, @catalog.GraphqlResponseIssue] {
  @catalog.issue_comments_read_accept(read, body)
}

///|
#export_name("githubIssueCommentsReadPageJson")
pub fn github_issue_comments_read_page_json(
  read : @catalog.IssueCommentsRead,
) -> Result[String, @catalog.GraphqlResponseIssue] {
  @catalog.issue_comments_read_take_page(read).map(page => {
    let value : Json = match page {
      None => Json::null()
      Some(page) =>
        {
          "rows": page.rows
          .map(row => {
            "id": row.id.to_string().to_json(),
            "subject_number": row.subject_number.to_string().to_json(),
            "author": optional_text(row.author),
            "body": row.body.to_json(),
            "created_at": row.created_at.to_json(),
            "updated_at": row.updated_at.to_json(),
          })
          .to_json(),
        }
    }
    ({ "page": value } : Json).stringify()
  })
}

///|
#export_name("githubIssueCommentsReadClose")
pub fn github_issue_comments_read_close(
  read : @catalog.IssueCommentsRead,
) -> Unit {
  @catalog.issue_comments_read_close(read)
}
