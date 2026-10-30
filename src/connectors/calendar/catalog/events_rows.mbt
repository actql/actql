///|
pub struct CalendarEventsPage {
  response_sha256 : String
  next_page_token : String?
  priv query : CalendarEventsQuery
  priv rows : Array[Array[@admitted.CheckedValue]]
}

///|
fn events_columns() -> Array[(String, @contract.Contract)] {
  let string = @contract.primitive(@contract.StringType, nullable=true)
  let timestamp = @contract.primitive(@contract.TimestampType, nullable=true)
  let attendee = @contract.object_contract(
    [
      ("email", @contract.primitive(@contract.StringType, nullable=false)),
      (
        "response_status",
        @contract.primitive(@contract.StringType, nullable=false),
      ),
      ("optional", @contract.primitive(@contract.BooleanType, nullable=false)),
    ],
    nullable=false,
    max_fields=3,
    max_name_bytes=64,
  ).unwrap()
  [
    ("id", @contract.primitive(@contract.StringType, nullable=false)),
    ("ical_uid", string),
    ("calendar_id", @contract.primitive(@contract.StringType, nullable=false)),
    ("summary", string),
    ("description", string),
    ("start", timestamp),
    ("end", timestamp),
    ("all_day", @contract.primitive(@contract.BooleanType, nullable=true)),
    ("location", string),
    ("status", string),
    ("organizer", string),
    ("attendees", @contract.array_contract(attendee, nullable=true).unwrap()),
    ("recurring_event_id", string),
    ("created", timestamp),
    ("updated", timestamp),
    ("etag", string),
  ]
}

///|
pub fn calendar_events_column_names() -> Array[String] {
  events_columns().map(column => column.0)
}

///|
fn events_text_value(
  text : String,
  limits : CalendarEventsLimits,
) -> Result[@admitted.Value, CalendarEventsIssue] {
  match @admitted.text_value(text, limits.max_bytes) {
    Some(value) => Ok(value)
    None => Err(BudgetExceeded)
  }
}

///|
fn events_nullable_text(
  object : @decode.ObjectView,
  native_name : String,
  column : String,
  limits : CalendarEventsLimits,
) -> Result[@admitted.Value, CalendarEventsIssue] {
  match @decode.field(object, native_name) {
    Missing | ExplicitNull => Ok(@admitted.null_value())
    Present(value) =>
      match @decode.text(value) {
        Ok(text) => events_text_value(text, limits)
        Err(_) => Err(InvalidCell(column))
      }
  }
}

///|
fn events_timestamp_value(text : String) -> @admitted.Value {
  @admitted.checked_timestamp_value(
    text,
    @contract.primitive(@contract.TimestampType, nullable=false),
  ).unwrap().value
}

///|
fn events_nullable_timestamp(
  object : @decode.ObjectView,
  name : String,
) -> Result[@admitted.Value, CalendarEventsIssue] {
  match @decode.field(object, name) {
    Missing | ExplicitNull => Ok(@admitted.null_value())
    Present(value) => {
      guard @decode.text(value) is Ok(text) &&
        @admitted.normalize_timestamp_text(text, 40) is Some(instant) else {
        return Err(InvalidCell(name))
      }
      Ok(events_timestamp_value(instant))
    }
  }
}

///|
fn events_default_boolean(
  object : @decode.ObjectView,
  name : String,
) -> Result[Bool, CalendarEventsIssue] {
  match @decode.field(object, name) {
    Missing => Ok(false)
    Present(value) =>
      match @decode.boolean(value) {
        Ok(value) => Ok(value)
        Err(_) => Err(InvalidCell(name))
      }
    ExplicitNull => Err(InvalidCell(name))
  }
}

