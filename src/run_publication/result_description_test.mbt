///|
test "description projects exact retained evidence and rejects substitutions" {
  let schema = "{\"answer\":{\"nullable\":false,\"type\":\"integer\"}}"
  // Independent fixed canonical schema vector, also used by the binding tests.
  let schema_cid = "sha256:4b94cf57d7e0fa174c9edbdc43b22f3ca573038098f1b29ed64f39b149edc8a1"
  let template = ordering_test_cid("d")
  let run = manifest_test_run(template)
  let invocation = manifest_test_invocation(template)
  let policy = ordering_test_cid("e")
  let retention = manifest_test_retention(policy)
  let (definition, evidence, artifact) = manifest_test_result(
    "answer", schema_cid, invocation, retention, policy,
  )
  let binding = issue_durable_result_binding(
    run,
    definition,
    invocation,
    artifact,
    result_ordering_evidence_contract(evidence),
    retention,
    ordering_test_cid("1"),
    ["answer"],
    schema,
    ordering_test_cid("2"),
    ordering_test_cid("3"),
    2,
    97,
    "4".repeat(64),
    32768,
    256,
    8,
  ).unwrap()
  let manifest = issue_result_manifest(
    run,
    invocation,
    [definition],
    [artifact],
    32768,
    256,
    16,
  ).unwrap()
  let index = delivery_test_contract(
    "public_index_entry",
    "{\"version\":\"actql-public-index-entry/0.1\"," +
    "\"namespace_id\":\"description\",\"authority_scope_cid\":\"" +
    ordering_test_cid("4") +
    "\",\"run_definition_cid\":\"" +
    publication_contract_identity(run) +
    "\",\"invocation_cid\":\"" +
    publication_contract_identity(invocation) +
    "\",\"result_manifest_cid\":\"" +
    publication_contract_identity(manifest) +
    "\",\"run_receipt_cid\":\"" +
    ordering_test_cid("5") +
    "\",\"captured_run_cid\":\"" +
    ordering_test_cid("6") +
    "\",\"durable_result_binding_cids\":[\"" +
    publication_contract_identity(binding) +
    "\"],\"publication_request_cid\":\"" +
    ordering_test_cid("7") +
    "\",\"publication_attempt_cid\":\"" +
    ordering_test_cid("8") +
    "\",\"committed_at\":\"2026-09-30T00:00:00.000Z\"}",
  )
  let description = describe_committed_result(
    index,
    manifest,
    "answer",
    [binding],
    definition,
    schema,
    "jsonl",
    32768,
    256,
    16,
  ).unwrap()
  assert_true(
    description.contains(
      "\"columns\":[{\"contract\":{\"nullable\":false,\"type\":\"integer\"},\"name\":\"answer\"}]",
    ),
  )
  assert_true(
    description.contains("\"resultSchemaCid\":\"" + schema_cid + "\""),
  )
  assert_true(
    description.contains(
      "\"contractCid\":\"sha256:61035606b44ad7f4dc24127825bcc46636f40ce5e06881cf9c97996dcb3bde84\"",
    ),
  )
  assert_true(
    describe_committed_result(
      index,
      manifest,
      "answer",
      [],
      definition,
      schema,
      "jsonl",
      32768,
      256,
      16,
    )
    is Err(DeliveryIssuanceReferenceMismatch("index.bindings")),
  )
  let foreign = result_definition_contract(
    prepare_result_definition(ordering_test_cid("0"), "answer").unwrap(),
  )
  assert_true(
    describe_committed_result(
      index,
      manifest,
      "answer",
      [binding],
      foreign,
      schema,
      "jsonl",
      32768,
      256,
      16,
    )
    is Err(DeliveryIssuanceReferenceMismatch("description.definition")),
  )
  assert_true(
    describe_committed_result(
      index,
      manifest,
      "answer",
      [binding],
      definition,
      "{\"answer\":{\"nullable\":true,\"type\":\"integer\"}}",
      "jsonl",
      32768,
      256,
      16,
    )
    is Err(_),
  )
  assert_true(
    describe_committed_result(
      index,
      manifest,
      "answer",
      [binding],
      definition,
      schema,
      "parquet",
      32768,
      256,
      16,
    )
    is Err(_),
  )
  assert_true(
    describe_committed_result(
      index,
      manifest,
      "answer",
      [binding],
      definition,
      schema,
      "jsonl",
      64,
      256,
      16,
    )
    is Err(DeliveryIssuanceEncoding),
  )
}
