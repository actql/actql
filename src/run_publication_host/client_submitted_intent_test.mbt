///|
test "submitted intent preserves source values and data keys before checking" {
  let original = "{\"kind\":\"aql\",\"input\":{\"text\":\"SELECT 'e\u{0301}\\r\\n'\",\"format\":\"aql-text\"},\"parameters\":{\"e\u{0301}\":\"line\\r\\n\",\"é\":\"line\\n\"}}"
  let admitted = prepare_client_submitted_intent(original, 4096, 128, 16).unwrap()
  assert_eq(client_submitted_intent_wire(admitted),
    "{\"input\":{\"format\":\"aql-text\",\"text\":\"SELECT 'e\u{0301}\\r\\n'\"},\"kind\":\"aql\",\"parameters\":{\"e\u{0301}\":\"line\\r\\n\",\"é\":\"line\\n\"}}")
  let composed = prepare_client_submitted_intent(
    original.replace(old="SELECT 'e\u{0301}", new="SELECT 'é"), 4096, 128, 16,
  ).unwrap()
  assert_true(client_submitted_intent_cid(admitted) != client_submitted_intent_cid(composed))
  let newline = prepare_client_submitted_intent(
    original.replace(old="line\\r\\n", new="line\\n"), 4096, 128, 16,
  ).unwrap()
  assert_true(client_submitted_intent_cid(admitted) != client_submitted_intent_cid(newline))
}

///|
test "submitted intent distinguishes storage admission limits from malformed envelopes" {
  let original = "{\"kind\":\"program\",\"input\":{},\"parameters\":null}"
  assert_true(prepare_client_submitted_intent(original, 8, 128, 16) is Err(Limit))
  assert_true(prepare_client_submitted_intent(original, 4096, 1, 16) is Err(Limit))
  assert_true(prepare_client_submitted_intent(original, 4096, 128, 1) is Err(Limit))
  assert_true(prepare_client_submitted_intent(original, 0, 128, 16) is Err(InvalidLimits))
  for malformed in [
    "null",
    "{\"kind\":\"program\",\"input\":{}}",
    "{\"kind\":\"other\",\"input\":{},\"parameters\":null}",
    "{\"kind\":\"program\",\"input\":{},\"parameters\":[],\"extra\":1}",
  ] {
    assert_true(prepare_client_submitted_intent(malformed, 4096, 128, 16) is Err(InvalidEnvelope))
  }
}

///|
test "submitted intent identity uses an independent versioned preimage" {
  let original = "{\"kind\":\"program\",\"input\":{},\"parameters\":null}"
  let admitted = prepare_client_submitted_intent(original, 4096, 128, 16).unwrap()
  // Independently hashed canonical preimage, not a product-generated fixture.
  assert_eq(client_submitted_intent_cid(admitted),
    "sha256:5ad281d9145e26cfb0bf5b7b0fa37c11cb2b065687350ae53a36f714bca0fe44")
}

///|
test "submitted intent transitions preserve the acceptance boundary" {
  for next in ["preparing", "held", "ready", "preparation_failed"] {
    assert_true(client_submitted_intent_transition("preparing", next))
  }
  for before in ["preparing", "held", "ready", "preparation_failed"] {
    assert_false(client_submitted_intent_transition(before, "not_accepted"))
  }
  for terminal in ["ready", "not_accepted", "preparation_failed"] {
    assert_true(client_submitted_intent_transition(terminal, terminal))
    assert_false(client_submitted_intent_transition(terminal, "preparing"))
    assert_false(client_submitted_intent_transition(terminal, "held"))
  }
  assert_false(client_submitted_intent_transition("unknown", "ready"))
}
