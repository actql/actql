///|
// Fixed public-token bytes. The tag is deliberately only a shape fixture:
// accepting it below makes no claim of physical HMAC verification.
let original_submission_token : String =
  #|{"authenticator":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","authorityScopeCid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","epochNonce":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","expiresAt":2000,"notBefore":1000,"version":"actql-submission-epoch/0.1"}

///|
test "common original Submission reference has independently fixed identity and bytes" {
  let token = admit_client_submission_epoch_token(original_submission_token).unwrap()
  let value = prepare_client_submission_reference_record(
    token, "original-submit",
  ).unwrap()
  assert_eq(
    value.wire,
    "{\"epoch\":" +
    original_submission_token +
    ",\"nonce\":\"original-submit\"}",
  )
  // Independent Python hashlib over the normative epoch and identity
  // preimages, using literal fields; no product output was used as an oracle.
  assert_eq(
    submission_epoch_cid(token.body),
    "sha256:8b61656a31c8f035142978ef3288463226592da3c79fcda6fb3004bdf545b493",
  )
  assert_eq(
    value.request_id,
    "sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267",
  )
  assert_eq(
    admit_client_submission_reference_record(value.wire).unwrap().wire,
    value.wire,
  )
  assert_eq(
    submission_epoch_validity(token.body, 1000.0).unwrap(),
    @request_scope.Admissible,
  )
  assert_eq(
    submission_epoch_validity(token.body, 2000.0).unwrap(),
    @request_scope.Expired,
  )
}

///|
test "common original reference rejects unknown duplicate and malformed fields" {
  let wire = "{\"epoch\":" +
    original_submission_token +
    ",\"nonce\":\"original-submit\"}"
  for
    value in [
      "null",
      "{}",
      "{\"epoch\":null,\"nonce\":\"original-submit\"}",
      wire.replace(old="\"nonce\":", new="\"extra\":false,\"nonce\":"),
      wire.replace(old="\"nonce\":", new="\"nonce\":\"other\",\"nonce\":"),
      wire.replace(
        old="\"expiresAt\":2000",
        new="\"expiresAt\":2000,\"expiresAt\":2001",
      ),
      wire.replace(old="\"notBefore\":1000", new="\"notBefore\":null"),
      wire.replace(old="\"authenticator\":\"c", new="\"authenticator\":\"C"),
    ] {
    assert_true(admit_client_submission_reference_record(value) is Err(_))
  }
  assert_true(
    admit_client_submission_epoch_token(
      original_submission_token.replace(old="2000", new="1000"),
    )
    is Err(Identity(_)),
  )
}

///|
test "common original reference preserves typed Unicode nonce rules without normalization" {
  let token = admit_client_submission_epoch_token(original_submission_token).unwrap()
  for nonce in ["", "e\u{0301}", "x".repeat(257), "line\r\n"] {
    assert_true(
      prepare_client_submission_reference_record(token, nonce)
      is Err(InvalidReference),
    )
  }
  let value = prepare_client_submission_reference_record(token, "é").unwrap()
  assert_eq(
    value.request_id,
    "sha256:cec4cf592b778d8bc75895cbc312b58413b3fe78d08a3e5dcf0c6ffe4cb090fd",
  )
  assert_eq(
    value.wire,
    "{\"epoch\":" + original_submission_token + ",\"nonce\":\"é\"}",
  )
}

///|
test "common original reference canonicalizes token syntax but does not verify its tag" {
  let spaced = original_submission_token.replace(old="{", new="{ ")
  let token = admit_client_submission_epoch_token(spaced).unwrap()
  assert_eq(token.wire, spaced)
  let value = prepare_client_submission_reference_record(
    token, "original-submit",
  ).unwrap()
  assert_eq(value.epoch.wire, original_submission_token)
  let altered = admit_client_submission_epoch_token(
    original_submission_token.replace(old="cccc", new="dddd"),
  ).unwrap()
  let other = prepare_client_submission_reference_record(
    altered, "original-submit",
  ).unwrap()
  assert_eq(other.request_id, value.request_id)
  assert_false(other.wire == value.wire)
  assert_true(
    admit_client_submission_reference_record(" ".repeat(4097)) is Err(_),
  )
}
