///|
test "managed observation binds transition and restored canonical bodies" {
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let request = request("managed-observation", 1, 1, bundle)
  let journal = journal()
  let (_, record) = commit_dispatch_acceptance(
    prepare_dispatch_acceptance(journal, request).unwrap(),
    true,
  ).unwrap()
  commit_dispatch_transition(
    prepare_begin_provisioning(record, execution_capability()).unwrap(),
    true,
  ).unwrap()
  commit_dispatch_transition(
    prepare_begin_remote_execution(record).unwrap(),
    true,
  ).unwrap()
  commit_dispatch_transition(
    prepare_confirm_native_settled(record).unwrap(),
    true,
  ).unwrap()
  let holding = cid(
    "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  )
  commit_dispatch_transition(
    prepare_retain_remote_output(record, "material-a", holding).unwrap(),
    true,
  ).unwrap()
  let measurement = prepare_remote_managed_output_measurement(
    1,
    1,
    1,
    1,
    [1],
    [1],
    [1],
    [1],
    [0],
    [1],
  ).unwrap()
  let subject = prepare_remote_managed_output_subject(
    dispatch_request_identity(request),
    "material-a",
    holding,
    cid("dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"),
    cid("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
    cid("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
    cid("1111111111111111111111111111111111111111111111111111111111111111"),
    cid("2222222222222222222222222222222222222222222222222222222222222222"),
    remote_managed_output_measurement_cid(measurement),
    1,
    1L,
  ).unwrap()
  let evidence = issue_remote_managed_output_evidence(
    managed_output_issuer(),
    record,
    subject,
  ).unwrap()
  let transition = prepare_durable_execution_evidence(record, evidence).unwrap()
  assert_true(
    remote_managed_output_observation_matches_transition(
      transition, evidence, subject, measurement,
    ),
  )
  let body = remote_managed_output_observation_json(
    transition, evidence, subject, measurement,
  ).unwrap()
  commit_dispatch_transition(transition, true).unwrap()
  let restored = admit_remote_managed_output_observation_json(record, body).unwrap()
  assert_eq(
    remote_execution_evidence_cid(restored.0),
    remote_execution_evidence_cid(evidence),
  )
  assert_eq(
    remote_managed_output_subject_cid(restored.1),
    remote_managed_output_subject_cid(subject),
  )
  assert_eq(
    remote_managed_output_measurement_cid(restored.2),
    remote_managed_output_measurement_cid(measurement),
  )
  assert_true(
    admit_remote_managed_output_observation_json(record, body + " ")
    is Err(InvalidJournal),
  )
}
