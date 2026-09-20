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
test "committed Result projection selects the exact indexed binding" {
  let run_definition_cid = delivery_test_cid("1")
  let invocation_cid = delivery_test_cid("2")
  let definition_cid = delivery_test_cid("3")
  let logical_cid = delivery_test_cid("4")
  let schema_cid = delivery_test_cid("5")
  let ordering_cid = delivery_test_cid("6")
  let retention_cid = delivery_test_cid("7")
  let material_cid = delivery_test_cid("8")
  let store_cid = delivery_test_cid("9")
  let codec_cid = delivery_test_cid("a")
  let physical_digest = "b".repeat(64)
  let artifact = delivery_test_contract(
    "result_artifact",
    "{\"version\":\"actql-result-artifact/0.1\"," +
    "\"result_definition_cid\":\"" +
    definition_cid +
    "\",\"invocation_cid\":\"" +
    invocation_cid +
    "\",\"logical_result_cid\":\"" +
    logical_cid +
    "\",\"result_schema_cid\":\"" +
    schema_cid +
    "\",\"ordering_evidence_cid\":\"" +
    ordering_cid +
    "\",\"actual_row_count\":2,\"actual_completeness\":\"complete\"," +
    "\"effective_data_policy_cid\":\"" +
    delivery_test_cid("c") +
    "\",\"effective_retention_policy_cid\":\"" +
    retention_cid +
    "\",\"provenance_evidence_cids\":[\"" +
    delivery_test_cid("d") +
    "\"]}",
  )
  let manifest = delivery_test_contract(
    "result_manifest",
    "{\"version\":\"actql-result-manifest/0.1\"," +
    "\"run_definition_cid\":\"" +
    run_definition_cid +
    "\",\"invocation_cid\":\"" +
    invocation_cid +
    "\",\"results\":{\"answer\":" +
    publication_contract_json(artifact) +
    "}}",
  )
  let binding = delivery_test_contract(
    "durable_result_binding",
    "{\"version\":\"actql-durable-result-binding/0.1\"," +
    "\"run_definition_cid\":\"" +
    run_definition_cid +
    "\",\"result_definition_cid\":\"" +
    definition_cid +
    "\",\"invocation_cid\":\"" +
    invocation_cid +
    "\",\"logical_result_cid\":\"" +
    logical_cid +
    "\",\"result_schema_cid\":\"" +
    schema_cid +
    "\",\"ordering_evidence_cid\":\"" +
    ordering_cid +
    "\",\"codec_contract_cid\":\"" +
    codec_cid +
    "\",\"result_fields\":[\"value\"]," +
    "\"material_generation_cid\":\"" +
    material_cid +
    "\",\"store_authority_cid\":\"" +
    store_cid +
    "\",\"effective_retention_policy_cid\":\"" +
    retention_cid +
    "\",\"row_count\":2,\"byte_count\":24,\"physical_sha256\":\"" +
    physical_digest +
    "\"}",
  )
  let index = delivery_test_contract(
    "public_index_entry",
    "{\"version\":\"actql-public-index-entry/0.1\"," +
    "\"tenant_id\":\"tenant\",\"authority_scope_cid\":\"" +
    delivery_test_cid("e") +
    "\",\"run_definition_cid\":\"" +
    run_definition_cid +
    "\",\"invocation_cid\":\"" +
    invocation_cid +
    "\",\"result_manifest_cid\":\"" +
    publication_contract_identity(manifest) +
    "\",\"run_receipt_cid\":\"" +
    delivery_test_cid("f") +
    "\",\"captured_run_cid\":\"" +
    delivery_test_cid("0") +
    "\",\"durable_result_binding_cids\":[\"" +
    publication_contract_identity(binding) +
    "\"],\"publication_request_cid\":\"" +
    delivery_test_cid("a") +
    "\",\"publication_attempt_cid\":\"" +
    delivery_test_cid("b") +
    "\",\"committed_at\":\"2026-09-18T00:00:00.000Z\"}",
  )
  let index_read = project_public_index_read(index).unwrap()
  assert_eq(
    index_read.result_manifest_cid,
    publication_contract_identity(manifest),
  )
  assert_eq(index_read.durable_result_binding_cids, [
    publication_contract_identity(binding),
  ])
  let resolved = project_committed_result_read(index, manifest, "answer", [
    binding,
  ]).unwrap()
  assert_eq(
    resolved.result_artifact_cid,
    publication_contract_identity(artifact),
  )
  assert_eq(resolved.material_generation_cid, material_cid)
  assert_eq(resolved.result_fields, ["value"])
  assert_eq(resolved.row_count, 2L)
  assert_eq(resolved.byte_count, 24L)
  assert_true(
    project_committed_result_read(index, manifest, "missing", [binding])
    is Err(DeliveryIssuanceUnknownResult("missing")),
  )
  assert_true(
    project_committed_result_read(index, manifest, "answer", [])
    is Err(DeliveryIssuanceReferenceMismatch("index.bindings")),
  )
}

