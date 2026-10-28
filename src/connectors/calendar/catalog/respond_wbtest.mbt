///|
fn respond_limits() -> CalendarRespondLimits {
  {
    max_target_bytes: 8192,
    max_nodes: 1000,
    max_depth: 20,
    max_attendees: 10,
    max_body_bytes: 4096,
  }
}

///|
fn respond_target() -> String {
  (
    #|{"kind":"calendar#event","id":"event/1","etag":"\"original-etag\"","status":"confirmed","summary":"Do not rewrite","attendees":[{"email":"other@example.test","responseStatus":"accepted","optional":true,"comment":"original"},{"email":"opérator@example.test","responseStatus":"needsAction","self":true}],"extendedProperties":{"private":{"other":"keep"},"shared":{"team":"same"}}}
  )
}

///|
fn respond_request(
  wire : String,
  response? : String = "declined",
  participant? : String = "opérator@example.test",
  marker? : String = "same-original-request",
  limits? : CalendarRespondLimits = respond_limits(),
) -> Result[CalendarRespondRequest, CalendarRespondIssue] {
  prepare_calendar_respond(
    @utf8.encode(wire),
    "calendar/+original@example.test",
    "event/1",
    participant,
    response,
    marker,
    limits,
  )
}

///|
test "respond request emits only original participant response and same original marker with exact preimage" {
  let before = respond_target()
  let request = respond_request(before).unwrap()
  assert_eq(
    calendar_respond_body(request),
    (
      #|{"attendees":[{"email":"opérator@example.test","responseStatus":"declined"}],"attendeesOmitted":true,"extendedProperties":{"private":{"actql_request":"same-original-request"}}}
    ),
  )
  let info = calendar_respond_info(request)
  assert_eq(info.calendar_id, "calendar/+original@example.test")
  assert_eq(info.event_id, "event/1")
  assert_eq(info.etag, "\"original-etag\"")
  assert_eq(info.participant, "opérator@example.test")
  assert_eq(info.response, "declined")
  assert_eq(info.marker, "same-original-request")
  assert_true(calendar_respond_matches_target(request, @utf8.encode(before)))
  assert_false(
    calendar_respond_matches_target(
      request,
      @utf8.encode(before.replace(old="original-etag", new="changed-etag")),
    ),
  )
  assert_false(
    calendar_respond_matches_target(request, @utf8.encode(before + " ")),
  )
  // A canonically equivalent spelling is not the original attendee identity.
  assert_true(
    respond_request(before, participant="opérator@example.test")
    is Err(MissingParticipant),
  )
}

///|
test "respond request preserves all three documented replies and refuses new action or foreign event" {
  for response in ["accepted", "declined", "tentative"] {
    let request = respond_request(respond_target(), response~).unwrap()
    assert_eq(calendar_respond_info(request).response, response)
    assert_true(calendar_respond_body(request).contains(response))
  }
  for response in ["needsAction", "", "Accepted", "unknown"] {
    assert_true(
      respond_request(respond_target(), response~) is Err(InvalidResponse),
    )
  }
  assert_true(
    respond_request(respond_target().replace(old="event/1", new="event/2"))
    is Err(ForeignEvent),
  )
  for
    pair in [
      ("calendar#event", "calendar#events"),
      ("confirmed", "cancelled"),
      ("needsAction", "unknown"),
      ("original-etag", "line\\r\\nbreak"),
    ] {
    assert_true(
      respond_request(respond_target().replace(old=pair.0, new=pair.1))
      is Err(InvalidTarget),
    )
  }
}

///|
test "respond request requires one exact participant and complete original attendee observation" {
  assert_true(
    respond_request(respond_target(), participant="foreign@example.test")
    is Err(MissingParticipant),
  )
  let duplicate = respond_target().replace(
    old="other@example.test",
    new="opérator@example.test",
  )
  assert_true(respond_request(duplicate) is Err(AmbiguousParticipant))
  for
    wire in [
      respond_target().replace(
        old="\"attendees\":[",
        new="\"attendeesOmitted\":true,\"attendees\":[",
      ),
      respond_target().replace(
        old="\"attendees\":[",
        new="\"attendeesOmitted\":null,\"attendees\":[",
      ),
      respond_target().replace(
        old="\"attendees\":[",
        new="\"attendeesOmitted\":\"false\",\"attendees\":[",
      ),
    ] {
    assert_true(respond_request(wire) is Err(IncompleteAttendees))
  }
  assert_true(
    respond_request(
      respond_target().replace(
        old="\"attendees\":[",
        new="\"attendeesOmitted\":false,\"attendees\":[",
      ),
    )
    is Ok(_),
  )
  assert_true(
    respond_request(respond_target(), limits={
      ..respond_limits(),
      max_attendees: 1,
    })
    is Err(CapacityExceeded),
  )
}

///|
test "respond request rejects malformed duplicate missing and null target fields" {
  for
    wire in [
      "not-json",
      "[]",
      respond_target().replace(old="\"id\":", new="\"id\":\"event/1\",\"id\":"),
      respond_target().replace(
        old="\"etag\":\"\\\"original-etag\\\"\"",
        new="\"etag\":null",
      ),
      respond_target().replace(
        old="\"etag\":\"\\\"original-etag\\\"\",",
        new="",
      ),
    ] {
    assert_false(respond_request(wire) is Ok(_))
  }
}

///|
test "respond request keeps marker and target body bounds exact with no truncation" {
  assert_true(
    respond_request(respond_target(), marker="") is Err(InvalidMarker),
  )
  assert_true(
    respond_request(respond_target(), marker="x".repeat(1024)) is Ok(_),
  )
  assert_true(
    respond_request(respond_target(), marker="x".repeat(1025))
    is Err(InvalidMarker),
  )
  let request = respond_request(respond_target()).unwrap()
  let bytes = @utf8.encode(calendar_respond_body(request)).length()
  assert_true(
    respond_request(respond_target(), limits={
      ..respond_limits(),
      max_body_bytes: bytes,
    })
    is Ok(_),
  )
  assert_true(
    respond_request(respond_target(), limits={
      ..respond_limits(),
      max_body_bytes: bytes - 1,
    })
    is Err(CapacityExceeded),
  )
  assert_true(
    respond_request(respond_target(), limits={
      ..respond_limits(),
      max_target_bytes: @utf8.encode(respond_target()).length() - 1,
    })
    is Err(CapacityExceeded),
  )
  assert_true(
    respond_request(respond_target(), limits={
      ..respond_limits(),
      max_depth: 0,
    })
    is Err(InvalidLimits),
  )
}

///|
test "respond request preserves nullable prior response observations without inferring a new prior value" {
  // The existing event Source keeps an absent/null prior response as unknown.
  // Setting a new explicit response does not need a fabricated old response.
  for
    wire in [
      respond_target().replace(
        old="\"responseStatus\":\"accepted\"",
        new="\"responseStatus\":null",
      ),
      respond_target().replace(
        old="\"responseStatus\":\"needsAction\"",
        new="\"responseStatus\":null",
      ),
    ] {
    let prepared = respond_request(wire)
    assert_true(prepared is Ok(_))
    let request = prepared.unwrap()
    assert_true(calendar_respond_matches_target(request, @utf8.encode(wire)))
    assert_eq(calendar_respond_info(request).response, "declined")
  }
}
