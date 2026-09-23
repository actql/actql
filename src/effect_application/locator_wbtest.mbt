///|
test "logical item and apply keys match independent canonical vectors" {
  let scope = prepare_logical_request_scope(
    "sha256:" + "a".repeat(64),
    "request-1",
    32,
  ).unwrap()
  let preview = "sha256:" + "b".repeat(64)
  let member_preview = "sha256:" + "c".repeat(64)
  let locator = prepare_logical_item_locator(
    scope, "program-1", "node-1", "WriteOne", "{\"row\":\"record-1\"}", 64, 128,
    8, 3,
  ).unwrap()
  assert_eq(
    logical_item_locator_cid(locator),
    "sha256:520a95693be3ea215833d19ee217dee53afbc614c3a0accf594e80eed2a38ade",
  )
  let apply = prepare_effect_apply_key(
    scope, preview, "WriteOne", member_preview, 64,
  ).unwrap()
  assert_eq(
    effect_apply_key_cid(apply),
    "sha256:6991293dfeef8207f1bc472049ceabd4ffdf4b33afea9ca8d8bb9fb31bfcc961",
  )
  let changed_preview = prepare_effect_apply_key(
    scope, member_preview, "WriteOne", member_preview, 64,
  ).unwrap()
  assert_true(
    effect_apply_key_cid(changed_preview) != effect_apply_key_cid(apply),
  )
  let changed_item = prepare_logical_item_locator(
    scope, "program-1", "node-1", "WriteOne", "{\"row\":\"record-2\"}", 64, 128,
    8, 3,
  ).unwrap()
  assert_true(
    logical_item_locator_cid(changed_item) != logical_item_locator_cid(locator),
  )
}

///|
test "logical item refuses noncanonical and foreign identities" {
  let scope = prepare_logical_request_scope(
    "sha256:" + "a".repeat(64),
    "request-1",
    32,
  ).unwrap()
  assert_true(
    prepare_logical_item_locator(
      scope, "", "node-1", "WriteOne", "\"row-1\"", 64, 128, 8, 3,
    )
    is Err(InvalidUnitNamespace),
  )
  assert_true(
    prepare_logical_item_locator(
      scope, "program-1", "node-1", "", "\"row-1\"", 64, 128, 8, 3,
    )
    is Err(InvalidEffect),
  )
  assert_true(
    prepare_logical_item_locator(
      scope, "program-1", "node-1", "WriteOne", "{\"z\":1,\"a\":2}", 64, 128, 8,
      3,
    )
    is Err(InvalidItemCorrelation),
  )
  assert_true(
    prepare_effect_apply_key(
      scope,
      "sha256:" + "b".repeat(64),
      "WriteOne",
      "foreign",
      64,
    )
    is Err(InvalidMemberPreview),
  )
}
