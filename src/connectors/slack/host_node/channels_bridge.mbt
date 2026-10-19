///|
#export_name("slackProjectChannelList")
pub fn slack_project_channel_list(
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_cursor_bytes : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
) -> Result[@catalog.SlackChannelListPage, @catalog.SlackChannelListIssue] {
  @catalog.project_slack_channel_list(body, {
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
#export_name("slackProjectHistoryConversationList")
pub fn slack_project_history_conversation_list(
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_cursor_bytes : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
) -> Result[@catalog.SlackChannelListPage, @catalog.SlackChannelListIssue] {
  @catalog.project_slack_history_conversation_list(body, {
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
#export_name("slackChannelListRowsWire")
pub fn slack_channel_list_rows_wire(
  page : @catalog.SlackChannelListPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.SlackChannelListIssue] {
  @catalog.slack_channel_list_rows_wire(
    page, names, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("slackChannelListMetadataJson")
pub fn slack_channel_list_metadata_json(
  page : @catalog.SlackChannelListPage,
) -> String {
  let next : Json = match page.next_cursor {
    Some(cursor) => cursor.to_json()
    None => Json::null()
  }
  (
    {
      "rowCount": @catalog.slack_channel_list_row_count(page).to_json(),
      "nextCursor": next,
    } : Json).stringify()
}

///|
#export_name("slackChannelListColumnNames")
pub fn slack_channel_list_column_names() -> Array[String] {
  @catalog.slack_channel_list_column_names()
}

///|
#export_name("slackChannelListSchemaWire")
pub fn slack_channel_list_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.SlackChannelListIssue] {
  @catalog.slack_channel_list_schema_wire(max_bytes, max_nodes, max_depth)
}

///|
#export_name("slackChannelListRelationFactsWire")
pub fn slack_channel_list_relation_facts_wire() -> String {
  @catalog.slack_channel_list_facts_wire()
}

///|
#export_name("slackChannelListIds")
pub fn slack_channel_list_ids(
  page : @catalog.SlackChannelListPage,
) -> Array[String] {
  @catalog.slack_channel_list_ids(page)
}
