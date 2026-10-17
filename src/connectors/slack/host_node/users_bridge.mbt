///|
#export_name("slackProjectUserList")
pub fn slack_project_user_list(
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_cursor_bytes : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
) -> Result[@catalog.SlackUserListPage, @catalog.SlackUserListIssue] {
  @catalog.project_slack_user_list(body, {
    max_bytes,
    max_nodes,
    max_depth,
    max_rows,
    max_cursor_bytes,
    max_value_nodes,
    max_value_text_bytes,
  })
}

///|
#export_name("slackUserListRowsWire")
pub fn slack_user_list_rows_wire(
  page : @catalog.SlackUserListPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.SlackUserListIssue] {
  @catalog.slack_user_list_rows_wire(
    page, names, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("slackUserListMetadataJson")
pub fn slack_user_list_metadata_json(
  page : @catalog.SlackUserListPage,
) -> String {
  let next : Json = match page.next_cursor {
    Some(cursor) => cursor.to_json()
    None => Json::null()
  }
  (
    {
      "rowCount": @catalog.slack_user_list_row_count(page).to_json(),
      "nextCursor": next,
    } : Json).stringify()
}

///|
#export_name("slackUserListColumnNames")
pub fn slack_user_list_column_names() -> Array[String] {
  @catalog.slack_user_list_column_names()
}

///|
#export_name("slackUserListSchemaWire")
pub fn slack_user_list_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.SlackUserListIssue] {
  @catalog.slack_user_list_schema_wire(max_bytes, max_nodes, max_depth)
}

///|
#export_name("slackUserListRelationFactsWire")
pub fn slack_user_list_relation_facts_wire() -> String {
  @catalog.slack_user_list_facts_wire()
}

///|
#export_name("slackUserListIdsJson")
pub fn slack_user_list_ids_json(page : @catalog.SlackUserListPage) -> String {
  @catalog.slack_user_list_ids(page).to_json().stringify()
}

///|
#export_name("slackProjectWorkspaceIdentity")
pub fn slack_project_workspace_identity(
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_identity_bytes : Int,
) -> Result[@catalog.SlackWorkspaceIdentity, @catalog.SlackUserListIssue] {
  @catalog.project_slack_workspace_identity(
    bytes, max_bytes, max_nodes, max_depth, max_identity_bytes,
  )
}

///|
#export_name("slackWorkspaceIdentityMatches")
pub fn slack_workspace_identity_matches(
  identity : @catalog.SlackWorkspaceIdentity,
  workspace_id : String,
) -> Bool {
  @catalog.slack_workspace_identity_matches(identity, workspace_id)
}
