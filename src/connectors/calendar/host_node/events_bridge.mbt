// Stateless provider wire/schema projections only. Selected Profile/query/page
// originals remain with the same Common runtime in calendar_events_bridge.mbt.

///|
#export_name("calendarEventsRequestSchemaWire")
pub fn calendar_events_request_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.CalendarEventsIssue] {
  @catalog.calendar_events_request_schema_wire(max_bytes, max_nodes, max_depth)
}

///|
#export_name("calendarEventsColumnNames")
pub fn calendar_events_column_names() -> Array[String] {
  @catalog.calendar_events_column_names()
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
