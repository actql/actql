///|
#export_name("notionProjectUserList")
pub fn notion_project_user_list(
  body : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_cursor_bytes : Int,
  max_identity_bytes : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
) -> Result[@catalog.NotionUserListPage, @catalog.NotionUserListIssue] {
  @catalog.project_notion_user_list(body, {
    max_bytes,
    max_nodes,
    max_depth,
    max_rows,
    max_cursor_bytes,
    max_identity_bytes,
    max_value_nodes,
    max_value_text_bytes,
  })
}

///|
#export_name("notionUserListRowsWire")
pub fn notion_user_list_rows_wire(
  page : @catalog.NotionUserListPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.NotionUserListIssue] {
  @catalog.notion_user_list_rows_wire(
    page, names, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("notionUserListMetadataJson")
pub fn notion_user_list_metadata_json(
  page : @catalog.NotionUserListPage,
) -> String {
  let next : Json = match page.next_cursor {
    Some(cursor) => cursor.to_json()
    None => Json::null()
  }
  (
    {
      "rowCount": @catalog.notion_user_list_row_count(page).to_json(),
      "nextCursor": next,
    } : Json).stringify()
}

///|
#export_name("notionUserListColumnNames")
pub fn notion_user_list_column_names() -> Array[String] {
  @catalog.notion_user_list_column_names()
}

///|
#export_name("notionUserListSchemaWire")
pub fn notion_user_list_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.NotionUserListIssue] {
  @catalog.notion_user_list_schema_wire(max_bytes, max_nodes, max_depth)
}

///|
#export_name("notionUserListIds")
pub fn notion_user_list_ids(
  page : @catalog.NotionUserListPage,
) -> Array[String] {
  @catalog.notion_user_list_ids(page)
}
