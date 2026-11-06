///|
// Storage-only setup. The issuer setting provides an existing selected-file
// original for codec/custody tests; it is not a live Salesforce installation,
// checked Work token, Provider read authorization or operational grant ACK.
fn preparation_target_storage_fixture(
  host : NativeLocalHostConnection,
  original : NativeLocalGrantOriginal,
) -> NativeLocalPreparationOriginalTarget {
  let file = host.session.settings.files
    .iter()
    .find_first(file => file.content_cid == original.issuer_selection_cid)
    .unwrap()
  {
    resource: "salesforce://org-a/Account",
    provider_file_name: file.name,
    provider_selection_cid: file.content_cid,
  }
}

///|
fn append_preparation_test_original(
  binding : NativeLocalCredentialIssuerBinding,
  original : NativeLocalGrantOriginal,
  current : () -> Result[Unit, NativeClientRunJournalIssue],
) -> Result[Unit, NativeClientRunJournalIssue] {
  binding.append_grant_original_locked(
    original,
    current,
    target=Some(preparation_target_storage_fixture(binding.host, original)),
  )
}

///|
test "Native target original shares grant append and refuses changed target or provider after ACK loss" {
  let (host, binding, mutation) = local_grant_storage_fixture(
    "target-original-repeat",
  )
  let original = local_preparation_storage_original(
    host, mutation, "observe-target-original",
  )
  let target = preparation_target_storage_fixture(host, original)
  let before = host.journal.retained(original.request).unwrap().unwrap().revision
  let key = local_grant_original_key(
    epoch_test_crypto(),
    original.request,
    original.operation_id,
  ).unwrap()
  host.journal
  .transaction(() => {
    binding.append_grant_original_locked(
      original,
      () => Ok(()),
      target=Some(target),
    )
  })
  .unwrap()
  // Discard the append acknowledgement and reconcile only the same originals.
  // This is a private storage boundary, not public process/transport loss.
  let saved_target = host.database
    .read("client_local_preparation_target_originals", key)
    .unwrap()
  let saved_grant = host.database
    .read("client_local_grant_originals", key)
    .unwrap()
  for _ in 0..<3 {
    host.journal
    .transaction(() => {
      binding.append_grant_original_locked(
        original,
        () => Ok(()),
        target=Some(target),
      )
    })
    .unwrap()
    assert_eq(
      host.journal
      .transaction(() => {
        host.lookup_preparation_target_original_locked(
          epoch_test_crypto(),
          original,
        )
      })
      .unwrap()
      .unwrap().resource,
      "salesforce://org-a/Account",
    )
    assert_eq(
      host.database
      .read("client_local_preparation_target_originals", key)
      .unwrap().body,
      saved_target.body,
    )
    assert_eq(
      host.database.read("client_local_grant_originals", key).unwrap().body,
      saved_grant.body,
    )
  }
  for
    changed in [
      { ..target, resource: "salesforce://org-a/Contact", },
      { ..target, provider_file_name: "foreign-provider.json", },
      { ..target, provider_selection_cid: "sha256:" + "9".repeat(64), },
    ] {
    assert_true(
      host.journal.transaction(() => {
        binding.append_grant_original_locked(
          original,
          () => Ok(()),
          target=Some(changed),
        )
      })
      is Err(ChangedIntent),
    )
  }
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().body,
    b"1",
  )
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    65536L,
  )
  assert_eq(
    host.journal.retained(original.request).unwrap().unwrap().revision,
    before,
  )
  host.close().unwrap()
}

