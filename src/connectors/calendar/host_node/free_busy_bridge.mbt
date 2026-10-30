///|
#export_name("calendarPrepareFreeBusyQuery")
pub fn calendar_prepare_free_busy_query(
  calendars : Array[String],
  start : String,
  end : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_calendars : Int,
  max_rows : Int,
  max_request_bytes : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
) -> Result[@catalog.CalendarFreeBusyQuery, @catalog.CalendarFreeBusyIssue] {
  @catalog.prepare_calendar_free_busy_query(calendars, start, end, {
    max_bytes,
    max_nodes,
    max_depth,
    max_calendars,
    max_rows,
    max_request_bytes,
    max_value_nodes,
    max_value_text_bytes,
  })
}

///|
#export_name("calendarFreeBusyRequestWire")
pub fn calendar_free_busy_request_wire(
  query : @catalog.CalendarFreeBusyQuery,
) -> String {
  @catalog.calendar_free_busy_request_wire(query)
}

///|
#export_name("calendarProjectFreeBusy")
pub fn calendar_project_free_busy(
  bytes : Bytes,
  query : @catalog.CalendarFreeBusyQuery,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_calendars : Int,
  max_rows : Int,
  max_request_bytes : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
) -> Result[@catalog.CalendarFreeBusyPage, @catalog.CalendarFreeBusyIssue] {
  @catalog.project_calendar_free_busy(bytes, query, {
    max_bytes,
    max_nodes,
    max_depth,
    max_calendars,
    max_rows,
    max_request_bytes,
    max_value_nodes,
    max_value_text_bytes,
  })
}

///|
#export_name("calendarFreeBusyMatchesQuery")
pub fn calendar_free_busy_matches_query(
  page : @catalog.CalendarFreeBusyPage,
  query : @catalog.CalendarFreeBusyQuery,
) -> Bool {
  @catalog.calendar_free_busy_matches_query(page, query)
}

///|
#export_name("calendarFreeBusyRowsWire")
pub fn calendar_free_busy_rows_wire(
  page : @catalog.CalendarFreeBusyPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.CalendarFreeBusyIssue] {
  @catalog.calendar_free_busy_rows_wire(
    page, names, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("calendarFreeBusyMetadataJson")
pub fn calendar_free_busy_metadata_json(
  page : @catalog.CalendarFreeBusyPage,
) -> String {
  (
    {
      "responseSha256": page.response_sha256.to_json(),
      "rowCount": @catalog.calendar_free_busy_row_count(page).to_json(),
    } : Json).stringify()
}

///|
#export_name("calendarFreeBusySchemaWire")
pub fn calendar_free_busy_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.CalendarFreeBusyIssue] {
  @catalog.calendar_free_busy_schema_wire(max_bytes, max_nodes, max_depth)
}

///|
#export_name("calendarFreeBusyColumnNames")
pub fn calendar_free_busy_column_names() -> Array[String] {
  @catalog.calendar_free_busy_column_names()
}

///|
#export_name("calendarFreeBusyRelationFactsWire")
pub fn calendar_free_busy_relation_facts_wire() -> String {
  @catalog.calendar_free_busy_facts_wire()
}

///|
#export_name("calendarPrepareFreeBusyRequest")
pub fn calendar_prepare_free_busy_request(
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_calendars : Int,
  max_rows : Int,
  max_request_bytes : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
) -> Result[@catalog.CalendarFreeBusyQuery, @catalog.CalendarFreeBusyIssue] {
  @catalog.prepare_calendar_free_busy_request(wire, {
    max_bytes,
    max_nodes,
    max_depth,
    max_calendars,
    max_rows,
    max_request_bytes,
    max_value_nodes,
    max_value_text_bytes,
  })
}

///|
#export_name("calendarFreeBusyRequestSchemaWire")
pub fn calendar_free_busy_request_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.CalendarFreeBusyIssue] {
  @catalog.calendar_free_busy_request_schema_wire(
    max_bytes, max_nodes, max_depth,
  )
}
