///|
test "saved Output intent binds both original attempt and dispatch" {
  let (_, _, request, _) = completed_envelope_fixture()
  let attempt = @remote.dispatch_request_attempt_identity(request).unwrap()
  let identity = @remote.dispatch_request_identity(request)
  assert_true(
    output_intent_matches_dispatch(
      output_intent_body(attempt, identity, "not-a-payload"),
      request,
    ),
  )
  assert_false(
    output_intent_matches_dispatch(
      output_intent_body("another-attempt", identity, "not-a-payload"),
      request,
    ),
  )
  assert_false(
    output_intent_matches_dispatch(
      output_intent_body(attempt, "sha256:" + "f".repeat(64), "not-a-payload"),
      request,
    ),
  )
  assert_false(output_intent_matches_dispatch("{}", request))
  assert_false(output_intent_matches_dispatch("invalid-json", request))
  // Metadata matching does not admit the payload or authorize recovery.
  assert_true(
    output_intent_request(
      identity,
      output_intent_body(attempt, identity, "not-a-payload"),
    )
    is None,
  )
}