///|
fn events_temporal_values(
  row : @decode.ObjectView,
  query : CalendarEventsQuery,
  remaining_work : Int,
) -> Result[
  (@admitted.Value, @admitted.Value, @admitted.Value, Int),
  CalendarEventsIssue,
] {
  let unspecified = match events_default_boolean(row, "endTimeUnspecified") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut used = 0
  let start = match @decode.field(row, "start") {
    Missing | ExplicitNull => None
    Present(value) =>
      match
        event_endpoint(value, query.time_zone, query.profile, remaining_work) {
        Ok((text, all_day, work)) => {
          used += work
          Some((text, all_day, value))
        }
        Err(issue) => return Err(EventTime(issue))
      }
  }
  // Validate a supplied compatibility end as well. It is never returned as
  // the actual end when endTimeUnspecified is true.
  let end = match @decode.field(row, "end") {
    Missing | ExplicitNull => None
    Present(value) =>
      match
        event_endpoint(
          value,
          query.time_zone,
          query.profile,
          remaining_work - used,
        ) {
        Ok((text, all_day, work)) => {
          used += work
          Some((text, all_day, value))
        }
        Err(issue) => return Err(EventTime(issue))
      }
  }
  match (start, end) {
    (
      Some((first, first_all_day, first_original)),
      Some((last, last_all_day, last_original)),
    ) => {
      if first_all_day != last_all_day {
        return Err(EventTime(MixedTimeKinds))
      }
      if !unspecified {
        if first_all_day &&
          event_time_text(@decode.open_object(first_original).unwrap(), "date").unwrap() >
          event_time_text(@decode.open_object(last_original).unwrap(), "date").unwrap() {
          return Err(EventTime(ReversedInterval))
        }
        if @admitted.compare_timestamp_text(first, last).unwrap() > 0 {
          return Err(EventTime(ReversedInterval))
        }
      }
    }
    _ => ()
  }
  Ok(
    (
      match start {
        Some((text, _, _)) => events_timestamp_value(text)
        None => @admitted.null_value()
      },
      if unspecified {
        @admitted.null_value()
      } else {
        match end {
          Some((text, _, _)) => events_timestamp_value(text)
          None => @admitted.null_value()
        }
      },
      match start {
        Some((_, all_day, _)) => @admitted.boolean_value(all_day)
        None => @admitted.null_value()
      },
      used,
    ),
  )
}

///|
fn events_organizer(
  row : @decode.ObjectView,
  limits : CalendarEventsLimits,
) -> Result[@admitted.Value, CalendarEventsIssue] {
  match @decode.field(row, "organizer") {
    Missing | ExplicitNull => Ok(@admitted.null_value())
    Present(value) => {
      guard @decode.open_object(value) is Ok(organizer) else {
        return Err(InvalidCell("organizer"))
      }
      // No identity/display-name fallback or email normalization.
      events_nullable_text(organizer, "email", "organizer", limits)
    }
  }
}

///|
fn events_attendees(
  row : @decode.ObjectView,
  limits : CalendarEventsLimits,
) -> Result[@admitted.Value, CalendarEventsIssue] {
  let mut incomplete = match events_default_boolean(row, "attendeesOmitted") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let list = match @decode.field(row, "attendees") {
    Missing | ExplicitNull => return Ok(@admitted.null_value())
    Present(value) => value
  }
  guard @decode.array_length(list) is Some(count) else {
    return Err(InvalidCell("attendees"))
  }
  if count > limits.max_attendees {
    return Err(BudgetExceeded)
  }
  let values = []
  for index in 0..<count {
    guard @decode.open_object(@decode.element_at(list, index).unwrap())
      is Ok(attendee) else {
      return Err(InvalidCell("attendees"))
    }
    let email = match @decode.field(attendee, "email") {
      Missing => {
        incomplete = true
        None
      }
      Present(value) =>
        match @decode.text(value) {
          Ok(text) => Some(text)
          Err(_) => return Err(InvalidCell("attendees.email"))
        }
      ExplicitNull => return Err(InvalidCell("attendees.email"))
    }
    let status = match @decode.field(attendee, "responseStatus") {
      Missing => {
        incomplete = true
        None
      }
      Present(value) =>
        match @decode.text(value) {
          Ok("needsAction" | "declined" | "tentative" | "accepted" as text) =>
            Some(text)
          _ => return Err(InvalidCell("attendees.response_status"))
        }
      ExplicitNull => return Err(InvalidCell("attendees.response_status"))
    }
    let optional = match events_default_boolean(attendee, "optional") {
      Ok(value) => value
      Err(_) => return Err(InvalidCell("attendees.optional"))
    }
    match @decode.field(attendee, "asyncOperation") {
      Missing => ()
      Present(value) if @decode.text(value) == Ok("inProgress") =>
        incomplete = true
      _ => return Err(InvalidCell("attendees.async_operation"))
    }
    match (email, status) {
      (Some(email), Some(status)) => {
        let email = match events_text_value(email, limits) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        let status = match events_text_value(status, limits) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        values.push(
          @admitted.object_value([
            ("email", email),
            ("response_status", status),
            ("optional", @admitted.boolean_value(optional)),
          ]).unwrap(),
        )
      }
      _ => ()
    }
  }
  // Do not short-circuit validation of present members on an omitted/pending
  // flag. NULL represents unavailable completeness, never malformed DATA.
  Ok(
    if incomplete {
      @admitted.null_value()
    } else {
      @admitted.array_value(values)
    },
  )
}

