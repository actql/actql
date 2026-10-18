///|
/// Native PullRequest fields additional to the shared Issue-shaped columns.
/// These values are observations, not merge permission or mutation selectors.
pub(all) struct PullRequestNativeFields {
  base : String
  head : String
  draft : Bool
  mergeable : Bool?
  merged_at : String?
  merged_by : String?
  review_decision : String?
} derive(Eq, Debug)

///|
pub(all) struct PullRequestRow {
  common : IssueRow
  native : PullRequestNativeFields
} derive(Eq, Debug)

///|
pub(all) struct GraphqlPullRequestPage {
  repository : GraphqlRepository
  rows : Array[PullRequestRow]
  pending_fields : Array[IssueFieldContinuation]
  has_next_page : Bool
  end_cursor : String?
} derive(Eq, Debug)

///|
/// Admit the same original repository and requested native PullRequest shape.
/// Incomplete assignee/label fields remain pending, never complete row output.
pub fn project_pull_requests_response(
  body : Bytes,
  limits : PageLimits,
  expected_node_id : String,
  expected_database_id : Int64,
  expected_name_with_owner : String,
) -> Result[GraphqlPullRequestPage, GraphqlResponseIssue] {
  project_issue_like_response(
    body, limits, expected_node_id, expected_database_id, expected_name_with_owner,
    true,
  ).map(pair => {
    let (page, native) = pair
    let rows = []
    for index, common in page.rows {
      rows.push({ common, native: native[index], })
    }
    {
      repository: page.repository,
      rows,
      pending_fields: page.pending_fields,
      has_next_page: page.has_next_page,
      end_cursor: page.end_cursor,
    }
  })
}

///|
fn graphql_nullable_actor(
  object : @decode.ObjectView,
  name : String,
) -> Result[String?, IssuePageIssue] {
  match @decode.field(object, name) {
    Missing => Err(MissingRequiredField(name))
    ExplicitNull => Ok(None)
    Present(cursor) => {
      guard @decode.open_object(cursor) is Ok(actor) else {
        return Err(InvalidField(name))
      }
      graphql_text(actor, "login").map(value => Some(value))
    }
  }
}

///|
pub fn graphql_pull_request_fields(
  object : @decode.ObjectView,
) -> Result[PullRequestNativeFields, IssuePageIssue] {
  let base = match graphql_text(object, "baseRefName") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let head = match graphql_text(object, "headRefName") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let draft_cursor = match required_field(object, "isDraft") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let draft = match @decode.boolean(draft_cursor) {
    Ok(value) => value
    Err(_) => return Err(InvalidField("isDraft"))
  }
  let mergeable = match graphql_text(object, "mergeable") {
    Ok("MERGEABLE") => Some(true)
    Ok("CONFLICTING") => Some(false)
    Ok("UNKNOWN") => None
    Ok(_) => return Err(InvalidField("mergeable"))
    Err(issue) => return Err(issue)
  }
  let merged_at = match graphql_timestamp(object, "mergedAt", true) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let merged_by = match graphql_nullable_actor(object, "mergedBy") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let review_decision = match nullable_text(object, "reviewDecision") {
    Ok(None) => None
    Ok(Some("APPROVED")) => Some("approved")
    Ok(Some("CHANGES_REQUESTED")) => Some("changes_requested")
    Ok(Some("REVIEW_REQUIRED")) => Some("review_required")
    Ok(Some(_)) => return Err(InvalidField("reviewDecision"))
    Err(issue) => return Err(issue)
  }
  Ok({ base, head, draft, mergeable, merged_at, merged_by, review_decision, })
}
