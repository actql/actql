// The GitHub provider's Node bridge. Every entry is pure: it receives what
// the common exchange observed (status, declared header pairs, body bytes)
// and returns a JSON text the Site driver reads. No entry performs I/O,
// holds a secret or decides authorization.

///|
fn headers_of(
  names : Array[String],
  values : Array[String],
) -> @catalog.HeaderObservation? {
  if names.length() != values.length() {
    return None
  }
  let entries = []
  for index = 0; index < names.length(); index = index + 1 {
    entries.push((names[index], values[index]))
  }
  Some({ entries, })
}

///|
fn optional_text(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
fn optional_number(value : Int64?) -> Json {
  match value {
    Some(number) => Json::number(number.to_double())
    None => Json::null()
  }
}

///|
fn issue_text(issue : @catalog.IssuePageIssue) -> Json {
  match issue {
    InvalidLimits => { "issue": "InvalidLimits" }
    BudgetExceeded => { "issue": "BudgetExceeded" }
    InvalidResponse => { "issue": "InvalidResponse" }
    MissingRequiredField(field) =>
      { "issue": "MissingRequiredField", "field": field.to_json() }
    NullRequiredField(field) =>
      { "issue": "NullRequiredField", "field": field.to_json() }
    InvalidField(field) => { "issue": "InvalidField", "field": field.to_json() }
  }
}

///|
fn basis_json(basis : @catalog.RateLimitBasis) -> Json {
  {
    "retryAfterSeconds": optional_number(basis.retry_after_seconds),
    "resetEpochSeconds": optional_number(basis.reset_epoch_seconds),
    "remaining": optional_number(basis.remaining),
    "resource": optional_text(basis.resource),
  }
}

///|
/// The fixed non-secret request headers, as `[[name, value], ...]`.
#export_name("githubRequestHeadersJson")
pub fn github_request_headers_json() -> String {
  let pairs : Array[Json] = @catalog.request_headers().map(pair => {
    [pair.0.to_json(), pair.1.to_json()]
  })
  Json::array(pairs).stringify()
}

///|
/// The declared response header names, as a JSON array.
#export_name("githubResponseHeadersJson")
pub fn github_response_headers_json() -> String {
  @catalog.response_headers.to_json().stringify()
}

///|
/// The REST API version this bridge states.
#export_name("githubApiVersion")
pub fn github_api_version() -> String {
  @catalog.api_version
}

///|
/// Classify a non-success status with its declared header observation.
#export_name("githubClassifyFailureJson")
pub fn github_classify_failure_json(
  status : Int,
  names : Array[String],
  values : Array[String],
) -> String {
  guard headers_of(names, values) is Some(headers) else {
    return ({ "kind": "InvalidHeaders" } : Json).stringify()
  }
  let json : Json = match @catalog.classify_failure(status, headers) {
    RateLimited(basis) => { "kind": "RateLimited", "basis": basis_json(basis) }
    PermissionDenied => { "kind": "PermissionDenied" }
    NotFound => { "kind": "NotFound" }
    Gone => { "kind": "Gone" }
    Unprocessable => { "kind": "Unprocessable" }
    ProviderUnavailable => { "kind": "ProviderUnavailable" }
    Unexpected(code) => { "kind": "Unexpected", "status": code.to_json() }
  }
  json.stringify()
}

///|
/// The rate-limit basis of any response (also a successful page).
#export_name("githubRateLimitBasisJson")
pub fn github_rate_limit_basis_json(
  names : Array[String],
  values : Array[String],
) -> String {
  guard headers_of(names, values) is Some(headers) else {
    return ({ "kind": "InvalidHeaders" } : Json).stringify()
  }
  basis_json(@catalog.rate_limit_basis(headers)).stringify()
}

///|
/// Project one 200 listing page: `{"page": {...}}` or `{"refused": {...}}`.
#export_name("githubIssuePageJson")
pub fn github_issue_page_json(
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
) -> String {
  let json : Json = match
    @catalog.project_issue_page(body, {
      max_bytes,
      max_nodes,
      max_depth,
      max_rows,
    }) {
    Ok(page) => {
      let rows : Array[Json] = page.rows.map(row => {
        "number": Json::number(row.number.to_double()),
        "node_id": row.node_id.to_json(),
        "title": row.title.to_json(),
        "state": row.state.to_json(),
        "body": optional_text(row.body),
        "author": optional_text(row.author),
        "comments": Json::number(row.comments.to_double()),
        "created_at": row.created_at.to_json(),
        "updated_at": row.updated_at.to_json(),
        "closed_at": optional_text(row.closed_at),
      })
      {
        "page": {
          "rows": Json::array(rows),
          "excludedPullRequests": page.excluded_pull_requests.to_json(),
          "providerItems": page.provider_items.to_json(),
        },
      }
    }
    Err(issue) => { "refused": issue_text(issue) }
  }
  json.stringify()
}

///|
/// The next page from an observed `Link` value (`has_link` false when the
/// response carried none): `{"next": null}`, `{"next": {...}}` or
/// `{"refused": "..."}`.
#export_name("githubNextPageJson")
pub fn github_next_page_json(
  has_link : Bool,
  link : String,
  origin : String,
  path : String,
  page : Int,
  max_locator_units : Int,
) -> String {
  let observed = if has_link { Some(link) } else { None }
  let json : Json = match
    @catalog.next_page(observed, origin, path, page, max_locator_units) {
    Ok(None) => { "next": Json::null() }
    Ok(Some(next)) => {
      let query : Array[Json] = next.query.map(pair => {
        [pair.0.to_json(), pair.1.to_json()]
      })
      {
        "next": {
          "path": next.path.to_json(),
          "query": Json::array(query),
          "page": next.page.to_json(),
        },
      }
    }
    Err(issue) => {
      let name = match issue {
        MalformedLink => "MalformedLink"
        ForeignOrigin => "ForeignOrigin"
        ForeignResource => "ForeignResource"
        NonAdvancingPage => "NonAdvancingPage"
        LocatorTooLong => "LocatorTooLong"
      }
      { "refused": name.to_json() }
    }
  }
  json.stringify()
}

///|
fn comment_request_json(
  request : Result[String, @catalog.CommentRequestIssue],
) -> String {
  let json : Json = match request {
    Ok(body) => { "body": body.to_json() }
    Err(InvalidSubjectId) => { "refused": "InvalidSubjectId" }
    Err(InvalidBody) => { "refused": "InvalidBody" }
  }
  json.stringify()
}

///|
/// The subject check body for one comment: `{"body": "..."}` or
/// `{"refused": "..."}`.
#export_name("githubCommentSubjectRequestJson")
pub fn github_comment_subject_request_json(subject_id : String) -> String {
  comment_request_json(@catalog.comment_subject_request(subject_id))
}

///|
/// The comment mutation body: `{"body": "..."}` or `{"refused": "..."}`.
#export_name("githubAddCommentRequestJson")
pub fn github_add_comment_request_json(
  subject_id : String,
  body : String,
) -> String {
  comment_request_json(@catalog.add_comment_request(subject_id, body))
}

///|
/// Project a subject check: `{"subject": {"node_id", "number"}}` or
/// `{"refused": {...}}`.
#export_name("githubCommentSubjectJson")
pub fn github_comment_subject_json(
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  subject_id : String,
  expected_node_id : String,
  expected_database_id : Double,
  expected_name_with_owner : String,
) -> String {
  let json : Json = match
    @catalog.project_comment_subject_response(
      body,
      { max_bytes, max_nodes, max_depth, max_rows: 1, },
      subject_id,
      expected_node_id,
      expected_database_id.to_int64(),
      expected_name_with_owner,
    ) {
    Ok(subject) =>
      {
        "subject": {
          "node_id": subject.node_id.to_json(),
          "number": Json::number(subject.number.to_double()),
        },
      }
    Err(issue) => { "refused": graphql_issue_name(issue) }
  }
  json.stringify()
}

///|
/// Classify a comment mutation response: `{"outcome": "Created", "id": n,
/// "nodeId": "..."}`, `{"outcome": "Refused", "status": n}`,
/// `{"outcome": "Rejected", "type": "..."}` or `{"outcome": "Unknown"}`.
#export_name("githubCommentOutcomeJson")
pub fn github_comment_outcome_json(
  status : Int,
  names : Array[String],
  values : Array[String],
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  subject_id : String,
) -> String {
  guard headers_of(names, values) is Some(headers) else {
    return ({ "outcome": "Unknown" } : Json).stringify()
  }
  let json : Json = match
    @catalog.classify_comment_response(
      status,
      headers,
      body,
      { max_bytes, max_nodes, max_depth, max_rows: 1, },
      subject_id,
    ) {
    Created(id~, node_id~) =>
      {
        "outcome": "Created",
        "id": Json::number(id.to_double()),
        "nodeId": node_id.to_json(),
      }
    Refused(status~) => { "outcome": "Refused", "status": status.to_json() }
    Rejected(kind~) => { "outcome": "Rejected", "type": kind.to_json() }
    Unknown => { "outcome": "Unknown" }
  }
  json.stringify()
}

///|
fn graphql_issue_name(issue : @catalog.GraphqlResponseIssue) -> Json {
  match issue {
    InvalidResponse => { "kind": "InvalidResponse" }
    RateLimited => { "kind": "RateLimited" }
    Errors(kind) => { "kind": "Errors", "type": kind.to_json() }
    RepositoryUnavailable => { "kind": "RepositoryUnavailable" }
    SubjectUnavailable => { "kind": "SubjectUnavailable" }
    ForeignSubject => { "kind": "ForeignSubject" }
    WrongType(name) => { "kind": "WrongType", "type": name.to_json() }
    ForeignRepository => { "kind": "ForeignRepository" }
    IdRepresentationChanged => { "kind": "IdRepresentationChanged" }
    BindingChanged => { "kind": "BindingChanged" }
    MissingCursor => { "kind": "MissingCursor" }
    BudgetExceeded => { "kind": "BudgetExceeded" }
    Row(row) => { "kind": "Row", "row": issue_text(row) }
  }
}

///|
fn graphql_repository_json(repository : @catalog.GraphqlRepository) -> Json {
  {
    "node_id": repository.node_id.to_json(),
    "database_id": Json::number(repository.database_id.to_double()),
    "name_with_owner": repository.name_with_owner.to_json(),
  }
}

///|
/// The publication lookup body for `owner/name`: the fixed query only.
#export_name("githubRepositoryRequest")
pub fn github_repository_request(owner : String, name : String) -> String {
  @catalog.repository_request(owner, name)
}

///|
/// One Issue page request body for the published node ID, or a refusal:
/// `{"body": "..."}` or `{"refused": "..."}`. Callers supply variables only.
#export_name("githubIssuesRequestJson")
pub fn github_issues_request_json(
  node_id : String,
  first : Int,
  has_after : Bool,
  after : String,
  state : String,
  labels : Array[String],
  has_since : Bool,
  since : String,
) -> String {
  let json : Json = match
    @catalog.issues_request(
      node_id,
      first,
      if has_after {
        Some(after)
      } else {
        None
      },
      { state, labels, since: if has_since { Some(since) } else { None }, },
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
  json.stringify()
}

///|
/// Project one Issue page of the published repository:
/// `{"page": {...}}` or `{"refused": {"kind": ...}}`.
#export_name("githubIssuesPageJson")
pub fn github_issues_page_json(
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  expected_node_id : String,
  expected_database_id : Double,
  expected_name_with_owner : String,
) -> String {
  let json : Json = match
    @catalog.project_issues_response(
      body,
      { max_bytes, max_nodes, max_depth, max_rows, },
      expected_node_id,
      expected_database_id.to_int64(),
      expected_name_with_owner,
    ) {
    Ok(page) => {
      let rows : Array[Json] = page.rows.map(row => {
        "number": Json::number(row.number.to_double()),
        "node_id": row.node_id.to_json(),
        "title": row.title.to_json(),
        "state": row.state.to_json(),
        "body": optional_text(row.body),
        "author": optional_text(row.author),
        "comments": Json::number(row.comments.to_double()),
        "created_at": row.created_at.to_json(),
        "updated_at": row.updated_at.to_json(),
        "closed_at": optional_text(row.closed_at),
      })
      {
        "page": {
          "rows": Json::array(rows),
          "hasNextPage": page.has_next_page.to_json(),
          "endCursor": optional_text(page.end_cursor),
          "repository": graphql_repository_json(page.repository),
        },
      }
    }
    Err(issue) => { "refused": graphql_issue_name(issue) }
  }
  json.stringify()
}

///|
/// Project a publication lookup: `{"repository": {...}}` or `{"refused": ...}`.
#export_name("githubRepositoryResponseJson")
pub fn github_repository_response_json(body : Bytes, max_bytes : Int) -> String {
  let json : Json = match
    @catalog.project_repository_response(body, {
      max_bytes,
      max_nodes: 20000,
      max_depth: 32,
      max_rows: 1,
    }) {
    Ok(repository) => { "repository": graphql_repository_json(repository) }
    Err(issue) => { "refused": graphql_issue_name(issue) }
  }
  json.stringify()
}
