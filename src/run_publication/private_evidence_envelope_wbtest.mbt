///|
test "private evidence retains exact nonce ciphertext and tag wire" {
  let encrypted = b"abcdefghijkl" + b"f" + b"0123456789ABCDEF"
  let wire = "{\"version\":\"actql-private-publication-evidence/0.1\",\"nonce\":\"YWJjZGVmZ2hpamts\",\"tag\":\"MDEyMzQ1Njc4OUFCQ0RFRg==\",\"ciphertext\":\"Zg==\"}"
  assert_eq(
    encode_private_evidence_envelope(encrypted),
    Some(@utf8.encode(wire)),
  )
  assert_eq(
    decode_private_evidence_envelope(@utf8.encode(wire)),
    Some(encrypted),
  )
  for invalid in ["Zh==", "Zg", ""] {
    assert_true(
      decode_private_evidence_envelope(
        @utf8.encode(wire.replace(old="Zg==", new=invalid)),
      )
      is None,
      msg=invalid,
    )
  }
}
