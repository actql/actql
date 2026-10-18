///|
fn initial_payload_fixture() -> ClientLocalInitialSigningPayloadFields {
  // Deliberately only DATA. These labels are not valid adopted CIDs, a policy
  // or a physical key; no structural codec may turn them into authority.
  {
    adoption_cid: "adoption-original",
    initialization_intent_cid: "intent-original",
    issuer_authority: "issuer-original",
    key_file: "local-signing-key.pem",
    key_projection: "projection-original",
    policy_cid: "policy-original",
    policy_original: "{\"x\":\"a\\r\\nb\"}",
    public_key_cid: "key-original",
    public_key_original: "{\"raw\":\"original\"}",
    public_key_pem: "line1\r\nline2\n",
    purpose: "reviewer_proof",
    root_role: "store",
    version: "actql-native-local-installation-original/0.1",
  }
}

///|
fn initial_payload_fixture_wire() -> Bytes {
  // Independently authored original Native field order and String escaping.
  b"{\"adoption_cid\":\"adoption-original\",\"initialization_intent_cid\":\"intent-original\",\"issuer_authority\":\"issuer-original\",\"key_file\":\"local-signing-key.pem\",\"key_projection\":\"projection-original\",\"policy_cid\":\"policy-original\",\"policy_original\":\"{\\\"x\\\":\\\"a\\\\r\\\\nb\\\"}\",\"public_key_cid\":\"key-original\",\"public_key_original\":\"{\\\"raw\\\":\\\"original\\\"}\",\"public_key_pem\":\"line1\\r\\nline2\\n\",\"purpose\":\"reviewer_proof\",\"root_role\":\"store\",\"version\":\"actql-native-local-installation-original/0.1\"}"
}

///|
test "initial signing payload codec preserves exact Native field order and independent preimage" {
  let fields = initial_payload_fixture()
  let wire = initial_payload_fixture_wire()
  assert_eq(client_local_initial_signing_payload_body(fields).unwrap(), wire)
  assert_eq(read_client_local_initial_signing_payload(wire), Ok(fields))
  assert_eq(wire.length(), 484)
  assert_eq(
    @sha.hex(wire),
    "6c3bad8b1c7fcb90a67cb385c35455f0c79e817d09ee1b90b3ddced2430bfd44",
  )
}

///|
test "initial signing payload codec rejects missing unknown copied-key and noncanonical field vectors" {
  let wire = @utf8.decode(initial_payload_fixture_wire())
  for
    changed in [
      wire.replace(old="\"adoption_cid\":\"adoption-original\",", new=""),
      wire.replace(old="\"adoption_cid\"", new="\"adoption_original\""),
      wire.replace(
        old="{\"adoption_cid\"",
        new="{\"extra\":\"x\",\"adoption_cid\"",
      ),
      wire.replace(old="\"root_role\":\"store\"", new="\"root_role\":null"),
      wire.replace(old="\"root_role\":\"store\"", new="\"root_role\":1"),
      wire.replace(
        old="\"root_role\":\"store\"",
        new="\"root_role\": \"store\"",
      ),
      wire.replace(
        old="\"root_role\":\"store\"",
        new="\"root_role\":\"store\",\"root_role\":\"store\"",
      ),
      wire.replace(
        old="{\"adoption_cid\":\"adoption-original\",\"initialization_intent_cid\":\"intent-original\"",
        new="{\"initialization_intent_cid\":\"intent-original\",\"adoption_cid\":\"adoption-original\"",
      ),
    ] {
    assert_true(
      read_client_local_initial_signing_payload(@utf8.encode(changed))
      is Err(InvalidOriginal),
    )
  }
  // The pre-existing legacy host row is not a new initial-signing payload.
  assert_true(
    read_client_local_initial_signing_payload(b"{}") is Err(InvalidOriginal),
  )
}

///|
test "initial signing payload DATA keeps purpose policy and key claims for their actual owners" {
  let original = initial_payload_fixture()
  let changed = {
    ..original,
    purpose: "host_attestation",
    policy_cid: "foreign-policy-data",
    root_role: "source",
  }
  let wire = client_local_initial_signing_payload_body(changed).unwrap()
  assert_eq(read_client_local_initial_signing_payload(wire), Ok(changed))
  assert_not_eq(wire, initial_payload_fixture_wire())
  // A typed DATA result issues no nominal adopted/current material or grant.
  // Native/Node physical consumers must still reject these claimed originals.
}

///|
test "initial signing payload codec preserves text and the original shared record budgets" {
  let original = initial_payload_fixture()
  for pem in ["e\u{0301}\r\n\u{0000}", "é\r\n\u{0000}"] {
    let fields = { ..original, public_key_pem: pem, }
    assert_eq(
      read_client_local_initial_signing_payload(
        client_local_initial_signing_payload_body(fields).unwrap(),
      ),
      Ok(fields),
    )
  }
  assert_true(
    client_local_initial_signing_payload_body({
      ..original,
      public_key_pem: "x".repeat(8193),
    })
    is Err(Encoding),
  )
  assert_true(
    read_client_local_initial_signing_payload(Bytes::make(8193, 32))
    is Err(InvalidOriginal),
  )
}
