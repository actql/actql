///|
fn delivery_test_cid(character : String) -> String {
  "sha256:" + character.repeat(64)
}

///|
fn delivery_test_contract(name : String, body : String) -> PublicationContract {
  seal_publication_contract(name, body, 32768, 256, 16).unwrap()
}

///|
fn delivery_test_root() -> (
  PublicationContract,
  PublicationContract,
  PublicationContract,
) {
  let c = delivery_test_cid("a")
  let artifact = delivery_test_contract(
    "result_artifact",
    "{\"version\":\"actql-result-artifact/0.1\"," +
    "\"result_definition_cid\":\"" +
    c +
    "\",\"invocation_cid\":\"" +
    delivery_test_cid("b") +
    "\",\"logical_result_cid\":\"" +
    delivery_test_cid("c") +
    "\",\"result_schema_cid\":\"" +
    delivery_test_cid("d") +
    "\",\"ordering_evidence_cid\":\"" +
    delivery_test_cid("e") +
    "\",\"actual_row_count\":2,\"actual_completeness\":\"complete\"," +
    "\"effective_data_policy_cid\":\"" +
    delivery_test_cid("f") +
    "\",\"effective_retention_policy_cid\":\"" +
    delivery_test_cid("1") +
    "\",\"provenance_evidence_cids\":[\"" +
    delivery_test_cid("2") +
    "\"]}",
  )
  let manifest = delivery_test_contract(
    "result_manifest",
    "{\"version\":\"actql-result-manifest/0.1\"," +
    "\"run_definition_cid\":\"" +
    delivery_test_cid("3") +
    "\",\"invocation_cid\":\"" +
    delivery_test_cid("b") +
    "\",\"results\":{\"answer\":" +
    publication_contract_json(artifact) +
    "}}",
  )
  let index = delivery_test_contract(
    "public_index_entry",
    "{\"version\":\"actql-public-index-entry/0.1\"," +
    "\"tenant_id\":\"tenant\",\"authority_scope_cid\":\"" +
    delivery_test_cid("4") +
    "\",\"run_definition_cid\":\"" +
    delivery_test_cid("3") +
    "\",\"invocation_cid\":\"" +
    delivery_test_cid("b") +
    "\",\"result_manifest_cid\":\"" +
    publication_contract_identity(manifest) +
    "\",\"run_receipt_cid\":\"" +
    delivery_test_cid("5") +
    "\",\"captured_run_cid\":\"" +
    delivery_test_cid("6") +
    "\",\"durable_result_binding_cids\":[\"" +
    delivery_test_cid("7") +
    "\"],\"publication_request_cid\":\"" +
    delivery_test_cid("8") +
    "\",\"publication_attempt_cid\":\"" +
    delivery_test_cid("9") +
    "\",\"committed_at\":\"2026-09-18T00:00:00.000Z\"}",
  )
  (index, manifest, artifact)
}

///|
test "serialization profiles have independent fixed identities" {
  assert_eq(
    result_serialization_contract_cid("json", 4096, 16, 4).unwrap(),
    "sha256:f8a9922a194323d7b0f33733eb29753a6b68b48becee913cedb30a23a97cedf8",
  )
  assert_eq(
    result_serialization_contract_cid("jsonl", 4096, 16, 4).unwrap(),
    "sha256:2b15824ab044228057826503eb186f7608e2fc05a1564bb18f057d6eb7bb5041",
  )
  assert_eq(
    result_serialization_contract_cid("csv", 4096, 16, 4).unwrap(),
    "sha256:13bb11256c3044cca8911b72af055d0792c237efeae46dda72ec618652041c0a",
  )
  assert_true(
    result_serialization_contract_cid("other", 4096, 16, 4)
    is Err(DeliveryIssuanceUnsupportedFormat("other")),
  )
}

