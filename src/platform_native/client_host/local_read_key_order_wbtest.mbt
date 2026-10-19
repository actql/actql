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

///|
test "Native material preimage binds receiver schema and ordering without changing stdout" {
  let crypto = epoch_test_crypto()
  let fields = [("a", @host.Text("original"))]
  let stdout = local_read_preimage(crypto, fields.copy()).unwrap()
  assert_eq(stdout.wire, "{\"a\":\"original\"}")
  let material : NativeLocalReadMaterialOriginal = {
    receiver_cid: "sha256:" + "a".repeat(64),
    ordering_evidence_cid: "sha256:" + "b".repeat(64),
    result_schema_cid: "sha256:" + "c".repeat(64),
  }
  let bound = local_read_preimage(
    crypto,
    fields.copy(),
    material=Some(material),
  ).unwrap()
  assert_eq(
    bound.wire,
    "{\"a\":\"original\",\"material_receiver_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"ordering_evidence_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"result_schema_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"}",
  )
  assert_eq(
    bound.cid,
    "sha256:02c2d86d36408fb70e7c339bb55dc9a8a92a9c195c3f7f34b6b61ab65c90e31b",
  )
  assert_false(bound.cid == stdout.cid)
  for
    changed in [
      { ..material, receiver_cid: "sha256:" + "d".repeat(64), },
      { ..material, result_schema_cid: "sha256:" + "d".repeat(64), },
      { ..material, ordering_evidence_cid: "sha256:" + "d".repeat(64), },
    ] {
    assert_false(
      local_read_preimage(crypto, fields.copy(), material=Some(changed)).unwrap().cid ==
      bound.cid,
    )
  }
}
