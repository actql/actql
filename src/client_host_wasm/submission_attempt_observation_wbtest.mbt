///|
test "lookup admits the original supplied intent and refuses a foreign identity" {
  let wire = "{\"kind\":\"program\",\"input\":{},\"parameters\":null}"
  // Existing independent canonical identity vector.
  let identity = "sha256:5ad281d9145e26cfb0bf5b7b0fa37c11cb2b065687350ae53a36f714bca0fe44"
  let original = admit_submission_lookup_intent(wire, identity).unwrap()
  assert_eq(@host.client_submitted_intent_cid(original), identity)
  assert_eq(
    admit_submission_lookup_intent(wire, "sha256:" + "d".repeat(64)),
    Err(-31),
  )
  assert_eq(admit_submission_lookup_intent("{}", identity), Err(-31))
  // A saved-only observation is not silently narrowed to fresh append's
  // 65536-byte profile. Unicode and decomposed text remain original DATA.
  let large = "{\"kind\":\"program\",\"input\":{},\"parameters\":{\"n\":\"" +
    "😀e\u{0301}".repeat(20000) +
    "\"}}"
  let retained = @host.prepare_client_submitted_intent(large, 1048576, 100, 10).unwrap()
  let observed = admit_submission_lookup_intent(
    large,
    @host.client_submitted_intent_cid(retained),
  ).unwrap()
  assert_eq(
    @host.client_submitted_intent_wire(observed),
    @host.client_submitted_intent_wire(retained),
  )
}

///|
test "lookup projects Common missing action without manufacturing retained history" {
  let identity = "sha256:5ad281d9145e26cfb0bf5b7b0fa37c11cb2b065687350ae53a36f714bca0fe44"
  let original = admit_submission_lookup_intent(
    "{\"kind\":\"program\",\"input\":{},\"parameters\":null}", identity,
  ).unwrap()
  let bytes = submission_lookup_wire(None, expected=Some(original)).unwrap()
  let source = @source.parse_json_bytes_preserving(bytes, {
    max_input_bytes: 4096,
    max_nodes: 32,
    max_depth: 4,
  }).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 32,
    max_depth: 4,
    max_string_bytes: 1024,
    max_total_string_bytes: 4096,
  }).unwrap()
  let object = @decode.closed_object(cursor, [
    "kind", "observation", "expectedIntentCid",
  ]).unwrap()
  assert_eq(required_text(object, "kind"), Some("missing"))
  assert_eq(required_text(object, "observation"), Some("missing"))
  assert_eq(required_text(object, "expectedIntentCid"), Some(identity))
}
