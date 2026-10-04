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
/// Classify a comment-create response: `{"outcome": "Created", "id": n,
/// "nodeId": "..."}`, `{"outcome": "Refused", "status": n}` or
/// `{"outcome": "Unknown"}`.
#export_name("githubCommentOutcomeJson")
pub fn github_comment_outcome_json(
  status : Int,
  names : Array[String],
  values : Array[String],
  body : Bytes,
  max_bytes : Int,
) -> String {
  guard headers_of(names, values) is Some(headers) else {
    return ({ "outcome": "Unknown" } : Json).stringify()
  }
  let json : Json = match
    @catalog.classify_comment_response(status, headers, body, max_bytes) {
    Created(id~, node_id~) =>
      {
        "outcome": "Created",
        "id": Json::number(id.to_double()),
        "nodeId": node_id.to_json(),
      }
    Refused(status~) => { "outcome": "Refused", "status": status.to_json() }
    Unknown => { "outcome": "Unknown" }
  }
  json.stringify()
}

///|
/// The repository identity of a `GET /repos/{owner}/{repo}` body, or `null`.
#export_name("githubRepositoryJson")
pub fn github_repository_json(body : Bytes, max_bytes : Int) -> String {
  match @catalog.project_repository(body, max_bytes) {
    Some(identity) =>
      (
        {
          "id": Json::number(identity.id.to_double()),
          "node_id": identity.node_id.to_json(),
          "owner": identity.owner.to_json(),
          "name": identity.name.to_json(),
        } : Json).stringify()
    None => "null"
  }
}
