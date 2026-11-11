///|
test "two Source custody cells preserve the original identity and cannot collide" {
  // This address-only test constructs no execution or read authority. The
  // expected digests are independent SHA-256 vectors over authored preimages.
  let definition : PublicationContract = {
    name: "run_definition",
    identity_field: "run_definition_cid",
    wire_usage: None,
    identity: "sha256:" + "a".repeat(64),
    wire: "{}",
    value: @json.from_json(Json::null(), 1, 1, 1),
  }
  let store = "sha256:" + "b".repeat(64)
  assert_eq(
    model_private_holding_cid(definition, store, "source_evidence", 0),
    Some(
      "sha256:a386f65280f169bef1d13e6243b39ee19dec1aa57086f8e59afda26debc72746",
    ),
  )
  assert_eq(
    model_private_holding_cid(definition, store, "source_evidence", 1),
    Some(
      "sha256:23a81ff008a8283fc96813faf3f55bcb1a72e97271f19d25eb42821df0cdc12b",
    ),
  )
  for slot in [-1, -2147483648] {
    assert_eq(
      model_private_holding_cid(definition, store, "source_evidence", slot),
      None,
    )
  }
  assert_eq(
    model_private_holding_cid(definition, "invalid", "source_evidence", 1),
    None,
  )
}

///|
test "Source custody addresses the original complete coordinate inventory without changing other role ranges" {
  // Independent hashes of authored canonical preimages, with the same dummy
  // Run/Store identities as the original zero/one vectors above. No execution
  // or Source permission follows from calculating a private Store address.
  let definition : PublicationContract = {
    name: "run_definition",
    identity_field: "run_definition_cid",
    wire_usage: None,
    identity: "sha256:" + "a".repeat(64),
    wire: "{}",
    value: @json.from_json(Json::null(), 1, 1, 1),
  }
  let store = "sha256:" + "b".repeat(64)
  let addresses = []
  for
    (slot, expected) in [
      (
        2, "sha256:fda14ac1c5dda716c8629f54fba220124fc9928a0dbc3779bdc7493ddec58177",
      ),
      (
        17, "sha256:d7ed84a0310edbd5ad82f3741d762062f7c66d0dcd3413380a523412e95d4c24",
      ),
      (
        2147483647, "sha256:969245530e75e083c4ea54164257451b7ac4872c2c056af07652841522ba21ba",
      ),
    ] {
    let address = model_private_holding_cid(
      definition, store, "source_evidence", slot,
    )
    assert_eq(address, Some(expected))
    assert_false(addresses.contains(address))
    addresses.push(address)
  }
  assert_eq(
    model_private_holding_cid(definition, store, "source_evidence", -1),
    None,
  )
  assert_eq(
    model_private_holding_cid(definition, store, "foreign_role", 2),
    None,
  )
  assert_eq(
    model_private_holding_cid(definition, store, "model_slot_capture", 128),
    None,
  )
  assert_eq(
    model_private_holding_cid(definition, store, "observation_set", 2),
    None,
  )
}

///|
test "scoped Model custody uses the canonical independent preimage" {
  let definition : PublicationContract = {
    name: "run_definition",
    identity_field: "run_definition_cid",
    wire_usage: None,
    identity: "sha256:" + "a".repeat(64),
    wire: "{}",
    value: @json.from_json(Json::null(), 1, 1, 1),
  }
  assert_eq(
    model_scoped_private_holding_cid(
      definition,
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
      "sha256:" + "d".repeat(64),
      "sha256:" + "e".repeat(64),
      1,
      "settled",
      "model_slot_capture",
    ),
    Some(
      "sha256:afe23c4e4233bf147ccacd7cb76ee89c1b5f7ec67ef2c851ea8eedc7a594f9a2",
    ),
  )
}

///|
test "raw Model custody has one original entered cell and no legacy address" {
  let definition : PublicationContract = {
    name: "run_definition",
    identity_field: "run_definition_cid",
    wire_usage: None,
    identity: "sha256:" + "a".repeat(64),
    wire: "{}",
    value: @json.from_json(Json::null(), 1, 1, 1),
  }
  let store = "sha256:" + "b".repeat(64)
  let scope = "sha256:" + "c".repeat(64)
  let slot = "sha256:" + "d".repeat(64)
  let attempt = "sha256:" + "e".repeat(64)
  // Authored canonical preimage hashed independently with Node SHA-256.
  // An address is not evidence of a saved object, permission or success.
  let expected = Some(
    "sha256:e88bde47a2c79876172258ccef1d3ffa32c681445466cfbc2e0ea3213e6d33a5",
  )
  assert_eq(
    model_scoped_private_holding_cid(
      definition, store, scope, slot, attempt, 1, "entered", "model_raw_response",
    ),
    expected,
  )
  for changed in ["sha256:" + "f".repeat(64), "invalid"] {
    assert_true(
      model_scoped_private_holding_cid(
        definition, store, scope, slot, changed, 1, "entered", "model_raw_response",
      ) !=
      expected,
    )
    assert_true(
      model_scoped_private_holding_cid(
        definition, store, changed, slot, attempt, 1, "entered", "model_raw_response",
      ) !=
      expected,
    )
    assert_true(
      model_scoped_private_holding_cid(
        definition, changed, scope, slot, attempt, 1, "entered", "model_raw_response",
      ) !=
      expected,
    )
  }
  assert_eq(
    model_scoped_private_holding_cid(
      definition, store, scope, slot, attempt, 1, "settled", "model_raw_response",
    ),
    None,
  )
  assert_eq(
    model_scoped_private_holding_cid(
      definition, store, scope, slot, attempt, 2, "entered", "model_raw_response",
    ),
    None,
  )
  assert_eq(
    model_private_holding_cid(definition, store, "model_raw_response", 0),
    None,
  )
}
