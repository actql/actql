// GitHub's Issue read through the GraphQL API, bound to the published
// repository's global node ID. The connector sends only two fixed, read-only
// documents; callers supply typed variables, never query text. Every page
// resolves the repository by `node(id:)`, so a different repository under the
// same name is never read. Node IDs are opaque strings and compared exactly.

///|
/// The fixed repository lookup used only by the explicit publication step.
pub let repository_query : String = "query ActqlRepository($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { __typename id databaseId nameWithOwner } }"

///|
/// The fixed Issue page read. The repository is resolved by its published
/// node ID on every page.
pub let issues_query : String = "query ActqlIssues($id: ID!, $first: Int!, $after: String, $states: [IssueState!], $labels: [String!], $since: DateTime) { node(id: $id) { __typename ... on Repository { id databaseId nameWithOwner issues(first: $first, after: $after, states: $states, labels: $labels, filterBy: {since: $since}) { pageInfo { hasNextPage endCursor } nodes { number id title state body author { login } comments { totalCount } createdAt updatedAt closedAt } } } } }"

///|
fn optional_json(value : String?) -> Json {
  match value {
    Some(text) => text.to_json()
    None => Json::null()
  }
}

///|
/// The JSON body of a publication lookup.
pub fn repository_request(owner : String, name : String) -> String {
  (
    {
      "query": repository_query.to_json(),
      "variables": { "owner": owner.to_json(), "name": name.to_json() },
    } : Json).stringify()
}

///|
/// The Issue filters a read may carry. `state` is "open", "closed" or "all".
pub(all) struct IssueFilters {
  state : String
  labels : Array[String]
  since : String?
} derive(Eq, Debug)

///|
pub(all) enum GraphqlRequestIssue {
  InvalidNodeId
  InvalidPageSize
  InvalidCursor
  InvalidState
  InvalidLabel
  InvalidSince
} derive(Eq, Debug)

///|
/// The JSON body of one Issue page request: the fixed query with typed
/// variables only.
pub fn issues_request(
  node_id : String,
  first : Int,
  after : String?,
  filters : IssueFilters,
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
    "all" => Json::null()
    _ => return Err(InvalidState)
  }
  if filters.labels.any(label => label.is_empty() || label.length() > 256) ||
    filters.labels.length() > 20 {
    return Err(InvalidLabel)
  }
  let since = match filters.since {
    Some(value) =>
      match canonical_timestamp(value) {
        Some(_) => Some(value)
        None => return Err(InvalidSince)
      }
    None => None
  }
  Ok(
    (
      {
        "query": issues_query.to_json(),
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
          "since": optional_json(since),
        },
      } : Json).stringify(),
  )
}

///|
/// Why a GraphQL response is not an accepted page or repository. None of
/// these is a completed read: an HTTP 200 with `errors` or incomplete `data`
/// is refused, and a rate limit is a stop, never a retry.
pub(all) enum GraphqlResponseIssue {
  InvalidResponse
  RateLimited
  Errors(String)
  RepositoryUnavailable
  WrongType(String)
  ForeignRepository
  IdRepresentationChanged
  BindingChanged
  MissingCursor
  BudgetExceeded
  Row(IssuePageIssue)
} derive(Eq, Debug)

///|
/// A repository as one response states it.
pub(all) struct GraphqlRepository {
  node_id : String
  database_id : Int64
  name_with_owner : String
} derive(Eq, Debug)

///|
/// One accepted Issue page and its continuation.
pub(all) struct GraphqlIssuePage {
  repository : GraphqlRepository
  rows : Array[IssueRow]
  has_next_page : Bool
  end_cursor : String?
} derive(Eq, Debug)

