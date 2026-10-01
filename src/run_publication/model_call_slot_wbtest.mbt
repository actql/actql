///|
test "model call slot rejects response and runtime-position fields" {
  let body = "{\"version\":\"actql-model-call-slot/0.1\"," +
    "\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\"," +
    "\"unit_definition_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\"," +
    "\"source_ordinal\":2," +
    "\"effective_inputs_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\"," +
    "\"input_artifact_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\"," +
    "\"input_key_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\"," +
    "\"model_task_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"," +
    "\"fixed_request_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"}"
  let issued = seal_run_evidence_value("model_call_slot", body, 10000, 1000, 20).unwrap()
  for name in ["row_number", "worker", "response", "stage_invocation_cid"] {
    let changed = body.replace(
      old="\"source_ordinal\":2,",
      new="\"" + name + "\":2,",
    )
    assert_true(
      seal_run_evidence_value("model_call_slot", changed, 10000, 1000, 20)
      is Err(RunEvidenceInvalidShape),
    )
  }
  // A parsed identity is neither a model invocation record nor capture proof.
  assert_eq(run_evidence_value_name(issued), "model_call_slot")
  assert_true(
    admit_run_evidence_value(
      "model_invocation_evidence",
      run_evidence_value_json(issued),
      10000,
      1000,
      20,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "effective model inputs require an explicit non-null artifact map" {
  let prefix = "{\"version\":\"actql-model-effective-inputs/0.1\"," +
    "\"parameter_values_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"," +
    "\"invocation_bindings_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\""
  assert_true(
    seal_run_evidence_value(
      "model_effective_inputs",
      prefix + "}",
      10000,
      1000,
      20,
    )
    is Err(RunEvidenceInvalidShape),
  )
  assert_true(
    seal_run_evidence_value(
      "model_effective_inputs",
      prefix + ",\"input_artifacts\":null}",
      10000,
      1000,
      20,
    )
    is Err(RunEvidenceInvalidShape),
  )
  assert_true(
    seal_run_evidence_value(
      "model_effective_inputs",
      prefix + ",\"input_artifacts\":{}}",
      10000,
      1000,
      20,
    )
    is Ok(_),
  )
}
