///|
test "logical request and row dispatch identities match independent vectors" {
  let authority = "sha256:" + "a".repeat(64)
  let preview = "sha256:" + "b".repeat(64)
  let scope = prepare_logical_request_scope(authority, "request-1", 32).unwrap()
  assert_eq(
    logical_request_scope_cid(scope),
    "sha256:caf2d10a1c26dfe7d79caf9a0d51645d5b29ad6c73fb2c6e036a3c2b04bf02c3",
  )
  let key = prepare_effect_dispatch_key(scope, preview, "\"row-1\"", 32, 8, 3).unwrap()
  assert_eq(
    effect_dispatch_key_cid(key),
    "sha256:753d888dba41f4ce14250676698394baa4a7a84c73eb301b35a86fc406de1e72",
  )
  assert_eq(effect_dispatch_key_preview_cid(key), preview)
  assert_eq(
    effect_dispatch_key_scope_cid(key),
    logical_request_scope_cid(scope),
  )
  let changed = prepare_logical_request_scope(authority, "request-2", 32).unwrap()
  assert_true(
    logical_request_scope_cid(changed) != logical_request_scope_cid(scope),
  )
  let changed_key = prepare_effect_dispatch_key(
    changed, preview, "\"row-1\"", 32, 8, 3,
  ).unwrap()
  assert_true(
    effect_dispatch_key_cid(changed_key) != effect_dispatch_key_cid(key),
  )
  let content = "sha256:" + "c".repeat(64)
  let create_key = prepare_effect_dispatch_key(
    scope,
    preview,
    "{\"content_cid\":\"" + content + "\",\"occurrence\":0}",
    128,
    8,
    3,
  ).unwrap()
  assert_eq(
    effect_dispatch_key_cid(create_key),
    "sha256:5f2e083a488aee62c542153a93d5db1b50cfe4ca9caf36027f20a9e7be9b17be",
  )
}

///|
test "effect identity rejects foreign or noncanonical inputs" {
  let authority = "sha256:" + "a".repeat(64)
  let preview = "sha256:" + "b".repeat(64)
  assert_true(
    prepare_logical_request_scope("sha256:wrong", "request-1", 32)
    is Err(InvalidAuthorityScope),
  )
  assert_true(
    prepare_logical_request_scope(authority, "", 32)
    is Err(InvalidCallerRequest),
  )
  assert_true(
    prepare_logical_request_scope(authority, "request-1", 3)
    is Err(InvalidCallerRequest),
  )
  assert_true(
    prepare_logical_request_scope(authority, "e\u{0301}", 32)
    is Err(InvalidCallerRequest),
  )
  let scope = prepare_logical_request_scope(authority, "request-1", 32).unwrap()
  assert_true(
    prepare_effect_dispatch_key(scope, "sha256:wrong", "\"row-1\"", 32, 8, 3)
    is Err(InvalidPreview),
  )
  assert_true(
    prepare_effect_dispatch_key(scope, preview, "", 32, 8, 3)
    is Err(InvalidRowKey),
  )
  assert_true(
    prepare_effect_dispatch_key(scope, preview, "\"row-1\"", 0, 8, 3)
    is Err(InvalidLimits),
  )
  assert_true(
    prepare_effect_dispatch_key(scope, preview, "{\"b\":1,\"a\":2}", 32, 8, 3)
    is Err(InvalidRowKey),
  )
}