///|
test "read grant and attempt bind an exact committed Result" {
  let (index, manifest, artifact) = delivery_test_root()
  let retention = delivery_test_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    delivery_test_cid("a") +
    "\",\"effective_data_policy_cid\":\"" +
    delivery_test_cid("b") +
    "\",\"available_until\":\"2026-09-18T02:00:00.000Z\"," +
    "\"delete_by\":\"2026-09-18T03:00:00.000Z\"," +
    "\"extension_ceiling_at\":\"2026-09-18T04:00:00.000Z\"," +
    "\"metadata_retention_policy_cid\":\"" +
    delivery_test_cid("c") +
    "\",\"metadata_delete_by\":\"2026-09-18T05:00:00.000Z" +
    "\",\"clock_contract_cid\":\"" +
    delivery_test_cid("d") +
    "\"}",
  )
  assert_eq(
    result_read_retention_policy_cid(manifest, "answer"),
    Ok(delivery_test_cid("1")),
  )
  assert_true(
    result_read_availability(
      manifest, "answer", retention, "2026-09-18T01:00:00.000Z",
    )
    is Err(DeliveryIssuanceReferenceMismatch("effective_retention_policy_cid")),
  )
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
  assert_eq(
    delivery_result_definition_cid(manifest, attempt),
    Ok(delivery_test_cid("a")),
  )
  assert_true(result_read_grant_allows_bytes(grant, 4096))
  assert_false(result_read_grant_allows_bytes(grant, 4097))
  assert_true(result_read_grant_valid_at(grant, "2026-09-19T00:00:00.000Z"))
  assert_false(result_read_grant_valid_at(grant, "2026-09-19T00:00:00.001Z"))
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
  assert_true(
    issue_delivery_attempt(
      index, manifest, grant, "answer", "json", "attempt-expired", "2026-09-19T00:00:00.001Z",
      32768, 256, 16,
    )
    is Err(DeliveryIssuanceExpiredGrant),
  )
}

///|
test "read grant use claims are durable, bounded, and retry-idempotent" {
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
  let first = issue_delivery_attempt(
    index, manifest, grant, "answer", "json", "attempt-1", "2026-09-18T01:00:00.000Z",
    32768, 256, 16,
  ).unwrap()
  let claim = prepare_delivery_grant_usage_claim(
    grant,
    None,
    first,
    32768,
    256,
    16,
  ).unwrap()
  assert_true(delivery_grant_usage_claim_is_new(claim))
  let wire = delivery_grant_usage_claim_wire(claim)
  let retry = prepare_delivery_grant_usage_claim(
    grant,
    Some(wire),
    first,
    32768,
    256,
    16,
  ).unwrap()
  assert_false(delivery_grant_usage_claim_is_new(retry))
  assert_eq(delivery_grant_usage_claim_wire(retry), wire)
  let second = issue_delivery_attempt(
    index, manifest, grant, "answer", "json", "attempt-2", "2026-09-18T01:00:01.000Z",
    32768, 256, 16,
  ).unwrap()
  assert_true(
    prepare_delivery_grant_usage_claim(
      grant,
      Some(wire),
      second,
      32768,
      256,
      16,
    )
    is Err(DeliveryGrantUsageExhausted),
  )
  assert_true(
    prepare_delivery_grant_usage_claim(
      grant,
      Some(
        "{\"delivery_attempt_cids\":[],\"grant_cid\":\"" +
        publication_contract_identity(grant) +
        "\",\"max_uses\":1,\"use_count\":1," +
        "\"version\":\"actql-result-read-grant-usage/0.1\"}",
      ),
      first,
      32768,
      256,
      16,
    )
    is Err(DeliveryGrantUsageInvalidWire),
  )
}

