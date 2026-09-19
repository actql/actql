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
