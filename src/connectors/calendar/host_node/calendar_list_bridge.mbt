///|
#export_name("calendarProjectCalendarList")
pub fn calendar_project_calendar_list(
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_cursor_units : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
) -> Result[@catalog.CalendarListPage, @catalog.CalendarListIssue] {
  @catalog.project_calendar_list(bytes, {
    max_bytes,
    max_nodes,
    max_depth,
    max_rows,
    max_cursor_units,
    max_value_nodes,
    max_value_text_bytes,
  })
}

///|
#export_name("calendarListRowsWire")
pub fn calendar_list_rows_wire(
  page : @catalog.CalendarListPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.CalendarListIssue] {
  @catalog.calendar_list_rows_wire(page, names, max_bytes, max_nodes, max_depth)
}

///|
#export_name("calendarListMetadataJson")
pub fn calendar_list_metadata_json(page : @catalog.CalendarListPage) -> String {
  (
    {
      "responseSha256": page.response_sha256.to_json(),
      "rowCount": @catalog.calendar_list_row_count(page).to_json(),
      "ids": @catalog.calendar_list_ids(page).to_json(),
      "nextPageToken": match page.next_page_token {
        Some(value) => value.to_json()
        None => Json::null()
      },
    } : Json).stringify()
}

///|
#export_name("calendarListSchemaWire")
pub fn calendar_list_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.CalendarListIssue] {
  @catalog.calendar_list_schema_wire(max_bytes, max_nodes, max_depth)
}

///|
#export_name("calendarListRelationFactsWire")
pub fn calendar_list_relation_facts_wire() -> String {
  @catalog.calendar_list_facts_wire()
}
