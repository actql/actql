///|
test "private ciphertext construction follows exact AEAD envelope geometry without funding a quota" {
  // Independent fixed ASCII envelope (version, nonce16, tag24, empty cipher)
  // is128 bytes. RFC4648 groups three plaintext bytes into four cipher chars.
  for
    (plain, expected) in [
      (1, 132),
      (2, 132),
      (3, 132),
      (4, 136),
      (1048576, 1398232),
    ] {
    let quote = private_evidence_custody_construction(plain).unwrap()
    assert_eq(quote.envelope_bytes, expected)
    assert_true(quote.retained.owned_wire_bytes >= expected.to_int64() + 32L)
    assert_true(quote.workspace.owned_wire_bytes >= plain.to_int64())
  }
  assert_true(private_evidence_custody_construction(0) is None)
  assert_true(private_evidence_custody_construction(-1) is None)
  assert_true(private_evidence_custody_construction(1048577) is None)
  assert_eq(
    private_evidence_custody_wire_construction("日").unwrap().envelope_bytes,
    132,
  )
  assert_eq(
    private_evidence_custody_wire_construction("日日").unwrap().envelope_bytes,
    136,
  )
}