///|
test "Native legacy target absence cannot be backfilled into an existing grant" {
  let (host, binding, mutation) = local_grant_storage_fixture(
    "target-legacy-missing",
  )
  let original = local_preparation_storage_original(
    host, mutation, "observe-legacy-original",
  )
  local_grant_test_store(host, original)
  let target = preparation_target_storage_fixture(host, original)
  let key = local_grant_original_key(
    epoch_test_crypto(),
    original.request,
    original.operation_id,
  ).unwrap()
  assert_true(
    host.journal.transaction(() => {
      host.lookup_preparation_target_original_locked(
        epoch_test_crypto(),
        original,
      )
    })
    is Ok(None),
  )
  for _ in 0..<2 {
    assert_true(
      host.journal.transaction(() => {
        binding.append_grant_original_locked(
          original,
          () => Ok(()),
          target=Some(target),
        )
      })
      is Err(CustodyLost),
    )
    assert_true(
      host.database.read("client_local_preparation_target_originals", key)
      is Err(@sqlite.NotFound),
    )
  }
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().body,
    b"1",
  )
  host.close().unwrap()
}

///|
test "Native target refusal rolls back the grant and original reservation together" {
  let (host, binding, mutation) = local_grant_storage_fixture(
    "target-current-denied",
  )
  let original = local_preparation_storage_original(
    host, mutation, "observe-refused-original",
  )
  let target = preparation_target_storage_fixture(host, original)
  let key = local_grant_original_key(
    epoch_test_crypto(),
    original.request,
    original.operation_id,
  ).unwrap()
  assert_true(
    host.journal.transaction(() => {
      binding.append_grant_original_locked(
        original,
        () => Err(AuthorizationDenied),
        target=Some(target),
      )
    })
    is Err(AuthorizationDenied),
  )
  for
    table in [
      "client_local_grant_originals", "client_local_preparation_target_originals",
    ] {
    assert_true(host.database.read(table, key) is Err(@sqlite.NotFound))
  }
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().body,
    b"0",
  )
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    0L,
  )
  host.close().unwrap()
}

///|
test "Native target authentication refuses altered body and foreign grant Run or operation" {
  let (host, binding, mutation) = local_grant_storage_fixture(
    "target-authenticated",
  )
  let original = local_preparation_storage_original(
    host, mutation, "observe-authenticated",
  )
  let target = preparation_target_storage_fixture(host, original)
  host.journal
  .transaction(() => {
    binding.append_grant_original_locked(
      original,
      () => Ok(()),
      target=Some(target),
    )
  })
  .unwrap()
  let key = local_grant_original_key(
    epoch_test_crypto(),
    original.request,
    original.operation_id,
  ).unwrap()
  let saved = host.database
    .read("client_local_preparation_target_originals", key)
    .unwrap()
  let row : @sqlite.NativeJournalEntry = {
    key,
    body: saved.body,
    revision: 0L,
  }
  let another = local_preparation_storage_original(
    host, mutation, "different-operation",
  )
  assert_true(
    read_local_preparation_target_record(host, another, row) is Err(CustodyLost),
  )
  assert_true(
    read_local_preparation_target_record(host, mutation, row)
    is Err(CustodyLost),
  )
  guard original.grant is PreparationGrant(saved_grant) else {
    fail("Preparation original required")
  }
  let other_grant = @credential.prepare_local_preparation_credential_grant(
    "credential-authority-a",
    @credential.local_preparation_credential_grant_scope(saved_grant),
    @values.timestamp_epoch_milliseconds("2098-01-01T00:00:00.000Z").unwrap(),
    2,
  ).unwrap()
  let different_grant = local_preparation_grant_original(
    epoch_test_crypto(),
    original.operation_id,
    original.request,
    original.issuer_selection_cid,
    other_grant,
  ).unwrap()
  assert_true(
    read_local_preparation_target_record(host, different_grant, row)
    is Err(CustodyLost),
  )
  let envelope = local_adoption_fields(saved.body, ["payload", "tag"]).unwrap()
  for
    changed in [
      { ..target, resource: "salesforce://org-a/Contact", },
      { ..target, provider_file_name: "foreign-provider.json", },
      { ..target, provider_selection_cid: "sha256:" + "9".repeat(64), },
    ] {
    let body = local_adoption_record([
      (
        "payload",
        @base64.encode(
          local_preparation_target_payload(original, changed).unwrap(),
        ),
      ),
      ("tag", envelope[1]),
    ]).unwrap()
    assert_true(
      read_local_preparation_target_record(host, original, { ..row, body, })
      is Err(CustodyLost),
    )
  }
  assert_true(
    read_local_preparation_target_record(host, original, {
      ..row,
      revision: 1L,
    })
    is Err(CustodyLost),
  )
  // Independently live Hosts need separate exclusive Adoption parents while
  // retaining the same Account source root and original fixture bodies.
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(path).unwrap()
  let state_name = "target-authenticated-other-parent"
  parent.create_directory(state_name).unwrap() |> ignore
  parent.close().unwrap()
  let (foreign, _, foreign_mutation) = local_grant_storage_fixture(
    "target-authenticated-other-run",
    state_parent=Some(path + "/" + state_name),
  )
  let foreign_original = local_preparation_storage_original(
    foreign, foreign_mutation, "observe-authenticated",
  )
  // Even the same signed body cannot become another original Run/adoption.
  assert_true(
    read_local_preparation_target_record(host, foreign_original, row)
    is Err(CustodyLost),
  )
  assert_true(
    read_local_preparation_target_record(foreign, original, row)
    is Err(CustodyLost),
  )
  foreign.close().unwrap()
  host.close().unwrap()
}