///|
fn admit_body(
  body : Bytes,
  limits : PageLimits,
) -> Result[@decode.ObjectView, GraphqlResponseIssue] {
  if limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_rows <= 0 {
    return Err(InvalidResponse)
  }
  if body.length() > limits.max_bytes {
    return Err(BudgetExceeded)
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
    return Err(InvalidResponse)
  }
  // Any `errors` member refuses the response, even with `data`: partial
  // data is not a page. A rate limit is reported as such.
  match @decode.field(object, "errors") {
    Missing => ()
    _ => {
      guard @decode.lookup(object, "errors") is Some(errors) &&
        @decode.elements(errors) is Ok(items) &&
        !items.is_empty() else {
        return Err(InvalidResponse)
      }
      let mut kind = ""
      for item in items {
        if @decode.open_object(item) is Ok(error) &&
          @decode.lookup(error, "type") is Some(type_cursor) &&
          @decode.text(type_cursor) is Ok(text) {
          if text == "RATE_LIMITED" {
            return Err(RateLimited)
          }
          if kind.is_empty() {
            kind = text
          }
        }
      }
      return Err(Errors(if kind.is_empty() { "UNKNOWN" } else { kind }))
    }
  }
  guard @decode.lookup(object, "data") is Some(data) &&
    @decode.open_object(data) is Ok(data_object) else {
    return Err(InvalidResponse)
  }
  Ok(data_object)
}

///|
fn repository_of(
  object : @decode.ObjectView,
) -> Result[GraphqlRepository, GraphqlResponseIssue] {
  guard @decode.lookup(object, "__typename") is Some(type_cursor) &&
    @decode.text(type_cursor) is Ok(type_name) else {
    return Err(InvalidResponse)
  }
  if type_name != "Repository" {
    return Err(WrongType(type_name))
  }
  guard @decode.lookup(object, "id") is Some(id_cursor) &&
    @decode.text(id_cursor) is Ok(node_id) &&
    !node_id.is_empty() &&
    @decode.lookup(object, "databaseId") is Some(database_cursor) &&
    @decode.safe_integer(database_cursor) is Ok(database_id) &&
    database_id > 0L &&
    @decode.lookup(object, "nameWithOwner") is Some(name_cursor) &&
    @decode.text(name_cursor) is Ok(name_with_owner) else {
    return Err(InvalidResponse)
  }
  Ok({ node_id, database_id, name_with_owner, })
}

///|
/// Project a publication lookup: the repository named `owner/name` now.
pub fn project_repository_response(
  body : Bytes,
  limits : PageLimits,
) -> Result[GraphqlRepository, GraphqlResponseIssue] {
  let data = match admit_body(body, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @decode.field(data, "repository") {
    Present(value) =>
      match @decode.open_object(value) {
        Ok(object) => repository_of(object)
        Err(_) => Err(InvalidResponse)
      }
    ExplicitNull => Err(RepositoryUnavailable)
    Missing => Err(InvalidResponse)
  }
}

///|
fn graphql_text(
  object : @decode.ObjectView,
  name : String,
) -> Result[String, IssuePageIssue] {
  match @decode.field(object, name) {
    Missing => Err(MissingRequiredField(name))
    ExplicitNull => Err(NullRequiredField(name))
    Present(value) =>
      match @decode.text(value) {
        Ok(text) => Ok(text)
        Err(_) => Err(InvalidField(name))
      }
  }
}

///|
fn graphql_timestamp(
  object : @decode.ObjectView,
  name : String,
  nullable : Bool,
) -> Result[String?, IssuePageIssue] {
  match @decode.field(object, name) {
    Missing => Err(MissingRequiredField(name))
    ExplicitNull =>
      if nullable {
        Ok(None)
      } else {
        Err(NullRequiredField(name))
      }
    Present(value) =>
      match @decode.text(value) {
        Ok(text) =>
          match canonical_timestamp(text) {
            Some(canonical) => Ok(Some(canonical))
            None => Err(InvalidField(name))
          }
        Err(_) => Err(InvalidField(name))
      }
  }
}

///|
/// One GraphQL Issue node as the same `issues` row the REST read produced.
/// See docs/reviews/2026-10-04-github-graphql-read.md for the field map.
fn graphql_issue_row(
  object : @decode.ObjectView,
) -> Result[IssueRow, IssuePageIssue] {
  let number = match @decode.field(object, "number") {
    Present(value) =>
      match @decode.safe_integer(value) {
        Ok(number) if number > 0L => number
        _ => return Err(InvalidField("number"))
      }
    Missing => return Err(MissingRequiredField("number"))
    ExplicitNull => return Err(NullRequiredField("number"))
  }
  let node_id = match graphql_text(object, "id") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let title = match graphql_text(object, "title") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let state = match graphql_text(object, "state") {
    Ok("OPEN") => "open"
    Ok("CLOSED") => "closed"
    Ok(_) => return Err(InvalidField("state"))
    Err(issue) => return Err(issue)
  }
  // GraphQL states an Issue without a body as "", where REST stated null.
  let body = match graphql_text(object, "body") {
    Ok("") => None
    Ok(text) => Some(text)
    Err(issue) => return Err(issue)
  }
  let author = match @decode.field(object, "author") {
    ExplicitNull => None
    Present(value) =>
      match @decode.open_object(value) {
        Ok(user) =>
          match graphql_text(user, "login") {
            Ok(login) => Some(login)
            Err(issue) => return Err(issue)
          }
        Err(_) => return Err(InvalidField("author"))
      }
    Missing => return Err(MissingRequiredField("author"))
  }
  let comments = match @decode.field(object, "comments") {
    Present(value) =>
      match @decode.open_object(value) {
        Ok(connection) =>
          match @decode.lookup(connection, "totalCount") {
            Some(count) =>
              match @decode.safe_integer(count) {
                Ok(total) if total >= 0L => total
                _ => return Err(InvalidField("comments"))
              }
            None => return Err(MissingRequiredField("comments"))
          }
        Err(_) => return Err(InvalidField("comments"))
      }
    Missing => return Err(MissingRequiredField("comments"))
    ExplicitNull => return Err(NullRequiredField("comments"))
  }
  let created_at = match graphql_timestamp(object, "createdAt", false) {
    Ok(Some(value)) => value
    Ok(None) => return Err(NullRequiredField("createdAt"))
    Err(issue) => return Err(issue)
  }
  let updated_at = match graphql_timestamp(object, "updatedAt", false) {
    Ok(Some(value)) => value
    Ok(None) => return Err(NullRequiredField("updatedAt"))
    Err(issue) => return Err(issue)
  }
  let closed_at = match graphql_timestamp(object, "closedAt", true) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    number,
    node_id,
    title,
    state,
    body,
    author,
    comments,
    created_at,
    updated_at,
    closed_at,
  })
}

