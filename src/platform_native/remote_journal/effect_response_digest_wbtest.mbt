///|
test "saved Effect response digest binds exact bytes without semantic interpretation" {
  let response : NativeEffectSavedResponse = {
    credential_use_cid: "not-an-authority",
    status_code: 503,
    body: b"abc",
  }
  assert_eq(
    response.body_digest(),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  let empty : NativeEffectSavedResponse = { ..response, body: b"", }
  assert_eq(
    empty.body_digest(),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  let changed : NativeEffectSavedResponse = { ..response, body: b"abc\r\n", }
  assert_true(changed.body_digest() != response.body_digest())
}
