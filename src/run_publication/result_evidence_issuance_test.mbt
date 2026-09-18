///|
test "Result evidence issuer binds exact output identities and canonical inputs" {
  let definition = result_definition_contract(
    prepare_result_definition(ordering_test_cid("1"), "answer").unwrap(),
  )
  let evidence = issue_result_occurrence_evidence(
    definition,
    ordering_test_cid("2"),
    ordering_test_cid("3"),
    ordering_test_cid("4"),
    [ordering_test_cid("6"), ordering_test_cid("5")],
    ordering_test_cid("7"),
    ordering_test_cid("8"),
    "common-host",
    ordering_test_cid("9"),
    8192,
    64,
    5,
  ).unwrap()
  let derivation = result_ordering_derivation_contract(evidence)
  let ordering = result_ordering_evidence_contract(evidence)
  let derivation_wire = publication_contract_json(derivation)
  let ordering_wire = publication_contract_json(ordering)
  assert_true(
    derivation_wire.contains(
      "\"logical_value_cid\":\"" + ordering_test_cid("2") + "\"",
    ),
  )
  assert_true(
    derivation_wire.contains(
      "\"relation_schema_cid\":\"" + ordering_test_cid("3") + "\"",
    ),
  )
  assert_true(
    ordering_wire.contains(
      "\"producer_contract_cid\":\"" +
      publication_contract_identity(definition) +
      "\"",
    ),
  )
  assert_true(
    derivation_wire.contains(
      "\"input_relation_cids\":[\"" +
      ordering_test_cid("5") +
      "\",\"" +
      ordering_test_cid("6") +
      "\"]",
    ),
  )
}

///|
test "Result evidence issuer rejects duplicate or malformed context" {
  let definition = result_definition_contract(
    prepare_result_definition(ordering_test_cid("1"), "answer").unwrap(),
  )
  assert_true(
    issue_result_occurrence_evidence(
      definition,
      ordering_test_cid("2"),
      ordering_test_cid("3"),
      ordering_test_cid("4"),
      [ordering_test_cid("5"), ordering_test_cid("5")],
      ordering_test_cid("7"),
      ordering_test_cid("8"),
      "common-host",
      ordering_test_cid("9"),
      8192,
      64,
      5,
    )
    is Err(IssuanceDuplicateInput),
  )
  assert_true(
    issue_result_occurrence_evidence(
      definition,
      "not-a-cid",
      ordering_test_cid("3"),
      ordering_test_cid("4"),
      [],
      ordering_test_cid("7"),
      ordering_test_cid("8"),
      "common-host",
      ordering_test_cid("9"),
      8192,
      64,
      5,
    )
    is Err(IssuanceInvalidIdentity),
  )
}

///|
test "complete Result Artifact is issued from bound evidence contracts" {
  let definition = result_definition_contract(
    prepare_result_definition(ordering_test_cid("1"), "answer").unwrap(),
  )
  let policy = ordering_test_cid("8")
  let evidence = issue_result_occurrence_evidence(
    definition,
    ordering_test_cid("2"),
    ordering_test_cid("3"),
    ordering_test_cid("4"),
    [],
    ordering_test_cid("7"),
    policy,
    "common-host",
    ordering_test_cid("9"),
    8192,
    64,
    5,
  ).unwrap()
  let invocation = seal_publication_contract(
    "run_invocation",
    "{\"version\":\"actql-run-invocation/0.1\"," +
    "\"invocation_template_cid\":\"" +
    ordering_test_cid("a") +
    "\",\"observation_set_cid\":\"" +
    ordering_test_cid("b") +
    "\"}",
    8192,
    64,
    5,
  ).unwrap()
  let retention = seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    ordering_test_cid("c") +
    "\",\"effective_data_policy_cid\":\"" +
    policy +
    "\",\"available_until\":\"2026-09-18T01:00:00.000Z\"," +
    "\"delete_by\":\"2026-09-18T02:00:00.000Z\"," +
    "\"extension_ceiling_at\":\"2026-09-18T03:00:00.000Z\"," +
    "\"metadata_retention_policy_cid\":\"" +
    ordering_test_cid("d") +
    "\",\"metadata_delete_by\":\"2026-09-18T04:00:00.000Z" +
    "\",\"clock_contract_cid\":\"" +
    ordering_test_cid("e") +
    "\"}",
    8192,
    64,
    5,
  ).unwrap()
  let artifact = issue_complete_result_artifact(
    definition, invocation, evidence, retention, 3, 16384, 128, 5,
  ).unwrap()
  let wire = publication_contract_json(artifact)
  assert_true(wire.contains("\"actual_completeness\":\"complete\""))
  assert_true(wire.contains("\"actual_row_count\":3"))
  assert_true(
    wire.contains(
      "\"invocation_cid\":\"" + publication_contract_identity(invocation) + "\"",
    ),
  )
  let foreign_retention = seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    ordering_test_cid("c") +
    "\",\"effective_data_policy_cid\":\"" +
    ordering_test_cid("f") +
    "\",\"available_until\":\"2026-09-18T01:00:00.000Z\"," +
    "\"delete_by\":\"2026-09-18T02:00:00.000Z\"," +
    "\"extension_ceiling_at\":\"2026-09-18T03:00:00.000Z\"," +
    "\"metadata_retention_policy_cid\":\"" +
    ordering_test_cid("d") +
    "\",\"metadata_delete_by\":\"2026-09-18T04:00:00.000Z" +
    "\",\"clock_contract_cid\":\"" +
    ordering_test_cid("e") +
    "\"}",
    8192,
    64,
    5,
  ).unwrap()
  assert_true(
    issue_complete_result_artifact(
      definition, invocation, evidence, foreign_retention, 3, 16384, 128, 5,
    )
    is Err(ArtifactIssuancePolicyMismatch),
  )
}
