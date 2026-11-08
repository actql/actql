///|
test "lookup captured event and adoption retain the closed existing schemas" {
  let cid = "sha256:" + "a".repeat(64)
  let event_body = "{\"version\":\"actql-lookup-attempt-event/0.1\",\"barrier_cid\":\"" +
    cid +
    "\",\"batch_plan_cid\":\"" +
    cid +
    "\",\"call_slot_cid\":\"" +
    cid +
    "\",\"network_attempt\":1,\"previous_event_cid\":null,\"recorded_at\":\"2026-10-26T00:00:00.001Z\",\"outcome\":\"captured\",\"raw_response_artifact_cid\":\"" +
    cid +
    "\",\"runtime_error_cid\":null,\"failure_code\":null,\"issuer_id\":\"component\",\"authority_scope_cid\":\"" +
    cid +
    "\"}"
  let event = seal_publication_contract(
    "native_file_lookup_attempt_event", event_body, 8192, 100, 8,
  ).unwrap()
  assert_true(
    admit_publication_contract(
      "native_file_lookup_attempt_event",
      event.wire + " ",
      8192,
      100,
      8,
    )
    is Err(InvalidWire),
  )
  assert_true(
    seal_publication_contract(
      "native_file_lookup_attempt_event",
      event_body.replace(
        old="\"raw_response_artifact_cid\":\"" + cid + "\"",
        new="\"raw_response_artifact_cid\":null",
      ),
      8192,
      100,
      8,
    )
    is Err(_),
  )
  assert_true(
    seal_publication_contract(
      "native_file_lookup_attempt_event",
      event_body.replace(
        old="\"runtime_error_cid\":null",
        new="\"runtime_error_cid\":\"" + cid + "\"",
      ),
      8192,
      100,
      8,
    )
    is Err(_),
  )
  let adoption_body = "{\"version\":\"actql-lookup-page-adoption/0.1\",\"barrier_cid\":\"" +
    cid +
    "\",\"batch_plan_cid\":\"" +
    cid +
    "\",\"call_slot_cid\":\"" +
    cid +
    "\",\"activation_cid\":\"" +
    cid +
    "\",\"network_attempt\":1,\"capture_event_cid\":\"" +
    event.identity +
    "\",\"raw_response_artifact_cid\":\"" +
    cid +
    "\",\"response_schema_cid\":\"" +
    cid +
    "\",\"page_value_cid\":\"" +
    cid +
    "\",\"previous_adoption_cid\":null,\"terminal\":true,\"next_token\":null,\"recorded_at\":\"2026-10-26T00:00:00.001Z\",\"issuer_id\":\"component\",\"authority_scope_cid\":\"" +
    cid +
    "\"}"
  let adoption = seal_publication_contract(
    "native_file_lookup_adoption", adoption_body, 8192, 100, 8,
  ).unwrap()
  assert_eq(
    contract_string(adoption, "capture_event_cid"),
    Some(event.identity),
  )
  assert_true(
    admit_publication_contract(
      "native_file_lookup_adoption",
      adoption.wire + " ",
      8192,
      100,
      8,
    )
    is Err(InvalidWire),
  )
  assert_true(
    seal_publication_contract(
      "native_file_lookup_adoption",
      adoption_body.replace(
        old="\"network_attempt\":1",
        new="\"network_attempt\":0",
      ),
      8192,
      100,
      8,
    )
    is Err(_),
  )
}
