///|
/// Existing provider DATA codec only. This issues no physical read, grant,
/// dispatch, Effect outcome or cleanup acknowledgement.
#export_name("githubCommentConfirmationRequestJson")
pub fn github_comment_confirmation_request_json(node_id : String) -> String {
  comment_request_json(@catalog.comment_confirmation_request(node_id))
}

///|
/// Original saved request DATA only. Admission does not prepare a request or
/// confer a dispatch permission; the actual Ledger claim remains mandatory.
#export_name("githubOriginalMarkedCommentRequestJson")
pub fn github_original_marked_comment_request_json(
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  subject_id : String,
  logical_body : String,
  request_tag : String,
) -> String {
  let json : Json = match
    @catalog.admit_original_marked_comment_request(
      body,
      { max_bytes, max_nodes, max_depth, max_rows: 1, },
      subject_id,
      logical_body,
      request_tag,
    ) {
    Ok(_) => { "original": { "subject_id": subject_id.to_json() } }
    Err(issue) => { "refused": graphql_issue_name(issue) }
  }
  json.stringify()
}

///|
/// Compare only the caller's independently retained original tuple with one
/// bounded read-back. The returned object is provider DATA, not permission or
/// a terminal row receipt. Current scoped acquisition and the existing claim,
/// Outcome Receipt and CAS remain obligations of the actual Host caller.
#export_name("githubCommentConfirmationJson")
pub fn github_comment_confirmation_json(
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  comment_id : Double,
  comment_node_id : String,
  subject_id : String,
  repository_node_id : String,
  repository_database_id : Double,
  repository_name_with_owner : String,
  logical_body : String,
  request_tag : String,
) -> String {
  // These originals use GitHub GraphQL Int, never a BigInt/String fallback.
  // Check the actual JS representation before narrowing either native value.
  if !(comment_id >= 1.0 &&
    comment_id <= 2147483647.0 &&
    comment_id.to_int().to_double() == comment_id &&
    repository_database_id >= 1.0 &&
    repository_database_id <= 2147483647.0 &&
    repository_database_id.to_int().to_double() == repository_database_id) {
    return ({ "refused": graphql_issue_name(InvalidResponse) } : Json).stringify()
  }
  let json : Json = match
    @catalog.project_comment_confirmation_response(
      body,
      { max_bytes, max_nodes, max_depth, max_rows: 1, },
      comment_id.to_int64(),
      comment_node_id,
      subject_id,
      {
        node_id: repository_node_id,
        database_id: repository_database_id.to_int64(),
        name_with_owner: repository_name_with_owner,
      },
      logical_body,
      request_tag,
    ) {
    Ok(_) =>
      {
        "comment": {
          "id": Json::number(comment_id),
          "node_id": comment_node_id.to_json(),
          "subject_id": subject_id.to_json(),
        },
      }
    Err(issue) => { "refused": graphql_issue_name(issue) }
  }
  json.stringify()
}
