///|
fn evidence_test_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn evidence_test_template(program : String) -> RunEvidenceValue {
  seal_run_evidence_value(
    "bound_invocation_template",
    "{\"version\":\"actql-bound-invocation-template/0.1\"," +
    "\"program_definition_cid\":\"" +
    program +
    "\",\"parameter_values_cid\":\"" +
    evidence_test_cid("2") +
    "\",\"invocation_bindings_cid\":\"" +
    evidence_test_cid("3") +
    "\",\"check_environment_cid\":\"" +
    evidence_test_cid("4") +
    "\",\"grammar_manifest_cid\":\"" +
    evidence_test_cid("5") +
    "\",\"required_profile_contracts\":[]," +
    "\"barrier_contract_manifest_cid\":\"" +
    evidence_test_cid("6") +
    "\",\"source_evidence\":\"unbound\"}",
    16384,
    128,
    8,
  ).unwrap()
}

///|
fn evidence_test_observation(template : RunEvidenceValue) -> RunEvidenceValue {
  seal_run_evidence_value(
    "observation_set",
    "{\"version\":\"actql-observation-set/0.1\"," +
    "\"invocation_template_cid\":\"" +
    run_evidence_value_identity(template) +
    "\",\"source_evidence_cids\":[]," +
    "\"captured_input_artifact_cids\":[]," +
    "\"consistency\":\"no_external_sources\"," +
    "\"capture_started_at\":null,\"capture_completed_at\":null," +
    "\"replayability\":{\"materialized\":false," +
    "\"availability_evidence_cids\":[]}," +
    "\"data_policy_cid\":\"" +
    evidence_test_cid("7") +
    "\"}",
    16384,
    128,
    8,
  ).unwrap()
}

///|
test "embedded Run evidence has one closed identity owner" {
  let template = evidence_test_template(evidence_test_cid("1"))
  assert_eq(run_evidence_value_name(template), "bound_invocation_template")
  let admitted = admit_run_evidence_value(
    "bound_invocation_template",
    run_evidence_value_json(template),
    16384,
    128,
    8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(admitted),
    run_evidence_value_identity(template),
  )
  assert_true(
    seal_run_evidence_value(
      "bound_invocation_template",
      run_evidence_value_json(template),
      16384,
      128,
      8,
    )
    is Err(RunEvidenceIdentityAlreadyPresent),
  )
  let changed = run_evidence_value_json(template).replace(
    old=run_evidence_value_identity(template),
    new=evidence_test_cid("0"),
  )
  assert_true(
    admit_run_evidence_value(
      "bound_invocation_template", changed, 16384, 128, 8,
    )
    is Err(RunEvidenceIdentityMismatch),
  )
}

///|
test "Run Invocation binds the exact admitted ObservationSet" {
  let template = evidence_test_template(evidence_test_cid("1"))
  let observation = evidence_test_observation(template)
  let invocation = issue_run_invocation(template, observation, 16384, 128, 8).unwrap()
  let wire = publication_contract_json(invocation)
  assert_true(
    wire.contains(
      "\"invocation_template_cid\":\"" +
      run_evidence_value_identity(template) +
      "\"",
    ),
  )
  assert_true(
    wire.contains(
      "\"observation_set_cid\":\"" +
      run_evidence_value_identity(observation) +
      "\"",
    ),
  )
  let foreign = evidence_test_template(evidence_test_cid("8"))
  assert_true(
    issue_run_invocation(foreign, observation, 16384, 128, 8)
    is Err(RunEvidenceReferenceMismatch("observation.invocation_template_cid")),
  )
}
