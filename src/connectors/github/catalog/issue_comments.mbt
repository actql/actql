///|
let comment_subject_read_query_prefix : String = "query ActqlCommentSubjects($id: ID!, $first: Int!, $after: String) { node(id: $id) { __typename ... on Repository { id databaseId nameWithOwner "

///|
let comment_subject_read_query_suffix : String = "(first: $first, after: $after) { pageInfo { hasNextPage endCursor } nodes { __typename id number updatedAt } } } } }"

///|
let comment_read_query_prefix : String = "query ActqlIssueComments($id: ID!, $first: Int!, $after: String) { node(id: $id) { __typename ... on "

///|
let comment_read_query_suffix : String = " { id number updatedAt repository { __typename id databaseId nameWithOwner } comments(first: $first, after: $after) { pageInfo { hasNextPage endCursor } nodes { __typename id fullDatabaseId author { login } body createdAt updatedAt repository { __typename id databaseId nameWithOwner } } } } } }"

///|
/// A comment's public numeric key and its separate opaque provider identity.
/// Neither is permission; the Source projection exports only the six declared
/// comment columns. The opaque ID remains with the original acquisition.
pub(all) struct IssueCommentRow {
  id : Int64
  node_id : String
  subject_number : Int64
  author : String?
  body : String
  created_at : String
  updated_at : String
} derive(Eq, Debug)

///|
/// The original native subject selected by the repository-bound enumeration.
/// A caller-supplied value is DATA, not an admitted Source or credential use.
pub(all) struct IssueCommentSubject {
  node_id : String
  number : Int64
  native_type : String
  updated_at : String
  repository : GraphqlRepository
} derive(Eq, Debug)

///|
pub(all) struct GraphqlIssueCommentPage {
  subject : IssueCommentSubject
  rows : Array[IssueCommentRow]
  has_next_page : Bool
  end_cursor : String?
} derive(Eq, Debug)

///|
/// Only the subject type changes between these fixed read-only documents.
/// Refetching by opaque node ID never falls back to a repository access name.
pub fn issue_comments_request(
  subject : IssueCommentSubject,
  first : Int,
  after : String?,
) -> Result[String, GraphqlRequestIssue] {
  if !valid_subject_id(subject.node_id) {
    return Err(InvalidNodeId)
  }
  if first < 1 || first > 100 {
    return Err(InvalidPageSize)
  }
  if after is Some(cursor) && (cursor.is_empty() || cursor.length() > 1024) {
    return Err(InvalidCursor)
  }
  if subject.native_type != "Issue" && subject.native_type != "PullRequest" {
    return Err(InvalidState)
  }
  let query = comment_read_query_prefix +
    subject.native_type +
    comment_read_query_suffix
  Ok(
    (
      {
        "query": query.to_json(),
        "variables": {
          "id": subject.node_id.to_json(),
          "first": first.to_json(),
          "after": optional_json(after),
        },
      } : Json).stringify(),
  )
}

///|
fn comment_repository(
  object : @decode.ObjectView,
  expected : GraphqlRepository,
) -> Result[Unit, GraphqlResponseIssue] {
  guard @decode.lookup(object, "repository") is Some(cursor) &&
    @decode.open_object(cursor) is Ok(repository) else {
    return Err(InvalidResponse)
  }
  let actual = match repository_of(repository) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if actual.database_id != expected.database_id {
    return Err(ForeignRepository)
  }
  if actual.node_id != expected.node_id {
    return Err(IdRepresentationChanged)
  }
  if actual.name_with_owner != expected.name_with_owner {
    return Err(BindingChanged)
  }
  Ok(())
}

