// GitHub Issue comment creation through the GraphQL API, addressed by the
// Issue's global node ID. The connector sends two fixed documents: a
// read-only subject check and the `addComment` mutation. Callers supply
// typed variables only, and the comment body is sent exactly as given.

///|
/// The fixed subject check sent before a comment: the node must be an Issue
/// of the published repository. It does not exclude a move between this
/// read and the send.
pub let comment_subject_query : String = "query ActqlCommentSubject($id: ID!) { node(id: $id) { __typename ... on Issue { id number repository { __typename id databaseId nameWithOwner } } } }"

///|
/// The fixed comment mutation. The reply names the created comment and the
/// subject it was added to.
pub let add_comment_mutation : String = "mutation ActqlAddComment($subjectId: ID!, $body: String!) { addComment(input: {subjectId: $subjectId, body: $body}) { commentEdge { node { id databaseId } } subject { __typename id } } }"

///|
/// GitHub's documented maximum comment body length, in characters.
pub let max_comment_characters : Int = 65536

///|
pub(all) enum CommentRequestIssue {
  InvalidSubjectId
  InvalidBody
} derive(Eq, Debug)

///|
fn valid_subject_id(subject_id : String) -> Bool {
  !subject_id.is_empty() && subject_id.length() <= 256
}

///|
/// The JSON body of a subject check.
pub fn comment_subject_request(
  subject_id : String,
) -> Result[String, CommentRequestIssue] {
  if !valid_subject_id(subject_id) {
    return Err(InvalidSubjectId)
  }
  Ok(
    (
      {
        "query": comment_subject_query.to_json(),
        "variables": { "id": subject_id.to_json() },
      } : Json).stringify(),
  )
}

///|
/// The JSON body of one comment mutation. The body is not normalized: the
/// sent bytes are the request's identity.
pub fn add_comment_request(
  subject_id : String,
  body : String,
) -> Result[String, CommentRequestIssue] {
  if !valid_subject_id(subject_id) {
    return Err(InvalidSubjectId)
  }
  let mut characters = 0
  for _ in body {
    characters = characters + 1
  }
  if characters == 0 || characters > max_comment_characters {
    return Err(InvalidBody)
  }
  Ok(
    (
      {
        "query": add_comment_mutation.to_json(),
        "variables": {
          "subjectId": subject_id.to_json(),
          "body": body.to_json(),
        },
      } : Json).stringify(),
  )
}

///|
/// The Issue a subject check resolved.
pub(all) struct CommentSubject {
  node_id : String
  number : Int64
  repository : GraphqlRepository
} derive(Eq, Debug)

