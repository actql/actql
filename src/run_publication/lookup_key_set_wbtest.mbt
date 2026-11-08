///|
fn lookup_key_test_body(tuples : String) -> String {
  "{\"key_roles\":[{\"request_role\":\"n\",\"value_contract\":{\"nullable\":false,\"type\":\"number\"}}],\"request_schema_cid\":\"sha256:" + "a".repeat(64) +
  "\",\"source_view_contract_cid\":\"sha256:" + "b".repeat(64) +
  "\",\"tuples\":" + tuples + ",\"version\":\"actql-lookup-key-set/0.1\"}"
}

///|
test "lookup key set derives numeric typed order and one identity across enumeration and duplicates" {
  let contract = @contract.primitive(@contract.NumberType, nullable=false)
  let two = @admitted.checked_number_value(2.0, contract).unwrap()
  let ten = @admitted.checked_number_value(10.0, contract).unwrap()
  for tuples in [[[ten], [two], [two]], [[two], [ten]]] {
    let keys = issue_lookup_request_key_set(
      "sha256:" + "b".repeat(64), "sha256:" + "a".repeat(64),
      [("n", contract)], tuples, 10000, 1000, 30,
    ).unwrap()
    // Independent SHA256 of the authored canonical preimage above, not a
    // runtime-generated expected identity or an execution/authority fixture.
    assert_eq(keys.identity, "sha256:8d392a85bd03bccd7e4859429fcc85e261d011c839e7406995ace51da0fccfc8")
    assert_true(keys.wire.contains("\"tuples\":[[2],[10]]"))
    assert_eq(admit_publication_contract("request_key_set", keys.wire, 10000, 1000, 30).unwrap().identity, keys.identity)
  }
}

///|
test "incoming key set refuses semantic duplicates lexical numeric order NULL and wrong arity" {
  for tuples in ["[[10],[2]]", "[[2],[2]]", "[[null]]", "[[2,10]]", "[[\"2\"]]"] {
    // A new matching self hash is not proof of typed order or tuple meaning.
    assert_true(seal_publication_contract("request_key_set", lookup_key_test_body(tuples), 10000, 1000, 30) is Err(_))
  }
  let valid = seal_publication_contract("request_key_set", lookup_key_test_body("[[2],[10]]"), 10000, 1000, 30).unwrap()
  assert_true(admit_publication_contract("request_key_set", " " + valid.wire, 10000, 1000, 30) is Err(InvalidWire))
  let contract = @contract.primitive(@contract.NumberType, nullable=false)
  assert_true(issue_lookup_request_key_set(
    "sha256:" + "b".repeat(64), "sha256:" + "a".repeat(64),
    [("z", contract), ("a", contract)], [], 10000, 1000, 30,
  ) is Err(KeySetRole(1, "a")))
  assert_true(issue_lookup_request_key_set(
    "sha256:" + "b".repeat(64), "sha256:" + "a".repeat(64),
    [("n", contract)], [], 1, 1000, 30,
  ) is Err(_))
}

///|
test "registered decimal and reference key vector admits original identities without issuing references" {
  // Exact independent spec/lookup-key-encoding-vector.json body and CID.
  let wire = "{\"key_roles\":[{\"request_role\":\"amount\",\"value_contract\":{\"nullable\":false,\"precision\":6,\"scale\":2,\"type\":\"decimal\"}},{\"request_role\":\"artifact\",\"value_contract\":{\"nullable\":false,\"type\":\"content_ref\"}},{\"request_role\":\"resource\",\"value_contract\":{\"nullable\":false,\"resource_kind\":\"files\",\"type\":\"resource_ref\"}}],\"request_schema_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"self_cid\":\"sha256:6169a0954828906a188a182921d010102502919b3af22089f9e38ec0383eb3df\",\"source_view_contract_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"tuples\":[[\"2.00\",\"sha256:6a3061840640f9359bdfee29c33e46f12594a5afa8293c6e1f9bcbb0883be3ed\",\"sha256:1ad7f20416a2a833f1d70f428a41485dde611a260807a6ec72ad1589e3159043\"],[\"10.00\",\"sha256:6a3061840640f9359bdfee29c33e46f12594a5afa8293c6e1f9bcbb0883be3ed\",\"sha256:1ad7f20416a2a833f1d70f428a41485dde611a260807a6ec72ad1589e3159043\"]],\"version\":\"actql-lookup-key-set/0.1\"}"
  let keys = admit_publication_contract("request_key_set", wire, 16384, 2000, 32).unwrap()
  assert_eq(keys.identity, "sha256:6169a0954828906a188a182921d010102502919b3af22089f9e38ec0383eb3df")
  assert_false(keys.wire.contains("$actql_ref"))
  assert_false(keys.wire.contains("issuer_evidence"))
  let body = admit_publication_effect_dependency_body("request_key_set", wire, 16384, 2000, 32).unwrap()
  assert_eq(body.node.references.map(reference => reference.kind), ["source_view_contract", "request_schema"])
  assert_eq(validate_captured_effect_dependency_bodies([body], [body], 0, {
    max_entries: 10, max_total_bytes: 16384, max_depth: 8, max_references: 20,
  }), Err(MissingDependency))
}

///|
test "key set empty extent still requires typed role schema and rejects non-key composite roles" {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let empty = issue_lookup_request_key_set(
    "sha256:" + "b".repeat(64), "sha256:" + "a".repeat(64),
    [("n", number)], [], 10000, 1000, 30,
  ).unwrap()
  assert_true(empty.wire.contains("\"tuples\":[]"))
  // The pinned toolchain's generic String comparison is length-first.
  // The protocol instead requires UTF-16 role order: resource before version.
  let mixed_lengths = issue_lookup_request_key_set(
    "sha256:" + "b".repeat(64), "sha256:" + "a".repeat(64),
    [("resource", number), ("version", number)], [], 10000, 1000, 30,
  ).unwrap()
  assert_true(admit_publication_contract(
    "request_key_set", mixed_lengths.wire, 10000, 1000, 30,
  ) is Ok(_))
  assert_true(seal_publication_contract("request_key_set",
    lookup_key_test_body("[]").replace(old="\"type\":\"number\"", new="\"type\":\"json\""),
    10000, 1000, 30,
  ) is Err(_))
}
