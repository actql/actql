// Pure correlation of a saved final Comment request and its actual mutation
// response. This value is DATA, never permission, a reader or an Effect receipt.

///|
pub struct CommentConfirmation {
  priv subject_id : String
  priv repository : GraphqlRepository
  priv physical_body : String
  priv created : (Int64, String)?
  priv request : String?
  priv limits : PageLimits
}

///|
let comment_confirmation_query : String = "query ActqlConfirmCreatedIssueComment($id: ID!) { node(id: $id) { __typename ... on IssueComment { id fullDatabaseId body repository { __typename id databaseId nameWithOwner } issue { __typename id repository { __typename id databaseId nameWithOwner } } pullRequest { id } } } }"

///|
fn comment_tag_data(tag : String) -> Bool {
  if tag.length() != 71 || !tag.has_prefix("sha256:") {
    return false
  }
  for i = 7; i < tag.length(); i = i + 1 {
    let unit = tag.code_unit_at(i).to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn comment_final_request_body(
  wire : String,
  subject_id : String,
  logical_body : String,
  tag : String,
  limits : PageLimits,
) -> Result[String, GraphqlResponseIssue] {
  if limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    wire.length() > limits.max_bytes ||
    !comment_tag_data(tag) {
    return Err(InvalidResponse)
  }
  let bytes = @utf8.encode(wire)
  guard bytes.length() <= limits.max_bytes &&
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    })
    is Ok(parsed) &&
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    })
    is Ok(root) &&
    @decode.closed_object(root, ["query", "variables"]) is Ok(request) &&
    required_text(request, "query") is Ok(query) &&
    query == add_comment_mutation &&
    @decode.lookup(request, "variables") is Some(variables_cursor) &&
    @decode.closed_object(variables_cursor, ["subjectId", "body"])
    is Ok(variables) &&
    required_text(variables, "subjectId") is Ok(actual_subject) &&
    actual_subject == subject_id &&
    required_text(variables, "body") is Ok(physical_body) &&
    physical_body == logical_body + "\n\n<!-- actql:effect:" + tag + " -->" else {
    return Err(InvalidResponse)
  }
  Ok(physical_body)
}

///|
/// Retain independently supplied originals. No mark/prepare of a mutation,
/// DispatchKey issuance, authority or provider I/O occurs in this constructor.
pub fn prepare_comment_confirmation(
  repository : GraphqlRepository,
  subject_id : String,
  logical_body : String,
  tag : String,
  final_request : String,
  status : Int,
  headers_known : Bool,
  headers : HeaderObservation,
  body : Bytes,
  request_limits : PageLimits,
  response_limits : PageLimits,
) -> Result[CommentConfirmation, GraphqlResponseIssue] {
  if !valid_subject_id(subject_id) ||
    !valid_subject_id(repository.node_id) ||
    repository.database_id <= 0L ||
    repository.name_with_owner.is_empty() ||
    response_limits.max_bytes <= 0 ||
    response_limits.max_nodes <= 0 ||
    response_limits.max_depth <= 0 ||
    response_limits.max_rows <= 0 {
    return Err(InvalidResponse)
  }
  let physical_body = match
    comment_final_request_body(
      final_request, subject_id, logical_body, tag, request_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Missing recovered headers never convert an ambiguous 403 into evidence.
  let created = if !headers_known && status == 403 {
    None
  } else {
    match
      classify_comment_response(
        status, headers, body, response_limits, subject_id,
      ) {
      Created(id~, node_id~) if valid_subject_id(node_id) => Some((id, node_id))
      _ => None
    }
  }
  let request = match created {
    Some((_, node_id)) => {
      let wire = (
        {
          "query": comment_confirmation_query.to_json(),
          "variables": { "id": node_id.to_json() },
        } : Json).stringify()
      if @utf8.encode(wire).length() > request_limits.max_bytes {
        return Err(BudgetExceeded)
      }
      Some(wire)
    }
    None => None
  }
  Ok({
    subject_id,
    repository,
    physical_body,
    created,
    request,
    limits: response_limits,
  })
}

///|
pub fn comment_confirmation_request(value : CommentConfirmation) -> String? {
  value.request
}

///|
/// A read refusal, absent object or changed input remains uncertain; only the
/// complete original object/body/marker/subject/repository correspondence is DATA.
pub fn project_comment_confirmation(
  value : CommentConfirmation,
  status : Int,
  body : Bytes,
) -> Result[(Int64, String), GraphqlResponseIssue] {
  guard value.created is Some((expected_id, expected_node)) && status == 200 else {
    return Err(InvalidResponse)
  }
  let data = match admit_body(body, value.limits) {
    Ok(data) => data
    Err(issue) => return Err(issue)
  }
  guard @decode.lookup(data, "node") is Some(cursor) &&
    @decode.open_object(cursor) is Ok(node) &&
    required_text(node, "__typename") is Ok("IssueComment") &&
    required_text(node, "id") is Ok(node_id) &&
    node_id == expected_node &&
    required_text(node, "body") is Ok(physical_body) &&
    physical_body == value.physical_body &&
    required_text(node, "fullDatabaseId") is Ok(id_text) &&
    @scalar.read_decimal_int64(id_text) is Ok(id) &&
    id > 0L &&
    id.to_string() == id_text &&
    id == expected_id else {
    return Err(InvalidResponse)
  }
  match comment_repository(node, value.repository) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard @decode.field(node, "pullRequest") is ExplicitNull &&
    @decode.lookup(node, "issue") is Some(issue_cursor) &&
    @decode.open_object(issue_cursor) is Ok(issue) &&
    required_text(issue, "__typename") is Ok("Issue") &&
    required_text(issue, "id") is Ok(subject_id) &&
    subject_id == value.subject_id else {
    return Err(ForeignSubject)
  }
  match comment_repository(issue, value.repository) {
    Ok(_) => Ok((id, node_id))
    Err(issue) => Err(issue)
  }
}
