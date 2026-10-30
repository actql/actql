///|
/// The caller must supply its same selected original Profile. This provider
/// bridge neither reconstructs it from JSON nor issues a Source acquisition.
#export_name("calendarPrepareEventsQuery")
pub fn calendar_prepare_events_query(
  calendar_id : String,
  time_min : String,
  time_max : String,
  time_zone : String,
  profile : @calendar_profile.Profile,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_identity_bytes : Int,
  max_cursor_bytes : Int,
  max_attendees : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
  max_resolution_work : Int,
) -> Result[@catalog.CalendarEventsQuery, @catalog.CalendarEventsIssue] {
  @catalog.prepare_calendar_events_query(
    calendar_id,
    time_min,
    time_max,
    time_zone,
    profile,
    {
      max_bytes,
      max_nodes,
      max_depth,
      max_rows,
      max_identity_bytes,
      max_cursor_bytes,
      max_attendees,
      max_value_nodes,
      max_value_text_bytes,
      max_resolution_work,
    },
  )
}

///|
#export_name("calendarEventsQueryWire")
pub fn calendar_events_query_wire(
  query : @catalog.CalendarEventsQuery,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.CalendarEventsIssue] {
  @catalog.calendar_events_query_wire(query, max_bytes, max_nodes, max_depth)
}

///|
#export_name("calendarProjectEvents")
pub fn calendar_project_events(
  bytes : Bytes,
  query : @catalog.CalendarEventsQuery,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_identity_bytes : Int,
  max_cursor_bytes : Int,
  max_attendees : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
  max_resolution_work : Int,
) -> Result[@catalog.CalendarEventsPage, @catalog.CalendarEventsIssue] {
  @catalog.project_calendar_events(bytes, query, {
    max_bytes,
    max_nodes,
    max_depth,
    max_rows,
    max_identity_bytes,
    max_cursor_bytes,
    max_attendees,
    max_value_nodes,
    max_value_text_bytes,
    max_resolution_work,
  })
}

///|
#export_name("calendarEventsMatchesQuery")
pub fn calendar_events_matches_query(
  page : @catalog.CalendarEventsPage,
  query : @catalog.CalendarEventsQuery,
) -> Bool {
  @catalog.calendar_events_matches_query(page, query)
}

///|
#export_name("calendarEventsColumnNames")
pub fn calendar_events_column_names() -> Array[String] {
  @catalog.calendar_events_column_names()
}

///|
#export_name("calendarEventsRowsWire")
pub fn calendar_events_rows_wire(
  page : @catalog.CalendarEventsPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.CalendarEventsIssue] {
  @catalog.calendar_events_rows_wire(
    page, names, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("calendarEventsMetadataWire")
pub fn calendar_events_metadata_wire(
  page : @catalog.CalendarEventsPage,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.CalendarEventsIssue] {
  @catalog.calendar_events_metadata_wire(page, max_bytes, max_nodes, max_depth)
}

///|
#export_name("calendarEventsSchemaWire")
pub fn calendar_events_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.CalendarEventsIssue] {
  @catalog.calendar_events_schema_wire(max_bytes, max_nodes, max_depth)
}

///|
#export_name("calendarEventsFactsWire")
pub fn calendar_events_facts_wire() -> String {
  @catalog.calendar_events_facts_wire()
}