///|
fn graphql_comment_row(
  object : @decode.ObjectView,
  subject : IssueCommentSubject,
) -> Result[IssueCommentRow, GraphqlResponseIssue] {
  match required_text(object, "__typename") {
    Ok("IssueComment") => ()
    Ok(other) => return Err(WrongType(other))
    Err(issue) => return Err(Row(issue))
  }
  match comment_repository(object, subject.repository) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  // GitHub BigInt is a decimal STRING. Do not decode an opaque Node ID or a
  // binary64 number as the database key, or fall back to deprecated databaseId.
  let id = match required_text(object, "fullDatabaseId") {
    Ok(text) =>
      match @scalar.read_decimal_int64(text) {
        Ok(value) if value > 0L && value.to_string() == text => value
        _ => return Err(Row(InvalidField("fullDatabaseId")))
      }
    Err(issue) => return Err(Row(issue))
  }
  let node_id = match required_text(object, "id") {
    Ok(value) if valid_subject_id(value) => value
    _ => return Err(Row(InvalidField("id")))
  }
  let author = match @decode.field(object, "author") {
    ExplicitNull => None
    Present(cursor) =>
      match @decode.open_object(cursor) {
        Ok(actor) =>
          match required_text(actor, "login") {
            Ok(login) => Some(login)
            Err(issue) => return Err(Row(issue))
          }
        Err(_) => return Err(Row(InvalidField("author")))
      }
    Missing => return Err(Row(MissingRequiredField("author")))
  }
  let body = match required_text(object, "body") {
    Ok(value) => value
    Err(issue) => return Err(Row(issue))
  }
  let created_at = match graphql_timestamp(object, "createdAt", false) {
    Ok(Some(value)) => value
    _ => return Err(Row(InvalidField("createdAt")))
  }
  let updated_at = match graphql_timestamp(object, "updatedAt", false) {
    Ok(Some(value)) => value
    _ => return Err(Row(InvalidField("updatedAt")))
  }
  Ok({
    id,
    node_id,
    subject_number: subject.number,
    author,
    body,
    created_at,
    updated_at,
  })
}

