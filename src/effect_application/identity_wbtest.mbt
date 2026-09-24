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
  assert_true(
    prepare_logical_request_scope(authority, "request\n1", 32)
    is Err(InvalidCallerRequest),
  )
  assert_true(
    prepare_logical_request_scope(authority, "request-1", 257)
    is Err(InvalidLimits),
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

///|
test "physical batch rows share one request member and Preview" {
  let authority = "sha256:" + "a".repeat(64)
  let preview = "sha256:" + "b".repeat(64)
  let other_preview = "sha256:" + "c".repeat(64)
  let scope = prepare_logical_request_scope(authority, "request-1", 32).unwrap()
  let other_scope = prepare_logical_request_scope(authority, "request-2", 32).unwrap()
  let first = prepare_logical_item_locator(
    scope, "program-1", "node-1", "WriteOne", "\"row-1\"", 64, 128, 8, 3,
  ).unwrap()
  let second = prepare_logical_item_locator(
    scope, "program-1", "node-1", "WriteOne", "\"row-2\"", 64, 128, 8, 3,
  ).unwrap()
  let first_key = prepare_effect_dispatch_key(
    scope, preview, "\"row-1\"", 32, 8, 3,
  ).unwrap()
  let second_key = prepare_effect_dispatch_key(
    scope, preview, "\"row-2\"", 32, 8, 3,
  ).unwrap()
  assert_true(
    effect_batch_rows_share_member(first, first_key, second, second_key),
  )
  let foreign_preview_key = prepare_effect_dispatch_key(
    scope, other_preview, "\"row-2\"", 32, 8, 3,
  ).unwrap()
  assert_false(
    effect_batch_rows_share_member(
      first, first_key, second, foreign_preview_key,
    ),
  )
  let foreign_member = prepare_logical_item_locator(
    scope, "program-1", "node-1", "WriteTwo", "\"row-2\"", 64, 128, 8, 3,
  ).unwrap()
  assert_false(
    effect_batch_rows_share_member(first, first_key, foreign_member, second_key),
  )
  let foreign_run = prepare_logical_item_locator(
    other_scope, "program-1", "node-1", "WriteOne", "\"row-2\"", 64, 128, 8, 3,
  ).unwrap()
  let foreign_key = prepare_effect_dispatch_key(
    other_scope, preview, "\"row-2\"", 32, 8, 3,
  ).unwrap()
  assert_false(
    effect_batch_rows_share_member(first, first_key, foreign_run, foreign_key),
  )
}
