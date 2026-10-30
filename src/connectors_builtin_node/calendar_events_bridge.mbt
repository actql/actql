// Calendar Events share the Common runtime which issued their original
// CheckEnvironment/Profile and all retained Map values. Keep opaque query/page
// operations together here; a separately compiled provider namespace is not an
// original-profile transport. No profile admission or physical authority.

///|
/// Return only the Profile retained by this original checker. This neither
/// admits provider JSON nor selects a default, installation, Source or grant.
/// The Host still owns passing its same checked-environment original here.
#export_name("calendarEventsProfileFromEnvironment")
pub fn client_calendar_events_profile_from_environment(
  environment : @program_check.CheckEnvironment,
) -> Result[@calendar_profile.Profile, @calendar_catalog.CalendarEventsIssue] {
  match @program_check.checking_environment_calendar_profile(environment) {
    Some(selected) => Ok(@check_environment.selected_calendar_profile(selected))
    None => Err(@calendar_catalog.TimeZoneUnavailable)
  }
}

///|
#export_name("calendarEventsQueryWire")
pub fn client_calendar_events_query_wire(
  query : @calendar_catalog.CalendarEventsQuery,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @calendar_catalog.CalendarEventsIssue] {
  @calendar_catalog.calendar_events_query_wire(
    query, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("calendarEventsQueryFromRequestWire")
pub fn client_calendar_events_query_from_request_wire(
  wire : String,
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
) -> Result[
  @calendar_catalog.CalendarEventsQuery,
  @calendar_catalog.CalendarEventsIssue,
] {
  @calendar_catalog.prepare_calendar_events_request(wire, profile, {
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
#export_name("calendarEventsRequestSchemaWire")
pub fn client_calendar_events_request_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @calendar_catalog.CalendarEventsIssue] {
  @calendar_catalog.calendar_events_request_schema_wire(
    max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("calendarProjectEvents")
pub fn client_calendar_project_events(
  bytes : Bytes,
  query : @calendar_catalog.CalendarEventsQuery,
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
) -> Result[
  @calendar_catalog.CalendarEventsPage,
  @calendar_catalog.CalendarEventsIssue,
] {
  @calendar_catalog.project_calendar_events(bytes, query, {
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
pub fn client_calendar_events_matches_query(
  page : @calendar_catalog.CalendarEventsPage,
  query : @calendar_catalog.CalendarEventsQuery,
) -> Bool {
  @calendar_catalog.calendar_events_matches_query(page, query)
}

///|
#export_name("calendarEventsColumnNames")
pub fn client_calendar_events_column_names() -> Array[String] {
  @calendar_catalog.calendar_events_column_names()
}

///|
#export_name("calendarEventsRowsWire")
pub fn client_calendar_events_rows_wire(
  page : @calendar_catalog.CalendarEventsPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @calendar_catalog.CalendarEventsIssue] {
  @calendar_catalog.calendar_events_rows_wire(
    page, names, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("calendarEventsMetadataWire")
pub fn client_calendar_events_metadata_wire(
  page : @calendar_catalog.CalendarEventsPage,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @calendar_catalog.CalendarEventsIssue] {
  @calendar_catalog.calendar_events_metadata_wire(
    page, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("calendarEventsSchemaWire")
pub fn client_calendar_events_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @calendar_catalog.CalendarEventsIssue] {
  @calendar_catalog.calendar_events_schema_wire(max_bytes, max_nodes, max_depth)
}

///|
#export_name("calendarEventsFactsWire")
pub fn client_calendar_events_facts_wire() -> String {
  @calendar_catalog.calendar_events_facts_wire()
}
