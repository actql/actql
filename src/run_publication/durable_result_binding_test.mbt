///|
test "durable Result binding fixes semantic and physical identities" {
  let schema_cid = "sha256:4b94cf57d7e0fa174c9edbdc43b22f3ca573038098f1b29ed64f39b149edc8a1"
  let template = ordering_test_cid("d")
  let run = manifest_test_run(template)
  let invocation = manifest_test_invocation(template)
  let policy = ordering_test_cid("e")
  let retention = manifest_test_retention(policy)
  let (definition, evidence, artifact) = manifest_test_result(
    "answer", schema_cid, invocation, retention, policy,
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
    ["answer"],
    "{\"answer\":{\"nullable\":false,\"type\":\"integer\"}}",
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
  assert_true(wire.contains("\"result_fields\":[\"answer\"]"))
  let schema_wire = "{\"answer\":{\"nullable\":false,\"type\":\"integer\"}}"
  let schema = admit_hashed_effect_dependency_body(
    "relation_schema", schema_cid, schema_wire, 32768, 256, 8,
  ).unwrap()
  let retained = issue_durable_result_binding(
    run,
    definition,
    invocation,
    artifact,
    ordering,
    retention,
    ordering_test_cid("1"),
    ["answer"],
    schema_wire,
    ordering_test_cid("2"),
    ordering_test_cid("3"),
    2,
    97,
    "4".repeat(64),
    32768,
    256,
    8,
    schema_original=Some(schema),
  ).unwrap()
  assert_eq(publication_contract_json(retained), wire)
  assert_true(
    issue_durable_result_binding(
      run,
      definition,
      invocation,
      artifact,
      ordering,
      retention,
      ordering_test_cid("1"),
      ["answer"],
      "{}",
      ordering_test_cid("2"),
      ordering_test_cid("3"),
      2,
      97,
      "4".repeat(64),
      32768,
      256,
      8,
      schema_original=Some(schema),
    )
    is Err(DurableBindingInvalidPhysicalIdentity),
  )
}

///|
test "durable Result binding rejects mismatched Result evidence" {
  let schema_cid = "sha256:4b94cf57d7e0fa174c9edbdc43b22f3ca573038098f1b29ed64f39b149edc8a1"
  let template = ordering_test_cid("d")
  let run = manifest_test_run(template)
  let invocation = manifest_test_invocation(template)
  let policy = ordering_test_cid("e")
  let retention = manifest_test_retention(policy)
  let (definition, evidence, artifact) = manifest_test_result(
    "answer", schema_cid, invocation, retention, policy,
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
      ["answer"],
      "{\"answer\":{\"nullable\":false,\"type\":\"integer\"}}",
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
      ["answer"],
      "{\"answer\":{\"nullable\":false,\"type\":\"integer\"}}",
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
  assert_true(
    issue_durable_result_binding(
      run,
      definition,
      invocation,
      artifact,
      result_ordering_evidence_contract(evidence),
      retention,
      ordering_test_cid("1"),
      ["missing"],
      "{\"answer\":{\"nullable\":false,\"type\":\"integer\"}}",
      ordering_test_cid("2"),
      ordering_test_cid("3"),
      2,
      97,
      "4".repeat(64),
      32768,
      256,
      8,
    )
    is Err(DurableBindingInvalidPhysicalIdentity),
  )
}