///|
/// Project a subject check. The subject is accepted only when it is that
/// exact node, an Issue (a pull request is refused), in exactly the
/// published repository.
pub fn project_comment_subject_response(
  body : Bytes,
  limits : PageLimits,
  subject_id : String,
  expected_node_id : String,
  expected_database_id : Int64,
  expected_name_with_owner : String,
) -> Result[CommentSubject, GraphqlResponseIssue] {
  let data = match admit_body(body, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let node = match @decode.field(data, "node") {
    Present(value) =>
      match @decode.open_object(value) {
        Ok(object) => object
        Err(_) => return Err(InvalidResponse)
      }
    ExplicitNull => return Err(SubjectUnavailable)
    Missing => return Err(InvalidResponse)
  }
  guard @decode.lookup(node, "__typename") is Some(type_cursor) &&
    @decode.text(type_cursor) is Ok(type_name) else {
    return Err(InvalidResponse)
  }
  if type_name != "Issue" {
    return Err(WrongType(type_name))
  }
  guard @decode.lookup(node, "id") is Some(id_cursor) &&
    @decode.text(id_cursor) is Ok(node_id) &&
    @decode.lookup(node, "number") is Some(number_cursor) &&
    @decode.safe_integer(number_cursor) is Ok(number) &&
    number > 0L &&
    @decode.lookup(node, "repository") is Some(repository_cursor) &&
    @decode.open_object(repository_cursor) is Ok(repository_object) else {
    return Err(InvalidResponse)
  }
  if node_id != subject_id {
    return Err(ForeignSubject)
  }
  let repository = match repository_of(repository_object) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if repository.database_id != expected_database_id {
    return Err(ForeignRepository)
  }
  if repository.node_id != expected_node_id {
    return Err(IdRepresentationChanged)
  }
  if repository.name_with_owner != expected_name_with_owner {
    return Err(BindingChanged)
  }
  Ok({ node_id, number, repository, })
}

///|
/// The settled meaning of one comment exchange. Only a documented success or
/// a documented refusal settles the row; every other observation leaves the
/// send unknown, and nothing here infers success from content.
pub(all) enum CommentOutcome {
  Created(id~ : Int64, node_id~ : String)
  Refused(status~ : Int)
  Rejected(kind~ : String)
  Unknown
} derive(Eq, Debug)

///|
/// Classify a comment mutation response.
///
/// - HTTP 200 whose `addComment` names a created comment on exactly the
///   requested subject, an Issue, with no `errors`: created.
/// - HTTP 200 with a non-empty `errors` list of well-formed errors (each an
///   object with a string `message`) and no `data` member: the GraphQL
///   specification states such an error was raised before execution, so
///   nothing was applied; rejected. A malformed error list stays unknown. A rate limit stays unknown, as GitHub does not
///   document that a throttled mutation was not applied.
/// - HTTP 200 with `errors` and `data` (even null): execution began; unknown.
/// - 403/404/410/422 without rate-limit evidence: refused, as for REST.
/// - Anything else, including a reply naming another subject: unknown.
pub fn classify_comment_response(
  status : Int,
  headers : HeaderObservation,
  body : Bytes,
  limits : PageLimits,
  subject_id : String,
) -> CommentOutcome {
  if status != 200 {
    return match classify_failure(status, headers) {
      PermissionDenied | NotFound | Gone | Unprocessable => Refused(status~)
      RateLimited(_) | ProviderUnavailable | Unexpected(_) => Unknown
    }
  }
  if limits.max_bytes <= 0 || body.length() > limits.max_bytes {
    return Unknown
  }
  guard @source.parse_json_bytes(body, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    })
    is Ok(node) &&
    @decode.admit(node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    })
    is Ok(root) &&
    @decode.open_object(root) is Ok(object) else {
    return Unknown
  }
  match @decode.field(object, "errors") {
    Missing => ()
    _ => {
      guard @decode.field(object, "data") is Missing &&
        @decode.lookup(object, "errors") is Some(errors) &&
        @decode.elements(errors) is Ok(items) &&
        !items.is_empty() else {
        return Unknown
      }
      let mut kind = ""
      for item in items {
        // A request error is a well-formed GraphQL error: an object with a
        // string `message`. Anything else is not evidence that execution
        // never began.
        guard @decode.open_object(item) is Ok(error) &&
          @decode.field(error, "message") is Present(message) &&
          @decode.text(message) is Ok(_) else {
          return Unknown
        }
        let text = match @decode.field(error, "type") {
          Present(value) =>
            match @decode.text(value) {
              Ok(text) if !text.is_empty() => text
              _ => return Unknown
            }
          Missing => "UNKNOWN"
          ExplicitNull => return Unknown
        }
        if text == "RATE_LIMITED" {
          return Unknown
        }
        if kind.is_empty() {
          kind = text
        }
      }
      return Rejected(kind~)
    }
  }
  guard @decode.lookup(object, "data") is Some(data_cursor) &&
    @decode.open_object(data_cursor) is Ok(data) &&
    @decode.lookup(data, "addComment") is Some(payload_cursor) &&
    @decode.open_object(payload_cursor) is Ok(payload) &&
    @decode.lookup(payload, "commentEdge") is Some(edge_cursor) &&
    @decode.open_object(edge_cursor) is Ok(edge) &&
    @decode.lookup(edge, "node") is Some(comment_cursor) &&
    @decode.open_object(comment_cursor) is Ok(comment) &&
    @decode.lookup(comment, "id") is Some(node_cursor) &&
    @decode.text(node_cursor) is Ok(node_id) &&
    !node_id.is_empty() &&
    @decode.lookup(comment, "databaseId") is Some(database_cursor) &&
    @decode.safe_integer(database_cursor) is Ok(id) &&
    id > 0L &&
    @decode.lookup(payload, "subject") is Some(subject_cursor) &&
    @decode.open_object(subject_cursor) is Ok(subject) &&
    @decode.lookup(subject, "__typename") is Some(type_cursor) &&
    @decode.text(type_cursor) is Ok("Issue") &&
    @decode.lookup(subject, "id") is Some(subject_cursor_id) &&
    @decode.text(subject_cursor_id) is Ok(answered) &&
    answered == subject_id else {
    return Unknown
  }
  Created(id~, node_id~)
}
