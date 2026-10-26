///|
fn raw_native_fixture(
  label : String,
) -> (Store, String, @sqlite.Library, @signature.Library, String)? {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(path) &&
    native_payload_fixture(label, 65536L)
    is Some((store, authority, sqlite, root)) else {
    if @env.get_env_var("ACTQL_REQUIRE_NATIVE_LOCAL_RAW_TESTS") == Some("1") {
      abort(
        "original raw tests require the actual isolated SQLite/crypto Store fixture",
      )
    }
    return None
  }
  Some((store, authority, sqlite, @signature.load_library(path).unwrap(), root))
}

///|
fn raw_native_custody(
  store : Store,
  authority : String,
  crypto : @signature.Library,
) -> LocalPreparationRawCustody {
  let (grant, original_use) = raw_test_credentials()
  let binding = local_preparation_raw_binding(
    grant, original_use, authority, 16L,
  ).unwrap()
  prepare_local_raw_custody(
    store,
    binding,
    crypto,
    Bytes::makei(32, i => i.to_byte()),
  ).unwrap()
}

///|
test "Native raw descriptor and original rejected response survive saved ACK failure and reopen" {
  guard raw_native_fixture("raw-ack-original")
    is Some((store, authority, sqlite, crypto, root)) else {
    return
  }
  let custody = raw_native_custody(store, authority, crypto)
  custody.reserve().unwrap()
  assert_eq(custody.reserved_bytes(), 5728L)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 5728L)
  assert_eq(store.capacity_usage().unwrap().reserved_objects, 2L)
  let descriptor = store.database
    .read("credential_raw_preparation", custody.private_custody.holding)
    .unwrap()
  store.allocation_failure.val = Some(step => {
    if step == "credential-raw-after-persist-readback" {
      Some(StateCollision)
    } else {
      None
    }
  })
  let body = @utf8.encode("e\u0301\r\n")
  assert_true(custody.persist(401, body) is Err(StateCollision))
  let saved = store.database
    .read("credential_raw_observation", custody.private_custody.holding)
    .unwrap()
  store.allocation_failure.val = None
  custody.persist(401, body).unwrap()
  assert_eq(
    store.database
    .read("credential_raw_observation", custody.private_custody.holding)
    .unwrap().body,
    saved.body,
  )
  assert_eq(
    store.database
    .read("credential_raw_preparation", custody.private_custody.holding)
    .unwrap().body,
    descriptor.body,
  )
  assert_eq(custody.confirm().unwrap().body, body)
  assert_eq(custody.confirm().unwrap().status, 401)
  store.close().unwrap() |> ignore
  let reopened = open_existing_store(
    sqlite, root, authority, 65536L, 8L, 65536L,
  ).unwrap()
  let (grant, original_use) = raw_test_credentials()
  let restored = reopened
    .restore_local_preparation_raw_observation(
      grant,
      original_use,
      crypto,
      Bytes::makei(32, i => i.to_byte()),
    )
    .unwrap()
  assert_eq(restored.confirm().unwrap().body, body)
  assert_eq(restored.confirm().unwrap().status, 401)
  assert_true(restored.persist(200, b"another response") is Err(StateCollision))
  assert_true(restored.retry_cleanup().unwrap())
  assert_true(!restored.retry_cleanup().unwrap())
  assert_eq(reopened.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(reopened.capacity_usage().unwrap().reserved_objects, 0L)
  reopened.close().unwrap() |> ignore
}

///|
test "Native raw insufficient capacity and missing original reservation cannot create or repair raw custody" {
  guard raw_native_fixture("raw-budget-original")
    is Some((store, authority, _, crypto, _)) else {
    return
  }
  store.database
  .reserve_capacity(
    "publication_payload", "another-original", 60000L, 1L, 65536L, 8L,
  )
  .unwrap()
  |> ignore
  let custody = raw_native_custody(store, authority, crypto)
  assert_true(custody.reserve() is Err(Database(@sqlite.CapacityExceeded)))
  assert_true(
    store.database.read(
      "credential_raw_preparation",
      custody.private_custody.holding,
    )
    is Err(@sqlite.NotFound),
  )
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 60000L)
  store.database
  .release_capacity("publication_payload", "another-original", 60000L, 1L)
  .unwrap()
  |> ignore
  custody.reserve().unwrap()
  store.database
  .release_capacity(
    "publication_payload",
    custody.private_custody.capacity_key,
    5728L,
    2L,
  )
  .unwrap()
  |> ignore
  assert_true(custody.persist(200, b"original") is Err(StateCollision))
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(
    store.database.read(
      "credential_raw_observation",
      custody.private_custody.holding,
    )
    is Err(@sqlite.NotFound),
  )
  // Missing reservation is not reconstructed. Cleanup retires the same
  // descriptor/body slot and confirms that no capacity remains to return.
  assert_true(!custody.retry_cleanup().unwrap())
  store.close().unwrap() |> ignore
}

///|
test "Native raw descriptor cleanup failure retains original capacity across reopen and forbids revival" {
  guard raw_native_fixture("raw-cleanup-original")
    is Some((store, authority, sqlite, crypto, root)) else {
    return
  }
  let custody = raw_native_custody(store, authority, crypto)
  custody.reserve().unwrap()
  custody.persist(200, b"not a Catalog").unwrap()
  store.allocation_failure.val = Some(step => {
    if step == "credential-raw-before-descriptor-cleanup" {
      Some(StateCollision)
    } else {
      None
    }
  })
  assert_true(custody.retry_cleanup() is Err(StateCollision))
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 5728L)
  assert_eq(store.capacity_usage().unwrap().reserved_objects, 2L)
  assert_true(custody.confirm() is Err(RecoveryRequired))
  store.allocation_failure.val = None
  store.close().unwrap() |> ignore
  let reopened = open_existing_store(
    sqlite, root, authority, 65536L, 8L, 65536L,
  ).unwrap()
  let (grant, original_use) = raw_test_credentials()
  let restored = reopened
    .restore_local_preparation_raw_observation(
      grant,
      original_use,
      crypto,
      Bytes::makei(32, i => i.to_byte()),
    )
    .unwrap()
  assert_true(restored.retry_cleanup().unwrap())
  assert_eq(reopened.capacity_usage().unwrap().reserved_bytes, 0L)
  let cleanup_only = reopened
    .restore_local_preparation_raw_observation(
      grant,
      original_use,
      crypto,
      Bytes::makei(32, i => i.to_byte()),
    )
    .unwrap()
  assert_true(cleanup_only.confirm() is Err(RecoveryRequired))
  assert_true(cleanup_only.reserve() is Err(RecoveryRequired))
  assert_true(!cleanup_only.retry_cleanup().unwrap())
  assert_eq(reopened.capacity_usage().unwrap().reserved_objects, 0L)
  reopened.close().unwrap() |> ignore
}

///|
test "Native raw holding keeps the independent original grant and use CID" {
  let binding = raw_test_binding(4096L)
  assert_eq(
    local_raw_preparation_holding(binding).unwrap(),
    "sha256:31b4f53329f31c997452b6f9dda6c382bcd05656e83b0fad97dfdf252ecf4ff2",
  )
  assert_eq(
    local_raw_preparation_holding(raw_test_binding(16L)).unwrap(),
    local_raw_preparation_holding(binding).unwrap(),
  )
}
