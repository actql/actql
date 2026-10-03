///|
test "two Source custody cells preserve the original identity and cannot collide" {
  // This address-only test constructs no execution or read authority. The
  // expected digests are independent SHA-256 vectors over authored preimages.
  let definition : PublicationContract = {
    name: "run_definition",
    identity_field: "run_definition_cid",
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
  for slot in [-1, 2] {
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
