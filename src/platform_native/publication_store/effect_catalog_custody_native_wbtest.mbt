///|
test "Native original Catalog close reopen and pending cleanup retain the same reservation" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(path) &&
    native_payload_fixture("original-catalog", 65536L)
    is Some((store, authority, library, root)) else {
    if @env.get_env_var("ACTQL_REQUIRE_NATIVE_EFFECT_CATALOG_TESTS") ==
      Some("1") {
      abort(
        "Native Catalog custody physical libraries and isolated Store are required",
      )
    }
    return
  }
  let crypto = @signature.load_library(path).unwrap()
  let key = Bytes::makei(32, i => i.to_byte())
  let binding = effect_catalog_test_binding()
  let evidence = effect_catalog_test_response()
  let limits = effect_catalog_test_limits()
  let custody = store
    .prepare_effect_catalog_custody(
      evidence.catalog,
      binding,
      "Account",
      evidence.use_cid,
      200,
      evidence.body,
      limits,
      crypto,
      key,
    )
    .unwrap()
  custody.persist().unwrap()
  let reservation = custody.reserved_bytes()
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, reservation)
  assert_eq(custody.confirm().unwrap().body, evidence.body)
  store.close().unwrap() |> ignore
  let reopened = open_store(library, root, authority, 65536L, 8L, 65536L).unwrap()
  let restored = reopened
    .restore_effect_catalog_custody(
      binding,
      "Account",
      evidence.use_cid,
      limits,
      crypto,
      key,
    )
    .unwrap()
  assert_eq(restored.confirm().unwrap().body, evidence.body)
  assert_true(
    reopened.restore_effect_catalog_custody(
      binding,
      "Account",
      "sha256:" + "f".repeat(64),
      limits,
      crypto,
      key,
    )
    is Err(StateCollision),
  )
  reopened.allocation_failure.val = Some(step => {
    if step == "effect-catalog-before-cleanup" {
      Some(StateCollision)
    } else {
      None
    }
  })
  assert_true(restored.retry_cleanup() is Err(StateCollision))
  assert_eq(restored.confirm().unwrap().body, evidence.body)
  assert_eq(reopened.capacity_usage().unwrap().reserved_bytes, reservation)
  reopened.allocation_failure.val = Some(step => {
    if step == "effect-catalog-before-capacity-release" {
      Some(StateCollision)
    } else {
      None
    }
  })
  assert_true(restored.retry_cleanup() is Err(StateCollision))
  assert_true(restored.confirm() is Err(RecoveryRequired))
  assert_eq(reopened.capacity_usage().unwrap().reserved_bytes, reservation)
  reopened.allocation_failure.val = None
  reopened.close().unwrap() |> ignore
  let final_store = open_store(library, root, authority, 65536L, 8L, 65536L).unwrap()
  let pending = final_store
    .restore_effect_catalog_custody(
      binding,
      "Account",
      evidence.use_cid,
      limits,
      crypto,
      key,
    )
    .unwrap()
  assert_true(pending.confirm() is Err(RecoveryRequired))
  assert_true(pending.persist() is Err(RecoveryRequired))
  assert_true(pending.retry_cleanup().unwrap())
  assert_false(pending.retry_cleanup().unwrap())
  assert_eq(final_store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(final_store.capacity_usage().unwrap().reserved_objects, 0L)
  final_store.close().unwrap() |> ignore
}