///|
test "read grant and attempt bind an exact committed Result" {
  let (index, manifest, artifact) = delivery_test_root()
  let grant = issue_result_read_grant(
    index,
    manifest,
    ["answer"],
    ["csv", "json"],
    "principal",
    "download",
    delivery_test_cid("a"),
    4096,
    2,
    "2026-09-19T00:00:00.000Z",
    delivery_test_cid("b"),
    delivery_test_cid("c"),
    32768,
    256,
    16,
  ).unwrap()
  let grant_wire = publication_contract_json(grant)
  assert_true(grant_wire.contains("\"formats\":[\"json\",\"csv\"]"))
  assert_true(
    grant_wire.contains(
      "\"results\":[{\"result_artifact_cid\":\"" +
      publication_contract_identity(artifact) +
      "\",\"result_name\":\"answer\"}]",
    ),
  )
  let attempt = issue_delivery_attempt(
    index, manifest, grant, "answer", "json", "attempt-1", "2026-09-18T01:00:00.000Z",
    32768, 256, 16,
  ).unwrap()
  assert_true(
    publication_contract_json(attempt).contains(
      "\"serialization_contract_cid\":\"" +
      "sha256:f8a9922a194323d7b0f33733eb29753a6b68b48becee913cedb30a23a97cedf8" +
      "\"",
    ),
  )
  assert_true(
    issue_delivery_attempt(
      index, manifest, grant, "answer", "jsonl", "attempt-2", "2026-09-18T01:00:00.000Z",
      32768, 256, 16,
    )
    is Err(DeliveryIssuanceUnsupportedFormat("jsonl")),
  )
}

///|
test "delivery receipt and records preserve attempt occurrence" {
  let (index, manifest, _) = delivery_test_root()
  let grant = issue_result_read_grant(
    index,
    manifest,
    ["answer"],
    ["json"],
    "principal",
    "download",
    delivery_test_cid("a"),
    4096,
    1,
    "2026-09-19T00:00:00.000Z",
    delivery_test_cid("b"),
    delivery_test_cid("c"),
    32768,
    256,
    16,
  ).unwrap()
  let attempt = issue_delivery_attempt(
    index, manifest, grant, "answer", "json", "attempt-1", "2026-09-18T01:00:00.000Z",
    32768, 256, 16,
  ).unwrap()
  let streaming = issue_delivery_record(
    attempt,
    None,
    "streaming",
    0,
    "exact",
    None,
    None,
    None,
    None,
    "2026-09-18T01:00:00.000Z",
    [],
    32768,
    256,
    16,
  ).unwrap()
  let receipt = issue_result_delivery_receipt(
    index,
    manifest,
    grant,
    attempt,
    12,
    "d".repeat(64),
    32768,
    256,
    16,
  ).unwrap()
  let succeeded = issue_delivery_record(
    attempt,
    Some(streaming),
    "succeeded",
    12,
    "exact",
    None,
    Some("d".repeat(64)),
    Some(receipt),
    None,
    "2026-09-18T01:00:01.000Z",
    [],
    32768,
    256,
    16,
  ).unwrap()
  assert_true(
    publication_contract_json(succeeded).contains(
      "\"result_delivery_receipt_cid\":\"" +
      publication_contract_identity(receipt) +
      "\"",
    ),
  )
  assert_true(
    issue_delivery_record(
      attempt,
      Some(succeeded),
      "failed",
      12,
      "exact",
      None,
      None,
      None,
      Some(delivery_test_cid("e")),
      "2026-09-18T01:00:02.000Z",
      [],
      32768,
      256,
      16,
    )
    is Err(DeliveryIssuanceTransition(DeliveryStateMismatch)),
  )
}

///|
test "foreign index and manifest cannot issue read authority" {
  let (index, _, artifact) = delivery_test_root()
  let foreign = delivery_test_contract(
    "result_manifest",
    "{\"version\":\"actql-result-manifest/0.1\"," +
    "\"run_definition_cid\":\"" +
    delivery_test_cid("4") +
    "\",\"invocation_cid\":\"" +
    delivery_test_cid("b") +
    "\",\"results\":{\"answer\":" +
    publication_contract_json(artifact) +
    "}}",
  )
  assert_true(
    issue_manifest_read_grant(
      index,
      foreign,
      "principal",
      "inspect",
      delivery_test_cid("a"),
      4096,
      1,
      "2026-09-19T00:00:00.000Z",
      delivery_test_cid("b"),
      32768,
      256,
      16,
    )
    is Err(DeliveryIssuanceReferenceMismatch("result_manifest_cid")),
  )
}
