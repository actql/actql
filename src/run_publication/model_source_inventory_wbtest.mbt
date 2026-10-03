///|
// Independent reference inventory after admission. These private test values
// isolate binding checks; they do not claim source admission or execution.
fn model_inventory_value(
  name : String,
  cid : String,
  body : String,
) -> RunEvidenceValue {
  {
    name,
    identity: cid,
    wire: body,
    value: parse_contract_wire(body, 16384, 1024, 20).unwrap(),
  }
}

///|
test "Model observation binds both sources even with no call slots" {
  let program = "sha256:" + "a".repeat(64)
  let policy = "sha256:" + "b".repeat(64)
  let template_cid = "sha256:" + "c".repeat(64)
  let artifact_cid = "sha256:" + "d".repeat(64)
  let first_cid = "sha256:" + "1".repeat(64)
  let second_cid = "sha256:" + "2".repeat(64)
  let template = model_inventory_value(
    "bound_invocation_template",
    template_cid,
    "{\"program_definition_cid\":\"" +
    program +
    "\",\"required_profile_contracts\":[{\"profile_id\":\"actql-infer/0.1\"}]}",
  )
  let artifact = model_inventory_value(
    "model_input_artifact",
    artifact_cid,
    "{\"program_definition_cid\":\"" + program + "\"}",
  )
  let first : ModelSourceObservation = {
    source: model_inventory_value("source_evidence", first_cid, "{}"),
    input: artifact,
    started_at: "2026-10-03T00:00:00.000Z",
    completed_at: "2026-10-03T00:00:01.000Z",
  }
  let second : ModelSourceObservation = {
    source: model_inventory_value("source_evidence", second_cid, "{}"),
    input: artifact,
    started_at: "2026-10-03T00:00:02.000Z",
    completed_at: "2026-10-03T00:00:03.000Z",
  }
  let body = "{\"invocation_template_cid\":\"" +
    template_cid +
    "\",\"data_policy_cid\":\"" +
    policy +
    "\",\"captured_input_artifact_cids\":[\"" +
    artifact_cid +
    "\"],\"model_slot_capture_cids\":[],\"source_evidence_cids\":[\"" +
    first_cid +
    "\",\"" +
    second_cid +
    "\"],\"consistency\":\"independent_snapshots\",\"capture_started_at\":\"2026-10-03T00:00:00.000Z\",\"capture_completed_at\":\"2026-10-03T00:00:03.000Z\"}"
  let observation = model_inventory_value(
    "observation_set",
    "sha256:" + "e".repeat(64),
    body,
  )
  assert_true(
    check_model_observation_binding(template, observation, artifact, policy, sources=[
      first, second,
    ])
    is Ok(_),
  )
  for expected in [[], [first], [second, first]] {
    assert_true(
      check_model_observation_binding(
        template,
        observation,
        artifact,
        policy,
        sources=expected,
      )
      is Err(RunEvidenceReferenceMismatch("observation.source_evidence_cids")),
    )
  }
  assert_true(
    check_model_observation_binding(
      template,
      observation,
      artifact,
      policy,
      source=Some(first),
      sources=[second],
    )
    is Err(_),
  )
  let short = model_inventory_value(
    "observation_set",
    observation.identity,
    body.replace(old="2026-10-03T00:00:03.000Z", new="2026-10-03T00:00:01.000Z"),
  )
  assert_true(
    check_model_observation_binding(template, short, artifact, policy, sources=[
      first, second,
    ])
    is Err(RunEvidenceReferenceMismatch("observation.capture_completed_at")),
  )
}
