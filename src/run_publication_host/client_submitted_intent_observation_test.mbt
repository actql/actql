///|
test "submission observation shares retained original and invocation decisions" {
  let wire = "{\"kind\":\"program\",\"input\":{},\"parameters\":null}"
  let expected = prepare_client_submitted_intent(wire, 4096, 128, 16).unwrap()
  // A cold admission of the same original content is not object identity.
  let cold = prepare_client_submitted_intent(wire, 4096, 128, 16).unwrap()
  let foreign = prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":{},\"parameters\":{\"n\":1}}", 4096, 128, 16,
  ).unwrap()
  assert_eq(
    observe_client_submitted_intent(expected, None),
    Ok(SubmissionMissing),
  )
  assert_eq(
    client_submitted_intent_attempt_kind(SubmissionMissing, false),
    None,
  )
  for
    phase in [
      "preparing", "held", "ready", "not_accepted", "preparation_failed",
    ] {
    assert_eq(
      observe_client_submitted_intent(expected, Some((foreign, phase))),
      Ok(SubmissionConflict),
    )
  }
  assert_eq(
    observe_client_submitted_intent(expected, Some((cold, "preparing"))),
    Ok(SubmissionPending),
  )
  assert_eq(
    client_submitted_intent_attempt_kind(SubmissionPending, false),
    Some("recorded"),
  )
  for phase in ["held", "ready", "not_accepted", "preparation_failed"] {
    let observation = observe_client_submitted_intent(
      expected,
      Some((cold, phase)),
    ).unwrap()
    assert_eq(observation, SubmissionSatisfied)
    assert_eq(
      client_submitted_intent_attempt_kind(observation, false),
      Some("already_satisfied"),
    )
    assert_eq(
      client_submitted_intent_attempt_kind(observation, true),
      Some("recorded"),
    )
  }
  assert_eq(
    client_submitted_intent_attempt_kind(SubmissionConflict, false),
    None,
  )
  for phase in ["", "unknown", "completed", "cancelled"] {
    assert_eq(
      observe_client_submitted_intent(expected, Some((cold, phase))),
      Err(InvalidEnvelope),
    )
  }
}

///|
test "submission observation exposes one closed binding action vocabulary" {
  assert_eq(
    client_submitted_intent_observation_action(SubmissionMissing, false),
    "missing",
  )
  assert_eq(
    client_submitted_intent_observation_action(SubmissionConflict, false),
    "conflict",
  )
  assert_eq(
    client_submitted_intent_observation_action(SubmissionPending, false),
    "recorded",
  )
  assert_eq(
    client_submitted_intent_observation_action(SubmissionSatisfied, false),
    "already_satisfied",
  )
  assert_eq(
    client_submitted_intent_observation_action(SubmissionSatisfied, true),
    "recorded",
  )
}
