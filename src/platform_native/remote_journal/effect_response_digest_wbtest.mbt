///|
test "response metadata digest hashes original bytes without JSON interpretation" {
  assert_eq(
    effect_response_body_digest(b""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    effect_response_body_digest(b"abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_true(
    effect_response_body_digest(b"null\r\n") !=
    effect_response_body_digest(b"null\n"),
  )
}

///|
test "response record framing retains the independent original metadata vector" {
  let response : NativeEffectSavedResponse = {
    credential_use_cid: "sha256:" + "7".repeat(64),
    status_code: 409,
    body: b"abc",
  }
  let expected = @utf8.encode(
    "sha256:" +
    "7".repeat(64) +
    "\n409\nba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(effect_response_record_metadata(response, 3L), Some(expected))
  assert_eq(
    effect_response_record_fields(expected, b"abc", 3L),
    Some((response.credential_use_cid, 409)),
  )
  assert_true(effect_response_record_metadata(response, 2L) is None)
  assert_true(effect_response_record_fields(expected, b"abc", 2L) is None)
  assert_true(effect_response_record_fields(expected, b"abd", 3L) is None)
  assert_true(
    effect_response_record_fields(@utf8.encode("short"), b"abc", 3L) is None,
  )
}
