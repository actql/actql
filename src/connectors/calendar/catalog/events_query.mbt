///|
pub(all) struct CalendarEventsLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
  max_identity_bytes : Int
  max_cursor_bytes : Int
  max_attendees : Int
  max_value_nodes : Int
  max_value_text_bytes : Int
  max_resolution_work : Int
}

///|
pub(all) enum CalendarEventsIssue {
  InvalidLimits
  BudgetExceeded
  InvalidQuery
  TimeZoneUnavailable
  InvalidResponse
  ForeignTimeZone
  InvalidCursor
  DuplicateEvent(String)
  InvalidCell(String)
  IncompleteAttendees
  InvalidSelection(String)
  EventTime(CalendarEventTimeIssue)
} derive(Eq, Debug)

///|
/// Original provider query DATA. The same caller still owns the selected
/// calendar, checked Source Request, Account/Site and whole read reservation.
pub struct CalendarEventsQuery {
  priv calendar_id : String
  priv time_min : String
  priv time_max : String
  priv time_zone : String
  priv profile : @calendar_profile.Profile
}

///|
fn events_limits_valid(limits : CalendarEventsLimits) -> Bool {
  limits.max_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_rows > 0 &&
  limits.max_identity_bytes > 0 &&
  limits.max_cursor_bytes > 0 &&
  limits.max_attendees >= 0 &&
  limits.max_value_nodes > 0 &&
  limits.max_value_text_bytes > 0 &&
  limits.max_resolution_work >= 0
}

///|
pub fn prepare_calendar_events_query(
  calendar_id : String,
  time_min : String,
  time_max : String,
  time_zone : String,
  profile : @calendar_profile.Profile,
  limits : CalendarEventsLimits,
) -> Result[CalendarEventsQuery, CalendarEventsIssue] {
  if !events_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  for text in [calendar_id, time_zone] {
    if text.is_empty() {
      return Err(InvalidQuery)
    }
    if text.length() > limits.max_identity_bytes ||
      @utf8.encode(text).length() > limits.max_identity_bytes {
      return Err(BudgetExceeded)
    }
  }
  guard @calendar_profile.zone(profile, time_zone) is Some(_) else {
    return Err(TimeZoneUnavailable)
  }
  guard @admitted.normalize_timestamp_text(time_min, 40) is Some(minimum) &&
    @admitted.normalize_timestamp_text(time_max, 40) is Some(maximum) &&
    @admitted.compare_timestamp_text(minimum, maximum) is Some(order) &&
    order < 0 else {
    return Err(InvalidQuery)
  }
  Ok({ calendar_id, time_min, time_max, time_zone, profile, })
}

///|
/// This preserves the original API-bound values. It does not claim an exact
/// SQL predicate pushdown: Google timeMin filters end, timeMax filters start,
/// and the API ignores fractional seconds in those request bounds.
pub fn calendar_events_query_wire(
  query : CalendarEventsQuery,
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
    for
      (name, value) in [
        ("calendar_id", query.calendar_id),
        ("time_min", query.time_min),
        ("time_max", query.time_max),
        ("time_zone", query.time_zone),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
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
/// The bounded original page envelope. Its private events are interpreted by
/// the same provider's complete row projection; the envelope alone is neither
/// a typed Source page nor authority to issue another request.
pub struct CalendarEventsEnvelope {
  response_sha256 : String
  next_page_token : String?
  priv query : CalendarEventsQuery
  priv events : Array[@decode.Cursor]
  priv ids : Array[String]
}

///|
pub fn project_calendar_events_envelope(
  bytes : Bytes,
  query : CalendarEventsQuery,
  limits : CalendarEventsLimits,
) -> Result[CalendarEventsEnvelope, CalendarEventsIssue] {
  if !events_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  let cursor = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  guard @decode.open_object(cursor) is Ok(root) &&
    event_time_text(root, "kind") == Some("calendar#events") else {
    return Err(InvalidResponse)
  }
  guard event_time_text(root, "timeZone") is Some(zone) else {
    return Err(InvalidResponse)
  }
  if zone != query.time_zone {
    return Err(ForeignTimeZone)
  }
  let next_page_token = match @decode.field(root, "nextPageToken") {
    Missing => None
    Present(value) => {
      guard @decode.text(value) is Ok(text) && !text.is_empty() else {
        return Err(InvalidCursor)
      }
      if text.length() > limits.max_cursor_bytes ||
        @utf8.encode(text).length() > limits.max_cursor_bytes {
        return Err(BudgetExceeded)
      }
      Some(text)
    }
    _ => return Err(InvalidCursor)
  }
  let items = match @decode.field(root, "items") {
    Missing => None
    Present(value) => Some(value)
    _ => return Err(InvalidResponse)
  }
  let count = match items {
    None => 0
    Some(value) =>
      match @decode.array_length(value) {
        Some(count) => count
        None => return Err(InvalidResponse)
      }
  }
  if count > limits.max_rows {
    return Err(BudgetExceeded)
  }
  let events : Array[@decode.Cursor] = []
  let ids : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  for index in 0..<count {
    let original = @decode.element_at(items.unwrap(), index).unwrap()
    guard @decode.open_object(original) is Ok(event) &&
      event_time_text(event, "id") is Some(id) else {
      return Err(InvalidResponse)
    }
    // A deleted tombstone only guarantees its id. A supplied kind must still
    // be the actual Event kind; absence is not an inferred cancellation.
    match @decode.field(event, "kind") {
      Missing => ()
      Present(value) if @decode.text(value) == Ok("calendar#event") => ()
      _ => return Err(InvalidResponse)
    }
    if id.length() > limits.max_identity_bytes ||
      @utf8.encode(id).length() > limits.max_identity_bytes {
      return Err(BudgetExceeded)
    }
    if seen.contains(id) {
      return Err(DuplicateEvent(id))
    }
    seen[id] = true
    ids.push(id)
    events.push(original)
  }
  Ok({ response_sha256: @sha.hex(bytes), next_page_token, query, events, ids, })
}

///|
pub fn calendar_events_envelope_count(page : CalendarEventsEnvelope) -> Int {
  page.events.length()
}

///|
pub fn calendar_events_envelope_ids(
  page : CalendarEventsEnvelope,
) -> Array[String] {
  page.ids.copy()
}

///|
pub fn calendar_events_envelope_calendar_id(
  page : CalendarEventsEnvelope,
) -> String {
  page.query.calendar_id
}

///|
/// Diagnostic DATA, not proof that this profile belongs to another Run.
pub fn calendar_events_envelope_profile_cid(
  page : CalendarEventsEnvelope,
) -> String {
  @calendar_profile.cid(page.query.profile)
}
