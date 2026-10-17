///|
// Vendor observation only. It is neither a Credential grant nor evidence that
// a different request, token, workspace or later use is authorized.
pub struct SlackWorkspaceIdentity {
  priv team_id : String
  user_id : String
  response_sha256 : String
}

///|
fn workspace_identity_text(
  root : @decode.ObjectView,
  name : String,
  max_text_bytes : Int,
) -> Result[String, SlackUserListIssue] {
  guard @decode.lookup(root, name) is Some(cursor) &&
    @decode.text(cursor) is Ok(text) &&
    !text.is_empty() else {
    return Err(InvalidCell(name))
  }
  match
    @admitted.admit_usage(
      @contract.primitive(@contract.StringType, nullable=false),
      cursor,
      { max_nodes: 1, max_depth: 1, max_text_bytes, },
    ) {
    Ok(_) => Ok(text)
    Err(_) => Err(BudgetExceeded)
  }
}

///|
pub fn project_slack_workspace_identity(
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_identity_bytes : Int,
) -> Result[SlackWorkspaceIdentity, SlackUserListIssue] {
  if max_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 ||
    max_identity_bytes <= 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > max_bytes {
    return Err(BudgetExceeded)
  }
  let node = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(node) => node
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  let cursor = match
    @decode.admit(node, {
      max_nodes,
      max_depth,
      max_string_bytes: max_bytes,
      max_total_string_bytes: max_bytes,
    }) {
    Ok(cursor) => cursor
    Err(issue) =>
      return Err(
        if issue.kind == @decode.BudgetExceeded {
          BudgetExceeded
        } else {
          InvalidResponse
        },
      )
  }
  guard @decode.open_object(cursor) is Ok(root) &&
    @decode.lookup(root, "ok") is Some(ok) &&
    @decode.boolean(ok) is Ok(true) &&
    @decode.lookup(root, "error") is None else {
    return Err(InvalidResponse)
  }
  let team_id = match
    workspace_identity_text(root, "team_id", max_identity_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let user_id = match
    workspace_identity_text(root, "user_id", max_identity_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ team_id, user_id, response_sha256: @sha.hex(bytes), })
}

///|
pub fn slack_workspace_identity_matches(
  identity : SlackWorkspaceIdentity,
  workspace_id : String,
) -> Bool {
  identity.team_id == workspace_id
}
