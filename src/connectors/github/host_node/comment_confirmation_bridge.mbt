// Provider DATA only. The Host owns the original final request, observations,
// current read grant, backing, cleanup and any terminal Effect receipt.

///|
#export_name("githubPrepareCommentConfirmation")
pub fn github_prepare_comment_confirmation(
  subject_id : String,
  logical_body : String,
  tag : String,
  final_request : String,
  repository_node_id : String,
  repository_database_id : Double,
  repository_name : String,
  status : Int,
  headers_known : Bool,
  names : Array[String],
  values : Array[String],
  body : Bytes,
  max_request_bytes : Int,
  max_response_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@catalog.CommentConfirmation, @catalog.GraphqlResponseIssue] {
  guard headers_of(names, values) is Some(headers) else {
    return Err(@catalog.InvalidResponse)
  }
  @catalog.prepare_comment_confirmation(
    { node_id: repository_node_id, database_id: repository_database_id.to_int64(),
      name_with_owner: repository_name, },
    subject_id, logical_body, tag, final_request, status, headers_known, headers, body,
    { max_bytes: max_request_bytes, max_nodes, max_depth, max_rows: 1, },
    { max_bytes: max_response_bytes, max_nodes, max_depth, max_rows: 1, },
  )
}

///|
#export_name("githubCommentConfirmationRequestJson")
pub fn github_comment_confirmation_request_json(
  held : @catalog.CommentConfirmation,
) -> String {
  (match @catalog.comment_confirmation_request(held) {
    Some(body) => { "kind": "ConfirmationRequest", "body": body.to_json() }
    None => { "kind": "NoConfirmation" }
  } : Json).stringify()
}

///|
#export_name("githubProjectCommentConfirmationJson")
pub fn github_project_comment_confirmation_json(
  held : @catalog.CommentConfirmation,
  status : Int,
  body : Bytes,
) -> String {
  (match @catalog.project_comment_confirmation(held, status, body) {
    Ok((id, node_id)) => { "kind": "Confirmed", "id": id.to_string().to_json(),
      "nodeId": node_id.to_json() }
    Err(_) => { "kind": "Unknown" }
  } : Json).stringify()
}
