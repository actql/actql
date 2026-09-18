///|
fn receipt_test_template(program : String) -> RunEvidenceValue {
  seal_run_evidence_value(
    "bound_invocation_template",
    "{\"version\":\"actql-bound-invocation-template/0.1\"," +
    "\"program_definition_cid\":\"" +
    program +
    "\",\"parameter_values_cid\":\"" +
    ordering_test_cid("2") +
    "\",\"invocation_bindings_cid\":\"" +
    ordering_test_cid("3") +
    "\",\"check_environment_cid\":\"" +
    ordering_test_cid("4") +
    "\",\"grammar_manifest_cid\":\"" +
    ordering_test_cid("5") +
    "\",\"required_profile_contracts\":[]," +
    "\"barrier_contract_manifest_cid\":\"" +
    ordering_test_cid("6") +
    "\",\"source_evidence\":\"unbound\"}",
    65536,
    1024,
    12,
  ).unwrap()
}

///|
fn receipt_test_admission(
  template : RunEvidenceValue,
) -> RunPublicationAdmission {
  let prepared = seal_run_evidence_value(
    "prepared_invocation",
    "{\"version\":\"actql-prepared-invocation/0.1\"," +
    "\"invocation_template_cid\":\"" +
    run_evidence_value_identity(template) +
    "\",\"compiled_plan_cid\":\"" +
    ordering_test_cid("1") +
    "\",\"execution_context_cid\":\"" +
    ordering_test_cid("2") +
    "\",\"host_policy_cid\":\"" +
    ordering_test_cid("3") +
    "\",\"policy_decision\":\"allow\"," +
    "\"expires_at\":\"2026-09-18T05:00:00.000Z\"}",
    65536,
    1024,
    12,
  ).unwrap()
  let authorization = seal_run_evidence_value(
    "run_authorization",
    "{\"version\":\"actql-run-authorization/0.1\"," +
    "\"prepared_invocation_cid\":\"" +
    run_evidence_value_identity(prepared) +
    "\",\"execution_context_cid\":\"" +
    ordering_test_cid("2") +
    "\",\"host_policy_cid\":\"" +
    ordering_test_cid("3") +
    "\",\"decision\":\"allowed\"}",
    65536,
    1024,
    12,
  ).unwrap()
  admit_run_publication(template, prepared, authorization).unwrap()
}

///|
fn receipt_test_observation(template : RunEvidenceValue) -> RunEvidenceValue {
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
    ordering_test_cid("e") +
    "\"}",
    65536,
    1024,
    12,
  ).unwrap()
}

///|
fn receipt_test_journal() -> RunEvidenceValue {
  seal_run_evidence_value(
    "normalization_journal",
    "{\"version\":\"actql-normalization-journal/0.1\"," +
    "\"rule_catalog_cid\":\"" +
    ordering_test_cid("d") +
    "\",\"entries\":[]}",
    65536,
    1024,
    12,
  ).unwrap()
}

///|
fn receipt_test_model_evidence(
  artifact : PublicationContract,
) -> RunEvidenceValue {
  seal_run_evidence_value(
    "model_invocation_evidence",
    "{\"version\":\"actql-model-invocation-evidence/0.1\"," +
    "\"model_task_contract_cid\":\"" +
    ordering_test_cid("0") +
    "\",\"semantic_request_cid\":\"" +
    ordering_test_cid("1") +
    "\",\"model_call_slot_cid\":\"" +
    ordering_test_cid("2") +
    "\",\"input_result_artifact_cid\":\"" +
    publication_contract_identity(artifact) +
    "\",\"input_row_identity_cid\":\"" +
    ordering_test_cid("3") +
    "\",\"input_row_identity\":\"row-1\"," +
    "\"authored_model_selector\":\"primary\"," +
    "\"provider_reported_model_id\":\"model-1\"," +
    "\"provider_request_id\":\"request-1\",\"attempt\":1," +
    "\"structured_response_artifact_cid\":\"" +
    ordering_test_cid("4") +
    "\",\"validated_structured_output_cid\":\"" +
    ordering_test_cid("5") +
    "\",\"input_tokens\":1,\"output_tokens\":1," +
    "\"finish_reason\":\"stop\"," +
    "\"observed_at\":\"2026-09-18T00:00:00.000Z\"}",
    65536,
    1024,
    12,
  ).unwrap()
}

