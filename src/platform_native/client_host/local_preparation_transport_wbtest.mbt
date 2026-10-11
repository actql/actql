///|
// Independent private preimage fixture, not a grant or a physical Host. The
// real crypto key comes only from authenticated original epoch custody.
test "Native preparation raw key uses the original adoption and Store with value-preserving private bytes" {
  let original = local_preparation_raw_key_preimage(
    "sha256:" + "1".repeat(64),
    "[\"namespace-e\u0301\r\n\",\"authority\",\"7\",\"8\"]",
  ).unwrap()
  assert_eq(
    @utf8.decode(original),
    "{\"adoption_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"domain\":\"actql-native-local-preparation-raw-key/0.1\",\"store_binding\":\"[\\\"namespace-é\\r\\n\\\",\\\"authority\\\",\\\"7\\\",\\\"8\\\"]\"}",
  )
  for
    (adoption, store) in [
      (
        "sha256:" + "2".repeat(64),
        "[\"namespace-e\u0301\r\n\",\"authority\",\"7\",\"8\"]",
      ),
      (
        "sha256:" + "1".repeat(64),
        "[\"namespace-é\r\n\",\"authority\",\"7\",\"8\"]",
      ),
      (
        "sha256:" + "1".repeat(64),
        "[\"namespace-e\u0301\n\",\"authority\",\"7\",\"8\"]",
      ),
      (
        "sha256:" + "1".repeat(64),
        "[\"namespace-e\u0301\r\n\",\"authority\",\"7\",\"9\"]",
      ),
    ] {
    assert_true(
      local_preparation_raw_key_preimage(adoption, store).unwrap() != original,
    )
  }
}

///|
// Exercise the shared original reader under the actual journal transaction.
// The fixture does not fabricate a live Work or an operational grant ACK.
test "Native raw grant custody reader preserves the original and refuses a changed reference" {
  let (host, _, mutation) = local_grant_storage_fixture(
    "raw-host-original-reader",
  )
  let original = local_preparation_storage_original(
    host, mutation, "explicit-raw-read",
  )
  local_grant_test_store(host, original)
  let crypto = epoch_test_crypto()
  let before = host.journal.retained(original.request).unwrap().unwrap().revision
  let original_packet = local_grant_original_packet(original).unwrap()
  for _ in 0..<3 {
    let saved = host.journal
      .transaction(() => {
        host.lookup_local_grant_original_locked(crypto, original)
      })
      .unwrap()
      .unwrap()
    assert_eq(local_grant_original_packet(saved).unwrap(), original_packet)
  }
  for
    reference in [
      { ..original, intent: @utf8.encode(@utf8.decode(original.intent) + " "), },
      { ..original, issuer_selection_cid: "sha256:" + "9".repeat(64), },
      { ..original, operation_cid: "sha256:" + "8".repeat(64), },
    ] {
    assert_true(
      host.journal.transaction(() => {
        host.lookup_local_grant_original_locked(crypto, reference)
      })
      is Err(ChangedIntent),
    )
  }
  assert_eq(
    host.journal.retained(original.request).unwrap().unwrap().revision,
    before,
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().body,
    b"1",
  )
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    65536L,
  )
  host.close().unwrap()
}

///|
test "Native raw grant custody reader cannot recreate a lost original reservation" {
  let (host, _, mutation) = local_grant_storage_fixture(
    "raw-host-lost-reservation",
  )
  let original = local_preparation_storage_original(
    host, mutation, "explicit-raw-read",
  )
  local_grant_test_store(host, original)
  host.database
  .release_capacity(
    "client_local_grant_originals",
    @host.client_request_scope_cid(original.request),
    65536L,
    1L,
  )
  .unwrap()
  |> ignore
  for _ in 0..<2 {
    assert_true(
      host.journal.transaction(() => {
        host.lookup_local_grant_original_locked(epoch_test_crypto(), original)
      })
      is Err(CustodyLost),
    )
    assert_eq(
      host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
      0L,
    )
    assert_eq(
      host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_objects,
      0L,
    )
    assert_eq(
      host.database.read("client_local_grant_custody", "issued").unwrap().body,
      b"1",
    )
  }
  host.close().unwrap()
}
