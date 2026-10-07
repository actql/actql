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

///|
test "recorded Output continuation binds original Run attempt and authority" {
  let (admission, _, request, envelope) = completed_envelope_fixture()
  let dispatch = @remote.admit_remote_poll_dispatch_json(envelope).unwrap()
  let body = @remote.remote_poll_dispatch_run_materials(dispatch).unwrap()
  let materials = rebuild_materials(admission, request, body).unwrap()
  let definition = @publication.prepare_result_definition(
    @host.prepared_client_identity(materials.prepared).program_definition_cid,
    "answer",
  ).unwrap()
  let recorded = @publication.prepare_recorded_run_publication(
    materials.admission,
    materials.run_definition,
    definition,
  ).unwrap()
  let attempt = @remote.dispatch_request_attempt_identity(request).unwrap()
  let restored = admit_resident_recorded_output_envelope(
    recorded, attempt, envelope,
  ).unwrap()
  assert_eq(
    @remote.dispatch_request_identity(restored),
    @remote.dispatch_request_identity(request),
  )
  assert_true(
    admit_resident_recorded_output_envelope(
      recorded, "another-attempt", envelope,
    )
    is Err(Protocol(@remote.DispatchIdentityMismatch)),
  )
  let other_run = @publication.issue_run_definition(
    materials.admission,
    "another-scope",
    "another-run",
    @publication.empty_initial_input_artifact_set_cid(),
    "2026-10-06T00:00:00.000Z",
    "2026-10-07T00:00:00.000Z",
    100000,
    10000,
    100,
  ).unwrap()
  let foreign = @publication.prepare_recorded_run_publication(
    materials.admission,
    other_run,
    definition,
  ).unwrap()
  assert_true(
    admit_resident_recorded_output_envelope(foreign, attempt, envelope)
    is Err(Protocol(@remote.DispatchIdentityMismatch)),
  )
  // A report continuation cannot substitute renewed authority for the exact
  // evidence accepted in the saved dispatch, even within the same context.
  let replaced = envelope.replace(
    old="prepared_invocation",
    new="missing_original_invocation",
  )
  assert_true(
    admit_resident_recorded_output_envelope(recorded, attempt, replaced)
    is Err(_),
  )
}
