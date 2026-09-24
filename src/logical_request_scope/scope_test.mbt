///|
test "logical request scope matches an independent vector" {
  let authority = "sha256:" +
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  assert_eq(
    prepare_scope_cid(authority, "request-1", 256).unwrap(),
    "sha256:caf2d10a1c26dfe7d79caf9a0d51645d5b29ad6c73fb2c6e036a3c2b04bf02c3",
  )
  assert_true(
    prepare_scope_cid(authority, "e\u{0301}", 256) is Err(InvalidCallerRequest),
  )
  assert_true(
    prepare_scope_cid(authority, "line\r\nbreak", 256)
    is Err(InvalidCallerRequest),
  )
  assert_true(
    prepare_scope_cid("sha256:wrong", "request-1", 256)
    is Err(InvalidAuthorityScope),
  )
}