///|
/// Decode one original subject's comments, retaining its native kind, number,
/// observation and repository correspondence on every dependent page. This
/// proves no atomic provider snapshot or live acquisition from DATA alone.
pub fn project_issue_comments_response(
  body : Bytes,
  limits : PageLimits,
  expected : IssueCommentSubject,
) -> Result[GraphqlIssueCommentPage, GraphqlResponseIssue] {
  let data = match admit_body(body, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.lookup(data, "node") is Some(cursor) &&
    @decode.open_object(cursor) is Ok(node) else {
    return Err(SubjectUnavailable)
  }
  match required_text(node, "__typename") {
    Ok(kind) if kind == expected.native_type &&
      (kind == "Issue" || kind == "PullRequest") => ()
    Ok(other) => return Err(WrongType(other))
    Err(issue) => return Err(Row(issue))
  }
  match comment_repository(node, expected.repository) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard required_text(node, "id") is Ok(identity) &&
    identity == expected.node_id &&
    required_integer(node, "number", body, limits.max_bytes) is Ok(number) &&
    number > 0L &&
    number <= 2147483647L &&
    number == expected.number &&
    graphql_timestamp(node, "updatedAt", false) is Ok(Some(updated)) &&
    updated == expected.updated_at else {
    return Err(ForeignSubject)
  }
  guard @decode.lookup(node, "comments") is Some(connection_cursor) &&
    @decode.open_object(connection_cursor) is Ok(connection) &&
    @decode.lookup(connection, "pageInfo") is Some(info_cursor) &&
    @decode.open_object(info_cursor) is Ok(info) &&
    @decode.lookup(info, "hasNextPage") is Some(next_cursor) &&
    @decode.boolean(next_cursor) is Ok(has_next_page) &&
    @decode.lookup(connection, "nodes") is Some(nodes_cursor) &&
    @decode.elements(nodes_cursor) is Ok(nodes) else {
    return Err(InvalidResponse)
  }
  let end_cursor = match nullable_text(info, "endCursor") {
    Ok(None) => None
    Ok(Some(text)) if !text.is_empty() && text.length() <= 1024 => Some(text)
    _ => return Err(InvalidResponse)
  }
  if has_next_page && end_cursor is None {
    return Err(MissingCursor)
  }
  if nodes.length() > limits.max_rows || nodes.length() > 100 {
    return Err(BudgetExceeded)
  }
  let rows = []
  for cursor in nodes {
    guard @decode.open_object(cursor) is Ok(object) else {
      return Err(InvalidResponse)
    }
    match graphql_comment_row(object, expected) {
      Ok(row) => rows.push(row)
      Err(issue) => return Err(issue)
    }
  }
  Ok({ subject: expected, rows, has_next_page, end_cursor, })
}

///|
pub(all) struct GraphqlIssueCommentSubjectsPage {
  repository : GraphqlRepository
  subjects : Array[IssueCommentSubject]
  has_next_page : Bool
  end_cursor : String?
} derive(Eq, Debug)

///|
/// Enumerate real subjects by the already published repository node. Comments
/// on native PullRequests are not inferred from Issue numbers or URLs.
pub fn issue_comment_subjects_request(
  repository_id : String,
  native_type : String,
  first : Int,
  after : String?,
) -> Result[String, GraphqlRequestIssue] {
  if !valid_subject_id(repository_id) {
    return Err(InvalidNodeId)
  }
  if first < 1 || first > 100 {
    return Err(InvalidPageSize)
  }
  if after is Some(cursor) && (cursor.is_empty() || cursor.length() > 1024) {
    return Err(InvalidCursor)
  }
  let connection = match native_type {
    "Issue" => "issues"
    "PullRequest" => "pullRequests"
    _ => return Err(InvalidState)
  }
  let query = comment_subject_read_query_prefix +
    connection +
    comment_subject_read_query_suffix
  Ok(
    (
      {
        "query": query.to_json(),
        "variables": {
          "id": repository_id.to_json(),
          "first": first.to_json(),
          "after": optional_json(after),
        },
      } : Json).stringify(),
  )
}

///|
pub fn project_issue_comment_subjects_response(
  body : Bytes,
  limits : PageLimits,
  expected : GraphqlRepository,
  native_type : String,
) -> Result[GraphqlIssueCommentSubjectsPage, GraphqlResponseIssue] {
  let connection_name = match native_type {
    "Issue" => "issues"
    "PullRequest" => "pullRequests"
    _ => return Err(InvalidResponse)
  }
  let data = match admit_body(body, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.lookup(data, "node") is Some(cursor) &&
    @decode.open_object(cursor) is Ok(node) else {
    return Err(RepositoryUnavailable)
  }
  let repository = match repository_of(node) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if repository.database_id != expected.database_id {
    return Err(ForeignRepository)
  }
  if repository.node_id != expected.node_id {
    return Err(IdRepresentationChanged)
  }
  if repository.name_with_owner != expected.name_with_owner {
    return Err(BindingChanged)
  }
  guard @decode.lookup(node, connection_name) is Some(connection_cursor) &&
    @decode.open_object(connection_cursor) is Ok(connection) &&
    @decode.lookup(connection, "pageInfo") is Some(info_cursor) &&
    @decode.open_object(info_cursor) is Ok(info) &&
    @decode.lookup(info, "hasNextPage") is Some(next_cursor) &&
    @decode.boolean(next_cursor) is Ok(has_next_page) &&
    @decode.lookup(connection, "nodes") is Some(nodes_cursor) &&
    @decode.elements(nodes_cursor) is Ok(nodes) else {
    return Err(InvalidResponse)
  }
  let end_cursor = match nullable_text(info, "endCursor") {
    Ok(None) => None
    Ok(Some(text)) if !text.is_empty() && text.length() <= 1024 => Some(text)
    _ => return Err(InvalidResponse)
  }
  if has_next_page && end_cursor is None {
    return Err(MissingCursor)
  }
  if nodes.length() > limits.max_rows || nodes.length() > 100 {
    return Err(BudgetExceeded)
  }
  let subjects = []
  for cursor in nodes {
    guard @decode.open_object(cursor) is Ok(object) else {
      return Err(InvalidResponse)
    }
    match required_text(object, "__typename") {
      Ok(kind) if kind == native_type => ()
      Ok(other) => return Err(WrongType(other))
      Err(issue) => return Err(Row(issue))
    }
    guard required_text(object, "id") is Ok(node_id) &&
      valid_subject_id(node_id) &&
      required_integer(object, "number", body, limits.max_bytes) is Ok(number) &&
      number > 0L &&
      number <= 2147483647L &&
      graphql_timestamp(object, "updatedAt", false) is Ok(Some(updated_at)) else {
      return Err(InvalidResponse)
    }
    subjects.push({ node_id, number, native_type, updated_at, repository, })
  }
  Ok({ repository, subjects, has_next_page, end_cursor, })
}

///|
// Quantity of the SAME fixed fragments used by both original request builders.
// No request or response is constructed to obtain this immutable geometry.
pub fn comment_read_query_units() -> Int {
  Int::max(
    comment_read_query_prefix.length() +
    "PullRequest".length() +
    comment_read_query_suffix.length(),
    comment_subject_read_query_prefix.length() +
    "pullRequests".length() +
    comment_subject_read_query_suffix.length(),
  )
}