///|
test "Native target payload capacity refuses before grant append without increasing existing bucket" {
  let (host, binding, mutation) = local_grant_storage_fixture("target-bounded")
  let original = local_preparation_storage_original(
    host, mutation, "observe-bounded",
  )
  let target = {
    ..preparation_target_storage_fixture(host, original),
    resource: "r".repeat(3072),
  }
  assert_true(
    local_preparation_target_payload(original, target) is Err(CapacityExceeded),
  )
  assert_true(
    host.journal.transaction(() => {
      binding.append_grant_original_locked(
        original,
        () => Ok(()),
        target=Some(target),
      )
    })
    is Err(CapacityExceeded),
  )
  let key = local_grant_original_key(
    epoch_test_crypto(),
    original.request,
    original.operation_id,
  ).unwrap()
  for
    table in [
      "client_local_grant_originals", "client_local_preparation_target_originals",
    ] {
    assert_true(host.database.read(table, key) is Err(@sqlite.NotFound))
  }
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().body,
    b"0",
  )
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    0L,
  )
  host.close().unwrap()
}

///|
test "Native orphan target cannot become a grant original or repair its reservation" {
  let (host, mutation_binding, mutation) = local_grant_storage_fixture(
    "target-orphan",
  )
  let original = local_preparation_storage_original(
    host, mutation, "observe-orphan",
  )
  let target = preparation_target_storage_fixture(host, original)
  // The fixture's Mutation binding cannot reconcile a Preparation operation.
  // Bind that exact operation before exercising the orphan custody refusal.
  assert_true(
    mutation_binding.lookup_grant_original(original) is Err(ChangedIntent),
  )
  let binding = host
    .acquire_credential_issuer(
      epoch_test_crypto(),
      target.provider_file_name,
      "operator",
      "cli",
      original.operation_cid,
    )
    .unwrap()
  let key = local_grant_original_key(
    epoch_test_crypto(),
    original.request,
    original.operation_id,
  ).unwrap()
  let body = local_preparation_target_record(host, original, target).unwrap()
  host.database
  .insert("client_local_preparation_target_originals", key, body)
  .unwrap()
  |> ignore
  for _ in 0..<2 {
    assert_true(binding.lookup_grant_original(original) is Err(CustodyLost))
    assert_true(
      host.database.read("client_local_grant_originals", key)
      is Err(@sqlite.NotFound),
    )
  }
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    0L,
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().body,
    b"0",
  )
  host.close().unwrap()
}
