///|
test "durable Result binding fixes semantic and physical identities" {
  let template = ordering_test_cid("d")
  let run = manifest_test_run(template)
  let invocation = manifest_test_invocation(template)
  let policy = ordering_test_cid("e")
  let retention = manifest_test_retention(policy)
  let (definition, evidence, artifact) = manifest_test_result(
    "answer",
    ordering_test_cid("f"),
    invocation,
    retention,
    policy,
  )
  let ordering = result_ordering_evidence_contract(evidence)
  let binding = issue_durable_result_binding(
    run,
    definition,
    invocation,
    artifact,
    ordering,
    retention,
    ordering_test_cid("1"),
    ordering_test_cid("2"),
    ordering_test_cid("3"),
    2,
    97,
    "4".repeat(64),
    32768,
    256,
    8,
  ).unwrap()
  let wire = publication_contract_json(binding)
  assert_true(
    wire.contains(
      "\"result_definition_cid\":\"" +
      publication_contract_identity(definition) +
      "\"",
    ),
  )
  assert_true(
    wire.contains("\"logical_result_cid\":\"" + ordering_test_cid("9") + "\""),
  )
  assert_true(wire.contains("\"row_count\":2"))
  assert_true(wire.contains("\"byte_count\":97"))
}

///|
test "durable Result binding rejects mismatched Result evidence" {
  let template = ordering_test_cid("d")
  let run = manifest_test_run(template)
  let invocation = manifest_test_invocation(template)
  let policy = ordering_test_cid("e")
  let retention = manifest_test_retention(policy)
  let (definition, evidence, artifact) = manifest_test_result(
    "answer",
    ordering_test_cid("f"),
    invocation,
    retention,
    policy,
  )
  let foreign = result_definition_contract(
    prepare_result_definition(ordering_test_cid("8"), "foreign").unwrap(),
  )
  assert_true(
    issue_durable_result_binding(
      run,
      foreign,
      invocation,
      artifact,
      result_ordering_evidence_contract(evidence),
      retention,
      ordering_test_cid("1"),
      ordering_test_cid("2"),
      ordering_test_cid("3"),
      2,
      97,
      "4".repeat(64),
      32768,
      256,
      8,
    )
    is Err(DurableBindingReferenceMismatch("result_definition_cid")),
  )
  assert_true(
    issue_durable_result_binding(
      run,
      definition,
      invocation,
      artifact,
      result_ordering_evidence_contract(evidence),
      retention,
      ordering_test_cid("1"),
      ordering_test_cid("2"),
      ordering_test_cid("3"),
      1,
      97,
      "4".repeat(64),
      32768,
      256,
      8,
    )
    is Err(DurableBindingReferenceMismatch("row_count")),
  )
}
