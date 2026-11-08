///|
test "lookup raw metadata preserves byte identity without granting Content or accepting noncanonical input" {
  let cid = "sha256:" + "a".repeat(64)
  let body = "{\"version\":\"actql-lookup-raw-response/0.1\",\"call_slot_cid\":\"" +
    cid +
    "\",\"network_attempt\":1,\"content_cid\":\"" +
    cid +
    "\",\"size_bytes\":3,\"media_type\":\"application/octet-stream\",\"captured_at\":\"2026-10-26T00:00:00.000Z\",\"effective_data_policy_cid\":\"" +
    cid +
    "\",\"effective_retention_policy_cid\":\"" +
    cid +
    "\",\"issuer_id\":\"component\",\"authority_scope_cid\":\"" +
    cid +
    "\"}"
  let raw = seal_publication_contract(
    "native_file_lookup_raw_response", body, 8192, 100, 8,
  ).unwrap()
  assert_eq(lookup_raw_response_content(raw), Some((cid, 3L)))
  assert_true(
    admit_publication_contract(
      "native_file_lookup_raw_response",
      publication_contract_json(raw) + " ",
      8192,
      100,
      8,
    )
    is Err(InvalidWire),
  )
  assert_true(
    seal_publication_contract(
      "native_file_lookup_raw_response",
      body.replace(old="\"size_bytes\":3", new="\"size_bytes\":-1"),
      8192,
      100,
      8,
    )
    is Err(_),
  )
  let other = result_definition_contract(
    prepare_result_definition(cid, "other-purpose").unwrap(),
  )
  assert_true(lookup_raw_response_content(other) is None)
}
