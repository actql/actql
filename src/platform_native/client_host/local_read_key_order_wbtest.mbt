///|
test "Native read preimage preserves unequal literal key bytes and independent CID" {
  let body = local_read_preimage(epoch_test_crypto(), [
    (
      "account_configuration_cid",
      @host.ClientLocalReadEvidenceValue::Text("ctx"),
    ),
    ("adoption_cid", @host.ClientLocalReadEvidenceValue::Text("adoption")),
  ]).unwrap()
  // Independently computed UTF-8 SHA-256, not derived from the product.
  assert_eq(
    body.wire,
    "{\"account_configuration_cid\":\"ctx\",\"adoption_cid\":\"adoption\"}",
  )
  assert_eq(
    body.cid,
    "sha256:407392a85e946d47afdce28c156c231dc242bdbc44d648707323571ccc0da8ce",
  )
}

///|
test "Native read preimage refuses shortlex-only reversed duplicate and malformed keys" {
  let crypto = epoch_test_crypto()
  for
    fields in [
      [
        ("adoption_cid", @host.ClientLocalReadEvidenceValue::Text("adoption")),
        (
          "account_configuration_cid",
          @host.ClientLocalReadEvidenceValue::Text("ctx"),
        ),
      ],
      [
        ("b", @host.ClientLocalReadEvidenceValue::Text("x")),
        ("a", @host.ClientLocalReadEvidenceValue::Text("y")),
      ],
      [
        ("a", @host.ClientLocalReadEvidenceValue::Text("x")),
        ("a", @host.ClientLocalReadEvidenceValue::Text("y")),
      ],
      [
        (
          String::from_array([(0xd800).unsafe_to_char()]),
          @host.ClientLocalReadEvidenceValue::Text("x"),
        ),
      ],
    ] {
    assert_true(local_read_preimage(crypto, fields) is Err(Encoding))
  }
  assert_true(
    local_read_preimage(crypto, [
      ("a", @host.ClientLocalReadEvidenceValue::Text("x".repeat(16384))),
    ])
    is Err(CapacityExceeded),
  )
}
