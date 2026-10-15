///|
#borrow(database)
extern "C" fn catalog_readback_empty(database : @sqlite.Database) -> Bool = "actql_native_sqlite_test_result_storage_empty"

///|
test "bounded current catalog exact bytes and refusal preserve original custody" {
  // Required physical fixture: absent libraries/root must fail, never skip.
  let (store, generation, artifact, _, _) = native_bundle_fixture(
    "bounded-current",
  ).unwrap()
  let adopted = adopt_native_bundle(store, generation, artifact, "1")
  store.activate(adopted.runtime_bundle_cid).unwrap() |> ignore
  let binding = store
    .acquire_active_component(
      "sha256:5cbfccb321655cdc50146d4dad052ac646ba09180cefd34d8c48cd248166346f",
      "aarch64-apple-darwin", "runtime-process:bounded-current",
    )
    .unwrap()
  let original = store.database.read("runtime_bundle", "catalog").unwrap()
  let limit = original.body.length().to_int64()
  assert_true(limit > 0L && limit < store.max_record_bytes.to_int64())
  store.verify_active_component_binding_with_body_limit(binding, limit).unwrap()
  assert_true(
    store.verify_active_component_binding_with_body_limit(binding, limit - 1L)
    is Err(Database(@sqlite.BodyTooLarge)),
  )
  // The SQLite Owner refused before its body readback allocation/copy.
  assert_true(catalog_readback_empty(store.database))
  assert_true(
    store.verify_active_component_binding_with_body_limit(binding, 0L)
    is Err(Database(@sqlite.BodyTooLarge)),
  )
  assert_true(catalog_readback_empty(store.database))
  assert_true(
    store.verify_active_component_binding_with_body_limit(binding, -1L)
    is Err(Database(@sqlite.InvalidLimit)),
  )
  let after = store.database.read("runtime_bundle", "catalog").unwrap()
  assert_eq(after.revision, original.revision)
  assert_eq(after.body, original.body)
  store.verify_active_component_binding(binding).unwrap()
  store.verify_active_component_binding_with_body_limit(binding, limit).unwrap()
  assert_true(store.release("runtime-process:bounded-current").unwrap())
  assert_true(
    store.verify_active_component_binding_with_body_limit(binding, 1048576L)
    is Err(MissingBundle),
  )
  store.drain(adopted.runtime_bundle_cid).unwrap() |> ignore
  store.reclaim(adopted.runtime_bundle_cid).unwrap() |> ignore
  assert_true(store.close().unwrap())
}

///|
test "bounded current catalog keeps original component hold and retirement fences" {
  let (store, generation, artifact, _, _) = native_bundle_fixture(
    "bounded-current-fences",
  ).unwrap()
  // The fixture shares its owned Store root; retain a distinct signed identity
  // from the first case, including after its proper reclaim/tombstone.
  let adopted = adopt_native_bundle(store, generation, artifact, "2")
  store.activate(adopted.runtime_bundle_cid).unwrap() |> ignore
  let binding = store
    .acquire_active_component(
      "sha256:5cbfccb321655cdc50146d4dad052ac646ba09180cefd34d8c48cd248166346f",
      "aarch64-apple-darwin", "runtime-process:bounded-fences",
    )
    .unwrap()
  let original = store.database.read("runtime_bundle", "catalog").unwrap()
  let limit = original.body.length().to_int64()
  let foreign_component = {
    ..binding,
    component_cid: "sha256:" + "a".repeat(64),
  }
  assert_true(
    store.verify_active_component_binding_with_body_limit(
      foreign_component, limit,
    )
    is Err(ComponentMismatch),
  )
  let foreign_hold = { ..binding, process_hold_id: "runtime-process:foreign", }
  assert_true(
    store.verify_active_component_binding_with_body_limit(foreign_hold, limit)
    is Err(MissingBundle),
  )
  store.retiring = true
  assert_true(
    store.verify_active_component_binding_with_body_limit(binding, limit)
    is Err(CleanupPending),
  )
  store.retiring = false
  store.verify_active_component_binding_with_body_limit(binding, limit).unwrap()
  let after = store.database.read("runtime_bundle", "catalog").unwrap()
  assert_eq(after.revision, original.revision)
  assert_eq(after.body, original.body)
  assert_true(store.release("runtime-process:bounded-fences").unwrap())
  store.drain(adopted.runtime_bundle_cid).unwrap() |> ignore
  store.reclaim(adopted.runtime_bundle_cid).unwrap() |> ignore
  assert_true(store.close().unwrap())
  assert_true(
    store.verify_active_component_binding_with_body_limit(binding, limit)
    is Err(Closed),
  )
}
