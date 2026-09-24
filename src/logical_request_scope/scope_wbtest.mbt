///|
test "logical request scope uses the independent 0.1 preimage" {
  let authority = "sha256:" + "a".repeat(64)
  let scope = prepare_logical_request_scope(authority, "request-1", 256).unwrap()
  assert_eq(logical_request_scope_authority(scope), authority)
  assert_eq(logical_request_scope_caller_id(scope), "request-1")
  assert_eq(
    logical_request_scope_cid(scope),
    "sha256:caf2d10a1c26dfe7d79caf9a0d51645d5b29ad6c73fb2c6e036a3c2b04bf02c3",
  )
}

///|
test "logical request scope rejects noncanonical and control caller IDs" {
  let authority = "sha256:" + "a".repeat(64)
  assert_true(
    prepare_logical_request_scope(authority, "e\u{0301}", 256)
    is Err(InvalidCallerRequest),
  )
  assert_true(
    prepare_logical_request_scope(authority, "request\n1", 256)
    is Err(InvalidCallerRequest),
  )
  assert_true(
    prepare_logical_request_scope(authority, "request\u{007f}1", 256)
    is Err(InvalidCallerRequest),
  )
  assert_true(
    prepare_logical_request_scope(authority, "request\u{0085}1", 256)
    is Err(InvalidCallerRequest),
  )
  assert_true(
    prepare_logical_request_scope(authority, "x".repeat(257), 256)
    is Err(InvalidCallerRequest),
  )
  assert_true(
    prepare_logical_request_scope(authority, "x".repeat(256), 256) is Ok(_),
  )
  assert_true(
    prepare_logical_request_scope(authority, "é".repeat(128), 256) is Ok(_),
  )
  assert_true(
    prepare_logical_request_scope(authority, "é".repeat(129), 256)
    is Err(InvalidCallerRequest),
  )
  assert_true(
    prepare_logical_request_scope(authority, "x", 257) is Err(InvalidLimits),
  )
  assert_true(
    prepare_logical_request_scope("sha256:wrong", "x", 256)
    is Err(InvalidAuthorityScope),
  )
}
