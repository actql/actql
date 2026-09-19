///|
test "remote evidence JSON is independently re-admitted in MoonBit" {
  let request = coordinator_request("evidence-json", 31)
  let (evidence, subject, measurement) = managed_output_for_coordinator(request)
  let evidence_body = remote_execution_evidence_json(evidence).unwrap()
  let subject_body = remote_managed_output_subject_json(subject).unwrap()
  let measurement_body = remote_managed_output_measurement_json(measurement).unwrap()
  let restored_evidence = admit_remote_execution_evidence_json(
    evidence_body,
    remote_execution_evidence_cid(evidence),
    request,
  ).unwrap()
  let restored_subject = admit_remote_managed_output_subject_json(
    subject_body,
    remote_managed_output_subject_cid(subject),
    request,
  ).unwrap()
  let restored_measurement = admit_remote_managed_output_measurement_json(
    measurement_body,
    remote_managed_output_measurement_cid(measurement),
  ).unwrap()
  assert_true(
    remote_managed_output_subject_matches_evidence(
      restored_subject, restored_evidence, request,
    ),
  )
  assert_true(
    remote_managed_output_subject_matches_measurement(
      restored_subject, restored_measurement,
    ),
  )
  assert_true(
    admit_remote_execution_evidence_json(
      evidence_body + " ",
      remote_execution_evidence_cid(evidence),
      request,
    )
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_managed_output_subject_json(
      subject_body, "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      request,
    )
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_managed_output_measurement_json(
      measurement_body.replace(old="\"rows\":2", new="\"rows\":1"),
      remote_managed_output_measurement_cid(measurement),
    )
    is Err(InvalidDispatch),
  )
}