///|
test "delivery payload binding matches the committed logical Result" {
  let schema_wire = "{\"answer\":{\"nullable\":false,\"type\":\"integer\"}}"
  let schema_cid = "sha256:4b94cf57d7e0fa174c9edbdc43b22f3ca573038098f1b29ed64f39b149edc8a1"
  let definition_cid = delivery_test_cid("a")
  let invocation_cid = delivery_test_cid("b")
  let logical_cid = delivery_test_cid("c")
  let ordering_cid = delivery_test_cid("d")
  let retention_cid = delivery_test_cid("e")
  let artifact = delivery_test_contract(
    "result_artifact",
    "{\"version\":\"actql-result-artifact/0.1\"," +
    "\"result_definition_cid\":\"" +
    definition_cid +
    "\",\"invocation_cid\":\"" +
    invocation_cid +
    "\",\"logical_result_cid\":\"" +
    logical_cid +
    "\",\"result_schema_cid\":\"" +
    schema_cid +
    "\",\"ordering_evidence_cid\":\"" +
    ordering_cid +
    "\",\"actual_row_count\":1,\"actual_completeness\":\"complete\"," +
    "\"effective_data_policy_cid\":\"" +
    delivery_test_cid("f") +
    "\",\"effective_retention_policy_cid\":\"" +
    retention_cid +
    "\",\"provenance_evidence_cids\":[]}",
  )
  let run_definition_cid = delivery_test_cid("1")
  let authority_cid = delivery_test_cid("2")
  let manifest = delivery_test_contract(
    "result_manifest",
    "{\"version\":\"actql-result-manifest/0.1\"," +
    "\"run_definition_cid\":\"" +
    run_definition_cid +
    "\",\"invocation_cid\":\"" +
    invocation_cid +
    "\",\"results\":{\"answer\":" +
    publication_contract_json(artifact) +
    "}}",
  )
  let index = delivery_test_contract(
    "public_index_entry",
    "{\"version\":\"actql-public-index-entry/0.1\"," +
    "\"tenant_id\":\"tenant\",\"authority_scope_cid\":\"" +
    delivery_test_cid("3") +
    "\",\"run_definition_cid\":\"" +
    run_definition_cid +
    "\",\"invocation_cid\":\"" +
    invocation_cid +
    "\",\"result_manifest_cid\":\"" +
    publication_contract_identity(manifest) +
    "\",\"run_receipt_cid\":\"" +
    delivery_test_cid("4") +
    "\",\"captured_run_cid\":\"" +
    delivery_test_cid("5") +
    "\",\"durable_result_binding_cids\":[\"" +
    delivery_test_cid("6") +
    "\"],\"publication_request_cid\":\"" +
    delivery_test_cid("7") +
    "\",\"publication_attempt_cid\":\"" +
    delivery_test_cid("8") +
    "\",\"committed_at\":\"2026-09-18T00:00:00.000Z\"}",
  )
  let grant = issue_result_read_grant(
    index,
    manifest,
    ["answer"],
    ["json"],
    "principal",
    "download",
    delivery_test_cid("9"),
    1024,
    1,
    "2026-09-19T00:00:00.000Z",
    delivery_test_cid("0"),
    delivery_test_cid("9"),
    32768,
    256,
    16,
  ).unwrap()
  let attempt = issue_delivery_attempt(
    index, manifest, grant, "answer", "json", "attempt-binding", "2026-09-18T01:00:00.000Z",
    32768, 256, 16,
  ).unwrap()
  let material_cid = delivery_test_cid("6")
  let codec_cid = delivery_test_cid("7")
  let physical_digest = "8".repeat(64)
  let binding = delivery_test_contract(
    "durable_result_binding",
    "{\"version\":\"actql-durable-result-binding/0.1\"," +
    "\"run_definition_cid\":\"" +
    run_definition_cid +
    "\",\"result_definition_cid\":\"" +
    definition_cid +
    "\",\"invocation_cid\":\"" +
    invocation_cid +
    "\",\"logical_result_cid\":\"" +
    logical_cid +
    "\",\"result_schema_cid\":\"" +
    schema_cid +
    "\",\"ordering_evidence_cid\":\"" +
    ordering_cid +
    "\",\"codec_contract_cid\":\"" +
    codec_cid +
    "\",\"result_fields\":[\"answer\"]," +
    "\"material_generation_cid\":\"" +
    material_cid +
    "\",\"store_authority_cid\":\"" +
    authority_cid +
    "\",\"effective_retention_policy_cid\":\"" +
    retention_cid +
    "\",\"row_count\":1,\"byte_count\":12,\"physical_sha256\":\"" +
    physical_digest +
    "\"}",
  )
  let facts : DeliveryPayloadFacts = {
    store_authority_cid: authority_cid,
    material_generation_cid: material_cid,
    logical_result_cid: logical_cid,
    result_schema_cid: schema_cid,
    ordering_evidence_cid: ordering_cid,
    codec_contract_cid: codec_cid,
    result_fields: ["answer"],
    result_schema_wire: schema_wire,
    row_count: 1L,
    byte_count: 12L,
    physical_sha256: physical_digest,
  }
  assert_eq(
    validate_delivery_payload_binding(
      index, manifest, attempt, binding, facts, 32768, 256, 16,
    ),
    Ok(()),
  )
  let wrong : DeliveryPayloadFacts = {
    ..facts,
    logical_result_cid: delivery_test_cid("f"),
  }
  assert_true(
    validate_delivery_payload_binding(
      index, manifest, attempt, binding, wrong, 32768, 256, 16,
    )
    is Err(DeliveryIssuanceReferenceMismatch("binding.physical_facts")),
  )
}

