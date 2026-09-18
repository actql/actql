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