///|
test "Run Receipt issuer embeds exact admitted evidence and Result inventory" {
  let program = ordering_test_cid("8")
  let template = receipt_test_template(program)
  let admission = receipt_test_admission(template)
  let run = issue_run_definition(
    admission,
    "scope",
    "run",
    ordering_test_cid("0"),
    "2026-09-18T00:00:00.000Z",
    "2026-09-18T04:00:00.000Z",
    65536,
    1024,
    12,
  ).unwrap()
  let observation = receipt_test_observation(template)
  let invocation = issue_run_invocation(template, observation, 65536, 1024, 12).unwrap()
  let policy = ordering_test_cid("e")
  let retention = manifest_test_retention(policy)
  let (definition, evidence, artifact) = manifest_test_result(
    "answer",
    ordering_test_cid("f"),
    invocation,
    retention,
    policy,
  )
  let manifest = issue_result_manifest(
    run,
    invocation,
    [definition],
    [artifact],
    65536,
    1024,
    12,
  ).unwrap()
  let receipt = issue_effect_free_run_receipt(
    admission,
    run,
    invocation,
    observation,
    [definition],
    [artifact],
    manifest,
    receipt_test_journal(),
    "compiler-0.1",
    "aoa-ir-0.1",
    ordering_test_cid("a"),
    ordering_test_cid("b"),
    ["program"],
    ["c".repeat(64)],
    [],
    [],
    [],
    65536,
    1024,
    12,
  ).unwrap()
  let wire = publication_contract_json(receipt)
  assert_true(wire.contains("\"version\":\"actql-run-receipt/0.1\""))
  assert_true(
    wire.contains(
      "\"result_manifest_cid\":\"" +
      publication_contract_identity(manifest) +
      "\"",
    ),
  )
  assert_true(
    wire.contains(
      "\"artifact_derivation_evidence_cids\":[\"" +
      publication_contract_identity(
        result_ordering_derivation_contract(evidence),
      ) +
      "\"]",
    ),
  )
}

///|
test "Run Receipt issuer rejects a foreign captured ObservationSet" {
  let program = ordering_test_cid("8")
  let template = receipt_test_template(program)
  let admission = receipt_test_admission(template)
  let run = issue_run_definition(
    admission,
    "scope",
    "run",
    ordering_test_cid("0"),
    "2026-09-18T00:00:00.000Z",
    "2026-09-18T04:00:00.000Z",
    65536,
    1024,
    12,
  ).unwrap()
  let observation = receipt_test_observation(template)
  let invocation = issue_run_invocation(template, observation, 65536, 1024, 12).unwrap()
  let retention = manifest_test_retention(ordering_test_cid("e"))
  let (definition, _, artifact) = manifest_test_result(
    "answer",
    ordering_test_cid("f"),
    invocation,
    retention,
    ordering_test_cid("e"),
  )
  let manifest = issue_result_manifest(
    run,
    invocation,
    [definition],
    [artifact],
    65536,
    1024,
    12,
  ).unwrap()
  let foreign = receipt_test_observation(
    receipt_test_template(ordering_test_cid("9")),
  )
  assert_true(
    issue_effect_free_run_receipt(
      admission,
      run,
      invocation,
      foreign,
      [definition],
      [artifact],
      manifest,
      receipt_test_journal(),
      "compiler-0.1",
      "aoa-ir-0.1",
      ordering_test_cid("a"),
      ordering_test_cid("b"),
      [],
      [],
      [],
      [],
      [],
      65536,
      1024,
      12,
    )
    is Err(ReceiptIssuanceReferenceMismatch("invocation")),
  )
}