///|
test "Result availability separates guarantee expiry and deletion deadline" {
  let retention = delivery_test_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    delivery_test_cid("a") +
    "\",\"effective_data_policy_cid\":\"" +
    delivery_test_cid("b") +
    "\",\"available_until\":\"2026-09-18T02:00:00.000Z\"," +
    "\"delete_by\":\"2026-09-18T03:00:00.000Z\"," +
    "\"extension_ceiling_at\":\"2026-09-18T04:00:00.000Z\"," +
    "\"metadata_retention_policy_cid\":\"" +
    delivery_test_cid("c") +
    "\",\"metadata_delete_by\":\"2026-09-18T05:00:00.000Z" +
    "\",\"clock_contract_cid\":\"" +
    delivery_test_cid("d") +
    "\"}",
  )
  let matching_artifact = delivery_test_contract(
    "result_artifact",
    "{\"version\":\"actql-result-artifact/0.1\"," +
    "\"result_definition_cid\":\"" +
    delivery_test_cid("a") +
    "\",\"invocation_cid\":\"" +
    delivery_test_cid("b") +
    "\",\"logical_result_cid\":\"" +
    delivery_test_cid("c") +
    "\",\"result_schema_cid\":\"" +
    delivery_test_cid("d") +
    "\",\"ordering_evidence_cid\":\"" +
    delivery_test_cid("e") +
    "\",\"actual_row_count\":0,\"actual_completeness\":\"complete\"," +
    "\"effective_data_policy_cid\":\"" +
    delivery_test_cid("f") +
    "\",\"effective_retention_policy_cid\":\"" +
    publication_contract_identity(retention) +
    "\",\"provenance_evidence_cids\":[\"" +
    delivery_test_cid("2") +
    "\"]}",
  )
  let matching_manifest = delivery_test_contract(
    "result_manifest",
    "{\"version\":\"actql-result-manifest/0.1\"," +
    "\"run_definition_cid\":\"" +
    delivery_test_cid("3") +
    "\",\"invocation_cid\":\"" +
    delivery_test_cid("b") +
    "\",\"results\":{\"answer\":" +
    publication_contract_json(matching_artifact) +
    "}}",
  )
  assert_eq(
    result_read_availability(
      matching_manifest, "answer", retention, "2026-09-18T02:00:00.000Z",
    ),
    Ok("available"),
  )
  assert_eq(
    result_read_availability(
      matching_manifest, "answer", retention, "2026-09-18T02:00:00.001Z",
    ),
    Ok("retention_expired"),
  )
  assert_eq(
    result_read_availability(
      matching_manifest, "answer", retention, "2026-09-18T03:00:00.000Z",
    ),
    Ok("delete_due"),
  )
  assert_eq(
    result_metadata_retention_state(retention, "2026-09-18T04:59:59.999Z"),
    Ok("retained"),
  )
  assert_eq(
    result_metadata_retention_state(retention, "2026-09-18T05:00:00.000Z"),
    Ok("delete_due"),
  )
  assert_eq(
    result_retention_clock_contract_cid(retention),
    Ok(delivery_test_cid("d")),
  )
  assert_true(trusted_clock_not_before(None, "2026-09-18T03:00:00.000Z"))
  assert_true(
    trusted_clock_not_before(
      Some("2026-09-18T03:00:00.000Z"),
      "2026-09-18T03:00:00.000Z",
    ),
  )
  assert_false(
    trusted_clock_not_before(
      Some("2026-09-18T03:00:00.001Z"),
      "2026-09-18T03:00:00.000Z",
    ),
  )
  let extended = issue_result_retention_extension(
    retention, "2026-09-18T02:30:00.000Z", "2026-09-18T01:30:00.000Z", 32768, 256,
    16,
  ).unwrap()
  assert_eq(
    result_read_extended_availability(
      matching_manifest, "answer", retention, extended, "2026-09-18T02:15:00.000Z",
    ),
    Ok("available"),
  )
  assert_eq(
    result_read_extended_availability(
      matching_manifest, "answer", retention, extended, "2026-09-18T02:30:00.001Z",
    ),
    Ok("retention_expired"),
  )
  assert_true(
    issue_result_retention_extension(
      retention, "2026-09-18T03:00:00.001Z", "2026-09-18T01:30:00.000Z", 32768, 256,
      16,
    )
    is Err(DeliveryIssuanceReferenceMismatch("retention_extension")),
  )
  assert_true(
    issue_result_retention_extension(
      retention, "2026-09-18T01:59:59.999Z", "2026-09-18T01:30:00.000Z", 32768, 256,
      16,
    )
    is Err(DeliveryIssuanceReferenceMismatch("retention_extension")),
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
  let wrong_receipt = issue_result_delivery_receipt(
    index,
    manifest,
    grant,
    attempt,
    13,
    "e".repeat(64),
    32768,
    256,
    16,
  ).unwrap()
  assert_true(
    issue_delivery_record(
      attempt,
      Some(streaming),
      "succeeded",
      12,
      "exact",
      None,
      Some("d".repeat(64)),
      Some(wrong_receipt),
      None,
      "2026-09-18T01:00:01.000Z",
      [],
      32768,
      256,
      16,
    )
    is Err(DeliveryIssuanceReferenceMismatch("delivery_receipt")),
  )
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
  let (index, manifest, artifact) = delivery_test_root()
  let grant = issue_manifest_read_grant(
    index,
    manifest,
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
  assert_true(grant is Ok(_))
  guard grant is Ok(grant) else { fail("expected Manifest grant") }
  assert_true(manifest_read_grant_allows_bytes(grant, 4096))
  assert_false(manifest_read_grant_allows_bytes(grant, 4097))
  assert_true(manifest_read_grant_valid_at(grant, "2026-09-19T00:00:00.000Z"))
  assert_false(manifest_read_grant_valid_at(grant, "2026-09-19T00:00:00.001Z"))
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
