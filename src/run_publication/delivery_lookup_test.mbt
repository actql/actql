///|
test "delivery lookup matches each original scope field without a renewed grant" {
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
    index, manifest, grant, "answer", "json", "original-read", "2026-09-18T01:00:00.000Z",
    32768, 256, 16,
  ).unwrap()
  let scope : DeliveryAttemptLookupScope = {
    namespace_id: "namespace_id",
    authority_scope_cid: delivery_test_cid("4"),
    run_definition_cid: delivery_test_cid("3"),
    principal_id: "principal",
    purpose: "download",
    result_name: "answer",
    attempt_id: "original-read",
  }
  assert_true(
    delivery_attempt_lookup_matches_scope(attempt, grant, scope).unwrap(),
  )
  for
    changed in [
      { ..scope, namespace_id: "foreign", },
      { ..scope, authority_scope_cid: delivery_test_cid("f"), },
      { ..scope, run_definition_cid: delivery_test_cid("f"), },
      { ..scope, principal_id: "foreign", },
      { ..scope, purpose: "foreign", },
      { ..scope, result_name: "foreign", },
      { ..scope, attempt_id: "foreign", },
    ] {
    assert_false(
      delivery_attempt_lookup_matches_scope(attempt, grant, changed).unwrap(),
    )
  }
  assert_false(result_read_grant_valid_at(grant, "2026-09-20T00:00:00.000Z"))
  assert_true(
    delivery_attempt_lookup_matches_scope(attempt, grant, scope).unwrap(),
  )
  assert_eq(
    delivery_attempt_read_grant_cid(attempt),
    Ok(publication_contract_identity(grant)),
  )
}

///|
test "delivery lookup refuses foreign original grant and ungranted serialization" {
  let (index, manifest, artifact) = delivery_test_root()
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
    index, manifest, grant, "answer", "json", "original-read", "2026-09-18T01:00:00.000Z",
    32768, 256, 16,
  ).unwrap()
  let scope : DeliveryAttemptLookupScope = {
    namespace_id: "namespace_id",
    authority_scope_cid: delivery_test_cid("4"),
    run_definition_cid: delivery_test_cid("3"),
    principal_id: "principal",
    purpose: "download",
    result_name: "answer",
    attempt_id: "original-read",
  }
  let foreign = issue_result_read_grant(
    index,
    manifest,
    ["answer"],
    ["json"],
    "foreign",
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
  assert_true(
    delivery_attempt_lookup_matches_scope(attempt, foreign, scope)
    is Err(DeliveryIssuanceReferenceMismatch("delivery_attempt_grant")),
  )
  let invalid_format = delivery_test_contract(
    "delivery_attempt",
    "{\"version\":\"actql-delivery-attempt/0.1\",\"attempt_id\":\"original-read\",\"requested_at\":\"2026-09-18T01:00:00.000Z\",\"result_read_grant_cid\":\"" +
    publication_contract_identity(grant) +
    "\",\"run_definition_cid\":\"" +
    delivery_test_cid("3") +
    "\",\"result_manifest_cid\":\"" +
    publication_contract_identity(manifest) +
    "\",\"result_name\":\"answer\",\"result_artifact_cid\":\"" +
    publication_contract_identity(artifact) +
    "\",\"serialization_contract_cid\":\"sha256:61035606b44ad7f4dc24127825bcc46636f40ce5e06881cf9c97996dcb3bde84\"}",
  )
  assert_true(
    delivery_attempt_lookup_matches_scope(invalid_format, grant, scope)
    is Err(DeliveryIssuanceReferenceMismatch("grant.formats")),
  )
}