///|
/// Project every declared cell before any downstream selection. The original
/// query and selected profile remain with this same page; no Source, grant,
/// complete read or physical-retirement receipt is issued by the projection.
pub fn project_calendar_events(
  bytes : Bytes,
  query : CalendarEventsQuery,
  limits : CalendarEventsLimits,
) -> Result[CalendarEventsPage, CalendarEventsIssue] {
  let envelope = match project_calendar_events_envelope(bytes, query, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let columns = events_columns()
  let rows = []
  let mut remaining_nodes = limits.max_value_nodes
  let mut remaining_text = limits.max_value_text_bytes
  let mut remaining_work = limits.max_resolution_work
  for original in envelope.events {
    let row = @decode.open_object(original).unwrap()
    let (start, end, all_day, work) = match
      events_temporal_values(row, query, remaining_work) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    remaining_work -= work
    let values = []
    for (name, contract) in columns {
      let value = match name {
        "calendar_id" => events_text_value(query.calendar_id, limits)
        "ical_uid" => events_nullable_text(row, "iCalUID", name, limits)
        "recurring_event_id" =>
          events_nullable_text(row, "recurringEventId", name, limits)
        "created" | "updated" => events_nullable_timestamp(row, name)
        "start" => Ok(start)
        "end" => Ok(end)
        "all_day" => Ok(all_day)
        "organizer" => events_organizer(row, limits)
        "attendees" => events_attendees(row, limits)
        "status" =>
          match @decode.field(row, "status") {
            Missing | ExplicitNull => Ok(@admitted.null_value())
            Present(value) =>
              match @decode.text(value) {
                Ok("confirmed" | "tentative" | "cancelled" as text) =>
                  events_text_value(text, limits)
                _ => Err(InvalidCell("status"))
              }
          }
        _ => events_nullable_text(row, name, name, limits)
      }
      let value = match value {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      guard @admitted.recheck_runtime_value_usage(value, contract, {
          max_nodes: remaining_nodes,
          max_depth: limits.max_depth,
          max_text_bytes: remaining_text,
        })
        is Some((checked, nodes, text)) else {
        return Err(BudgetExceeded)
      }
      remaining_nodes -= nodes
      remaining_text -= text
      values.push(checked)
    }
    rows.push(values)
  }
  Ok({
    response_sha256: envelope.response_sha256,
    next_page_token: envelope.next_page_token,
    query,
    rows,
  })
}

///|
pub fn calendar_events_row_count(page : CalendarEventsPage) -> Int {
  page.rows.length()
}

///|
pub fn calendar_events_matches_query(
  page : CalendarEventsPage,
  query : CalendarEventsQuery,
) -> Bool {
  physical_equal(page.query, query)
}

///|
pub fn calendar_events_ids(page : CalendarEventsPage) -> Array[String] {
  page.rows.map(row => {
    match row[0].value {
      @admitted.Text(id) => id
      _ => abort("checked Event id invariant")
    }
  })
}

///|
pub fn calendar_events_rows_wire(
  page : CalendarEventsPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, CalendarEventsIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let columns = calendar_events_column_names()
  let selected : Array[(String, Int)] = []
  for name in names {
    if selected.any(item => item.0 == name) {
      return Err(InvalidSelection(name))
    }
    let mut found = None
    for index, column in columns {
      if column == name {
        found = Some(index)
      }
    }
    guard found is Some(index) else { return Err(InvalidSelection(name)) }
    selected.push((name, index))
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_array(writer)
    for row in page.rows {
      @encode.begin_object(writer)
      for (name, index) in selected {
        @encode.key(writer, name)
        @admitted.emit_checked_wire_value(row[index], writer)
      }
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}

///|
pub fn calendar_events_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, CalendarEventsIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let contract = @contract.object_contract(
    events_columns(),
    nullable=false,
    max_fields=16,
    max_name_bytes=256,
  ).unwrap()
  guard contract.shape is @contract.Object(fields) else {
    abort("static Event schema invariant")
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_ordered_object(writer)
    for index in 0..<@contract.field_count(fields) {
      let field = @contract.field_at(fields, index).unwrap()
      @encode.ordered_key(writer, field.name)
      @contract.emit_checked(field.contract, writer)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}

///|
pub fn calendar_events_facts_wire() -> String {
  // Recurring instances can share iCalUID. No extra KeySet is inferred.
  "{\"relation_keys\":{\"candidate_keys\":[[\"calendar_id\",\"id\"]]}}"
}

///|
pub fn calendar_events_metadata_wire(
  page : CalendarEventsPage,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, CalendarEventsIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "calendarId")
    @encode.string_value(writer, page.query.calendar_id)
    @encode.key(writer, "ids")
    @encode.begin_array(writer)
    for id in calendar_events_ids(page) {
      @encode.string_value(writer, id)
    }
    @encode.end_array(writer)
    @encode.key(writer, "nextPageToken")
    match page.next_page_token {
      Some(token) => @encode.string_value(writer, token)
      None => @encode.null_value(writer)
    }
    @encode.key(writer, "profileCid")
    @encode.string_value(writer, @calendar_profile.cid(page.query.profile))
    @encode.key(writer, "responseSha256")
    @encode.string_value(writer, page.response_sha256)
    @encode.key(writer, "rowCount")
    @encode.number_value(writer, page.rows.length().to_double())
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}
