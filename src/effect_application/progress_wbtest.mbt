///|
test "effect retry never turns possible dispatch into a new send" {
  let scope = prepare_logical_request_scope(
    "sha256:" + "a".repeat(64),
    "request-1",
    32,
  ).unwrap()
  let key = prepare_effect_dispatch_key(
    scope,
    "sha256:" + "b".repeat(64),
    "\"row-1\"",
    32,
    8,
    3,
  ).unwrap()
  let locator = prepare_logical_item_locator(
    scope, "program-1", "node-1", "WriteOne", "\"row-1\"", 64, 32, 8, 3,
  ).unwrap()
  let fingerprint = "sha256:" + "d".repeat(64)
  let request = "sha256:" + "c".repeat(64)
  assert_eq(
    effect_row_recovery_action(locator, fingerprint, key, request, None, false),
    PersistPrepared,
  )
  assert_eq(
    effect_row_recovery_action(locator, fingerprint, key, request, None, true),
    InvalidRecord,
  )
  for
    (state, action) in [
      (Prepared, ClaimPrepared),
      (Dispatching, ReconcilePossibleDispatch),
      (Applied, ReturnApplied),
      (Accepted, ReturnAccepted),
      (Failed, ReturnFailed),
      (Unknown, ReconcileUnknown),
    ] {
    let record : EffectRowRecord = {
      logical_item_locator_cid: logical_item_locator_cid(locator),
      intent_fingerprint_cid: fingerprint,
      dispatch_key_cid: effect_dispatch_key_cid(key),
      canonical_request_cid: request,
      state,
    }
    assert_eq(
      effect_row_recovery_action(
        locator,
        fingerprint,
        key,
        request,
        Some(record),
        false,
      ),
      action,
    )
  }
  for state in [Prepared, Dispatching] {
    let record : EffectRowRecord = {
      logical_item_locator_cid: logical_item_locator_cid(locator),
      intent_fingerprint_cid: fingerprint,
      dispatch_key_cid: effect_dispatch_key_cid(key),
      canonical_request_cid: request,
      state,
    }
    assert_eq(
      effect_row_recovery_action(
        locator,
        fingerprint,
        key,
        request,
        Some(record),
        true,
      ),
      JoinActive,
    )
  }
}

///|
test "effect recovery rejects changed canonical requests and preview keys" {
  let scope = prepare_logical_request_scope(
    "sha256:" + "a".repeat(64),
    "request-1",
    32,
  ).unwrap()
  let key = prepare_effect_dispatch_key(
    scope,
    "sha256:" + "b".repeat(64),
    "\"row-1\"",
    32,
    8,
    3,
  ).unwrap()
  let locator = prepare_logical_item_locator(
    scope, "program-1", "node-1", "WriteOne", "\"row-1\"", 64, 32, 8, 3,
  ).unwrap()
  let fingerprint = "sha256:" + "d".repeat(64)
  let record : EffectRowRecord = {
    logical_item_locator_cid: logical_item_locator_cid(locator),
    intent_fingerprint_cid: fingerprint,
    dispatch_key_cid: effect_dispatch_key_cid(key),
    canonical_request_cid: "sha256:" + "c".repeat(64),
    state: Applied,
  }
  assert_eq(
    effect_row_recovery_action(
      locator,
      fingerprint,
      key,
      "sha256:" + "d".repeat(64),
      Some(record),
      false,
    ),
    RequestConflict,
  )
  let other = prepare_effect_dispatch_key(
    scope,
    "sha256:" + "b".repeat(64),
    "\"row-2\"",
    32,
    8,
    3,
  ).unwrap()
  assert_eq(
    effect_row_recovery_action(
      locator,
      fingerprint,
      other,
      "sha256:" + "c".repeat(64),
      Some(record),
      false,
    ),
    RequestConflict,
  )
  assert_eq(
    effect_row_recovery_action(
      locator,
      "sha256:" + "e".repeat(64),
      key,
      "sha256:" + "c".repeat(64),
      Some(record),
      false,
    ),
    RequestConflict,
  )
}

///|
test "Store projections cannot disguise dispatching as absent or prepared" {
  let scope = prepare_logical_request_scope(
    "sha256:" + "a".repeat(64),
    "request-1",
    32,
  ).unwrap()
  let key = prepare_effect_dispatch_key(
    scope,
    "sha256:" + "b".repeat(64),
    "\"row-1\"",
    32,
    8,
    3,
  ).unwrap()
  let locator = prepare_logical_item_locator(
    scope, "program-1", "node-1", "WriteOne", "\"row-1\"", 64, 32, 8, 3,
  ).unwrap()
  let fingerprint = "sha256:" + "d".repeat(64)
  let request = "sha256:" + "c".repeat(64)
  let cid = effect_dispatch_key_cid(key)
  let locator_cid = logical_item_locator_cid(locator)
  assert_eq(
    effect_row_recovery_action_from_store(
      locator, fingerprint, key, request, "", "", "", "", -1, false,
    ),
    effect_row_action_code(PersistPrepared),
  )
  assert_eq(
    effect_row_recovery_action_from_store(
      locator, fingerprint, key, request, locator_cid, fingerprint, cid, request,
      1, false,
    ),
    effect_row_action_code(ReconcilePossibleDispatch),
  )
  assert_eq(
    effect_row_recovery_action_from_store(
      locator, fingerprint, key, request, locator_cid, fingerprint, cid, request,
      1, true,
    ),
    effect_row_action_code(JoinActive),
  )
  assert_eq(
    effect_row_recovery_action_from_store(
      locator, fingerprint, key, request, locator_cid, fingerprint, cid, request,
      -1, false,
    ),
    effect_row_action_code(InvalidRecord),
  )
  assert_eq(
    effect_row_recovery_action_from_store(
      locator, fingerprint, key, request, locator_cid, fingerprint, cid, request,
      6, false,
    ),
    effect_row_action_code(InvalidRecord),
  )
}
