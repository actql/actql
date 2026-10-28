// Provider DATA only. The caller must supply the connected account's original
// participant and current target; this codec issues no send/approval authority.

///|
pub(all) struct CalendarRespondLimits {
  max_target_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_attendees : Int
  max_body_bytes : Int
}

///|
pub(all) enum CalendarRespondIssue {
  InvalidLimits
  CapacityExceeded
  InvalidTarget
  ForeignEvent
  IncompleteAttendees
  MissingParticipant
  AmbiguousParticipant
  InvalidResponse
  InvalidMarker
} derive(Eq, Debug)

///|
pub struct CalendarRespondRequest {
  priv target_wire : String
  priv body : String
  priv info : CalendarRespondInfo
}

///|
pub(all) struct CalendarRespondInfo {
  calendar_id : String
  event_id : String
  etag : String
  participant : String
  response : String
  marker : String
  target_sha256 : String
} derive(Eq, Debug)

///|
fn respond_required_text(value : @decode.ObjectView, name : String) -> String? {
  match @decode.lookup(value, name) {
    Some(value) =>
      match @decode.text(value) {
        Ok(text) if !text.is_empty() => Some(text)
        _ => None
      }
    None => None
  }
}

///|
/// Prepare the documented participant-only PATCH, preserving all other
/// attendees and properties through the API's attendeesOmitted/patch semantics.
/// The private marker is the caller's existing original, never a fresh tag.
pub fn prepare_calendar_respond(
  target : Bytes,
  calendar_id : String,
  event_id : String,
  participant : String,
  response : String,
  marker : String,
  limits : CalendarRespondLimits,
) -> Result[CalendarRespondRequest, CalendarRespondIssue] {
  if limits.max_target_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_attendees < 0 ||
    limits.max_body_bytes <= 0 {
    return Err(InvalidLimits)
  }
  if target.length() > limits.max_target_bytes {
    return Err(CapacityExceeded)
  }
  for text in [calendar_id, event_id, participant] {
    if text.is_empty() {
      return Err(InvalidTarget)
    }
    if text.length() > limits.max_target_bytes ||
      @utf8.encode(text).length() > limits.max_target_bytes {
      return Err(CapacityExceeded)
    }
  }
  if !(response == "accepted" ||
    response == "declined" ||
    response == "tentative") {
    return Err(InvalidResponse)
  }
  // Google silently truncates longer extended-property values. An original
  // marker must fit unchanged; the existing request markers are ASCII DATA.
  if marker.is_empty() || marker.length() > 1024 {
    return Err(InvalidMarker)
  }
  let parsed = match
    @source.parse_json_bytes(target, {
      max_input_bytes: limits.max_target_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => CapacityExceeded
          _ => InvalidTarget
        },
      )
  }
  let cursor = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_target_bytes,
      max_total_string_bytes: limits.max_target_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidTarget)
  }
  guard @decode.open_object(cursor) is Ok(original) &&
    respond_required_text(original, "kind") == Some("calendar#event") else {
    return Err(InvalidTarget)
  }
  if respond_required_text(original, "id") != Some(event_id) {
    return Err(ForeignEvent)
  }
  guard respond_required_text(original, "etag") is Some(etag) else {
    return Err(InvalidTarget)
  }
  if etag.contains("\r") || etag.contains("\n") {
    return Err(InvalidTarget)
  }
  match @decode.field(original, "status") {
    Missing => ()
    Present(value) if @decode.text(value) is Ok("confirmed" | "tentative") => ()
    _ => return Err(InvalidTarget)
  }
  match @decode.field(original, "attendeesOmitted") {
    Missing => ()
    Present(value) if @decode.boolean(value) is Ok(false) => ()
    _ => return Err(IncompleteAttendees)
  }
  guard @decode.lookup(original, "attendees") is Some(attendees) &&
    @decode.array_length(attendees) is Some(count) else {
    return Err(IncompleteAttendees)
  }
  if count > limits.max_attendees {
    return Err(CapacityExceeded)
  }
  let mut selected = 0
  for index in 0..<count {
    guard @decode.open_object(@decode.element_at(attendees, index).unwrap())
      is Ok(attendee) else {
      return Err(InvalidTarget)
    }
    if respond_required_text(attendee, "email") == Some(participant) {
      selected += 1
    }
    match @decode.field(attendee, "responseStatus") {
      Missing | ExplicitNull => ()
      Present(value) =>
        match @decode.text(value) {
          Ok("needsAction" | "accepted" | "declined" | "tentative") => ()
          _ => return Err(InvalidTarget)
        }
    }
  }
  if selected == 0 {
    return Err(MissingParticipant)
  }
  if selected != 1 {
    return Err(AmbiguousParticipant)
  }
  let target_wire = @utf8.decode(target, ignore_bom=false) catch {
    _ => return Err(InvalidTarget)
  }
  let writer = @encode.writer(
    limits.max_body_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(CapacityExceeded)
  }
  let body = try {
    @encode.begin_object(writer)
    @encode.key(writer, "attendees")
    @encode.begin_array(writer)
    @encode.begin_object(writer)
    @encode.key(writer, "email")
    @encode.string_value(writer, participant)
    @encode.key(writer, "responseStatus")
    @encode.string_value(writer, response)
    @encode.end_object(writer)
    @encode.end_array(writer)
    @encode.key(writer, "attendeesOmitted")
    @encode.bool_value(writer, true)
    @encode.key(writer, "extendedProperties")
    @encode.begin_object(writer)
    @encode.key(writer, "private")
    @encode.begin_object(writer)
    @encode.key(writer, "actql_request")
    @encode.string_value(writer, marker)
    @encode.end_object(writer)
    @encode.end_object(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return Err(CapacityExceeded)
    }
  }
  Ok({
    target_wire,
    body,
    info: {
      calendar_id,
      event_id,
      etag,
      participant,
      response,
      marker,
      target_sha256: @sha.hex(target),
    },
  })
}

///|
pub fn calendar_respond_body(request : CalendarRespondRequest) -> String {
  request.body
}

///|
pub fn calendar_respond_info(
  request : CalendarRespondRequest,
) -> CalendarRespondInfo {
  request.info
}

///|
pub fn calendar_respond_matches_target(
  request : CalendarRespondRequest,
  target : Bytes,
) -> Bool {
  @utf8.encode(request.target_wire) == target
}
