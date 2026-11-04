///|
/// Read only the comment named by the original Created response. This does
/// not enumerate repository history or infer an outcome from an HTTP status.
/// IssueComment fields follow https://docs.github.com/en/graphql/reference/issues#issuecomment.
pub let comment_confirmation_query : String = "query ActqlConfirmComment($id: ID!) { node(id: $id) { __typename ... on IssueComment { id databaseId body issue { __typename id } repository { __typename id databaseId nameWithOwner } } } }"

///|
pub fn comment_confirmation_request(
  comment_node_id : String,
) -> Result[String, CommentRequestIssue] {
  if !valid_subject_id(comment_node_id) {
    return Err(InvalidSubjectId)
  }
  Ok(
    (
      {
        "query": comment_confirmation_query.to_json(),
        "variables": { "id": comment_node_id.to_json() },
      } : Json).stringify(),
  )
}

///|
// The original Common DispatchKey CID is DATA here, never a new key, claim,
// credential or permission. Keep the same exact spelling as the stamp recipe.
fn comment_confirmation_tag_valid(tag : String) -> Bool {
  if tag.length() != 71 || !tag.has_prefix("sha256:") {
    return false
  }
  for character in tag[7:] {
    if !((character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f')) {
      return false
    }
  }
  true
}

///|
// Exact original DATA only; the caller independently binds this tag to the
// admitted Preview/DispatchKey. No CID, request or signing authority is issued.
fn original_comment_marked_body(
  logical_body : String,
  request_tag : String,
) -> Result[String, GraphqlResponseIssue] {
  if !comment_confirmation_tag_valid(request_tag) {
    return Err(InvalidResponse)
  }
  if logical_body.length() > 2 * max_comment_characters {
    return Err(BudgetExceeded)
  }
  let expected_body = logical_body +
    "\n\n<!-- actql:effect:" +
    request_tag +
    " -->"
  let mut characters = 0
  for _ in expected_body {
    characters += 1
    if characters > max_comment_characters {
      return Err(BudgetExceeded)
    }
  }
  Ok(expected_body)
}

///|
/// Compare the COMPLETE retained physical request against independently
/// retained original logical DATA/tag. This does not re-encode or prepare a
/// replacement request, follow a response, create a key or authorize a send.
pub fn admit_original_marked_comment_request(
  body : Bytes,
  limits : PageLimits,
  subject_id : String,
  logical_body : String,
  request_tag : String,
) -> Result[Unit, GraphqlResponseIssue] {
  if !valid_subject_id(subject_id) ||
    limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_rows < 1 {
    return Err(InvalidResponse)
  }
  let expected_body = match
    original_comment_marked_body(logical_body, request_tag) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if body.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  guard @source.parse_json_bytes(body, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    })
    is Ok(source) &&
    @decode.admit(source, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, ["query", "variables"]) is Ok(root) &&
    @decode.lookup(root, "query") is Some(query) &&
    @decode.text(query) == Ok(add_comment_mutation) &&
    @decode.lookup(root, "variables") is Some(variables) &&
    @decode.closed_object(variables, ["subjectId", "body"]) is Ok(variables) &&
    required_text(variables, "subjectId") == Ok(subject_id) &&
    required_text(variables, "body") == Ok(expected_body) else {
    return Err(BindingChanged)
  }
  Ok(())
}

///|
/// Compare a bounded original read-back with the independently retained
/// request and Created response. Exact content includes the original marker;
/// equivalent or unmarked content is insufficient. This pure comparison does
/// not admit a Run outcome, perform a read, issue a grant or authorize resend.
/// Every refusal leaves the caller's possible mutation outcome unresolved.
pub fn project_comment_confirmation_response(
  body : Bytes,
  limits : PageLimits,
  comment_id : Int64,
  comment_node_id : String,
  subject_id : String,
  repository : GraphqlRepository,
  logical_body : String,
  request_tag : String,
) -> Result[Unit, GraphqlResponseIssue] {
  if comment_id < 1L ||
    comment_id > 2147483647L ||
    !valid_subject_id(comment_node_id) ||
    !valid_subject_id(subject_id) ||
    !comment_confirmation_tag_valid(request_tag) {
    return Err(InvalidResponse)
  }
  let expected_body = match
    original_comment_marked_body(logical_body, request_tag) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let data = match admit_body(body, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.lookup(data, "node") is Some(cursor) &&
    @decode.open_object(cursor) is Ok(node) else {
    return Err(SubjectUnavailable)
  }
  match required_text(node, "__typename") {
    Ok("IssueComment") => ()
    Ok(other) => return Err(WrongType(other))
    Err(issue) => return Err(Row(issue))
  }
  match comment_repository(node, repository) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard required_text(node, "id") is Ok(actual_node_id) &&
    actual_node_id == comment_node_id &&
    required_integer(node, "databaseId", body, limits.max_bytes)
    is Ok(actual_id) &&
    actual_id == comment_id &&
    @decode.lookup(node, "issue") is Some(issue_cursor) &&
    @decode.open_object(issue_cursor) is Ok(issue) &&
    required_text(issue, "__typename") == Ok("Issue") &&
    required_text(issue, "id") == Ok(subject_id) else {
    return Err(ForeignSubject)
  }
  if required_text(node, "body") != Ok(expected_body) {
    return Err(BindingChanged)
  }
  Ok(())
}