///|
/// Project one Issue page of the repository published as
/// `expected_node_id`/`expected_database_id`/`expected_name_with_owner`.
/// The page is accepted only when the response resolves exactly that
/// repository: another repository is refused, the same repository under
/// another ID representation needs an explicit re-publication, and a renamed
/// or transferred repository needs an explicit re-binding.
pub fn project_issues_response(
  body : Bytes,
  limits : PageLimits,
  expected_node_id : String,
  expected_database_id : Int64,
  expected_name_with_owner : String,
) -> Result[GraphqlIssuePage, GraphqlResponseIssue] {
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
    // The published repository is gone or no longer readable: never fall
    // back to a name lookup.
    ExplicitNull => return Err(RepositoryUnavailable)
    Missing => return Err(InvalidResponse)
  }
  let repository = match repository_of(node) {
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
  guard @decode.lookup(node, "issues") is Some(issues_cursor) &&
    @decode.open_object(issues_cursor) is Ok(issues) &&
    @decode.lookup(issues, "pageInfo") is Some(info_cursor) &&
    @decode.open_object(info_cursor) is Ok(info) &&
    @decode.lookup(info, "hasNextPage") is Some(next_cursor) &&
    @decode.boolean(next_cursor) is Ok(has_next_page) &&
    @decode.lookup(issues, "nodes") is Some(nodes_cursor) &&
    @decode.elements(nodes_cursor) is Ok(nodes) else {
    return Err(InvalidResponse)
  }
  let end_cursor = match @decode.field(info, "endCursor") {
    Present(value) =>
      match @decode.text(value) {
        Ok(text) if !text.is_empty() => Some(text)
        _ => return Err(InvalidResponse)
      }
    ExplicitNull => None
    Missing => return Err(InvalidResponse)
  }
  if has_next_page && end_cursor is None {
    return Err(MissingCursor)
  }
  if nodes.length() > limits.max_rows {
    return Err(BudgetExceeded)
  }
  let rows = []
  for item in nodes {
    guard @decode.open_object(item) is Ok(object) else {
      return Err(InvalidResponse)
    }
    match graphql_issue_row(object) {
      Ok(row) => rows.push(row)
      Err(issue) => return Err(Row(issue))
    }
  }
  Ok({ repository, rows, has_next_page, end_cursor, })
}
