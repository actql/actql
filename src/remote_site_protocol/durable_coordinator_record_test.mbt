///|
test "Coordinator durable record preserves typed evidence across restart" {
  let request = coordinator_request("durable-coordinator", 41)
  let journal = create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let admission = prepare_coordinator_dispatch_intent(journal, request).unwrap()
  let initial_body = coordinator_dispatch_admission_durable_json(admission).unwrap()
  let initial = admit_durable_coordinator_dispatch_record(
    @utf8.encode(initial_body),
  ).unwrap()
  let (_, record) = commit_coordinator_dispatch_intent(admission, true).unwrap()
  let (evidence, subject, measurement) = managed_output_for_coordinator(request)
  let transition = prepare_coordinator_managed_output_observation(
    record, 5, 3, 2, 0, true, false, evidence, subject, measurement,
  ).unwrap()
  let next_body = coordinator_dispatch_transition_durable_json(
    initial,
    transition,
    evidence=Some(evidence),
    subject=Some(subject),
    measurement=Some(measurement),
  ).unwrap()
  let durable = admit_durable_coordinator_dispatch_record(
    @utf8.encode(next_body),
  ).unwrap()
  let restored = restore_durable_coordinator_dispatch_record(
    create_coordinator_dispatch_journal("coordinator-a").unwrap(),
    durable,
  ).unwrap()
  assert_true(coordinator_completion_evidence_available(restored))
  assert_true(durable_coordinator_dispatch_record_evidence(durable) is Some(_))
  assert_true(durable_coordinator_dispatch_record_subject(durable) is Some(_))
  assert_true(
    durable_coordinator_dispatch_record_measurement(durable) is Some(_),
  )
  assert_true(
    admit_durable_coordinator_dispatch_record(@utf8.encode(next_body + " "))
    is Err(InvalidJournal),
  )
}

///|
test "Durable Coordinator history replays older admitted observations without a new body" {
  let request = coordinator_request("durable-replay", 42)
  let journal = create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let admission = prepare_coordinator_dispatch_intent(journal, request).unwrap()
  let mut durable = admit_durable_coordinator_dispatch_record(
    @utf8.encode(
      coordinator_dispatch_admission_durable_json(admission).unwrap(),
    ),
  ).unwrap()
  let (_, record) = commit_coordinator_dispatch_intent(admission, true).unwrap()
  for revision in [1, 3] {
    let transition = prepare_coordinator_site_observation(
      record,
      revision,
      2,
      0,
      0,
      false,
      false,
      None,
    ).unwrap()
    let next = coordinator_dispatch_transition_durable_json(durable, transition).unwrap()
    // Admission history and state are one durable body, before the portable
    // owner commits. A lost ACK cannot erase either part of that same body.
    durable = admit_durable_coordinator_dispatch_record(@utf8.encode(next)).unwrap()
    commit_coordinator_dispatch_transition(transition, true).unwrap()
  }
  let saved = durable_coordinator_dispatch_record_json(durable)
  let restored = restore_durable_coordinator_dispatch_record(
    create_coordinator_dispatch_journal("coordinator-a").unwrap(),
    durable,
  ).unwrap()
  for revision in [3, 1] {
    let transition = prepare_coordinator_site_observation(
      restored,
      revision,
      2,
      0,
      0,
      false,
      false,
      None,
    ).unwrap()
    assert_true(coordinator_dispatch_transition_is_replay(transition))
    assert_eq(
      coordinator_dispatch_transition_durable_json(durable, transition),
      Ok(saved),
    )
    commit_coordinator_dispatch_transition(transition, true).unwrap()
    assert_eq(coordinator_dispatch_record_revision(restored), 2)
  }
  assert_true(
    prepare_coordinator_site_observation(
      restored,
      2,
      2,
      0,
      0,
      false,
      false,
      None,
    )
    is Err(StateCollision),
  )
  assert_true(
    prepare_coordinator_site_observation(
      restored,
      1,
      4,
      0,
      0,
      false,
      false,
      None,
    )
    is Err(StateCollision),
  )
}

///|
test "Durable Coordinator refuses legacy and invented history rather than reconstructing it" {
  let request = coordinator_request("history-format", 43)
  let journal = create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let admission = prepare_coordinator_dispatch_intent(journal, request).unwrap()
  let body = coordinator_dispatch_admission_durable_json(admission).unwrap()
  let old = body
    .replace(
      old="actql-remote-coordinator-history-record/0.1",
      new="actql-remote-coordinator-record/0.1",
    )
    .replace(old="\"observation_history_json\":\"[]\",", new="")
  assert_true(
    admit_durable_coordinator_dispatch_record(@utf8.encode(old))
    is Err(ObservationHistoryRequired),
  )
  let durable = admit_durable_coordinator_dispatch_record(@utf8.encode(body)).unwrap()
  let (_, record) = commit_coordinator_dispatch_intent(admission, true).unwrap()
  let transition = prepare_coordinator_site_observation(
    record,
    3,
    2,
    0,
    0,
    false,
    false,
    None,
  ).unwrap()
  let next = coordinator_dispatch_transition_durable_json(durable, transition).unwrap()
  // Removing the actual accepted profile is not repaired from latest state.
  let without_history = next.replace(
    old="\"observation_history_json\":\"[[\\\"3\\\",\\\"2\\\",\\\"0\\\",\\\"0\\\",\\\"0\\\",\\\"0\\\",\\\"\\\",\\\"\\\",\\\"\\\"]]\"",
    new="\"observation_history_json\":\"[]\"",
  )
  assert_false(without_history == next)
  assert_true(
    admit_durable_coordinator_dispatch_record(@utf8.encode(without_history))
    is Err(InvalidJournal),
  )
}
