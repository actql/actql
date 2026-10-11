///|
// Storage-only originals for current authorization tests. They do not claim
// operational grant issuance, a live Work, a Provider GET or a public restart.
let preparation_raw_read_account : Bytes = b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"read\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\",\"salesforce://org-a/Account\"]},\"operation\":{\"any_of\":[\"read\"]},\"exclusions\":[]}]}"

///|
fn preparation_raw_read_fixture(
  name : String,
  account_body : Bytes,
) -> (
  NativeLocalHostConnection,
  NativeLocalGrantOriginal,
  NativeLocalPreparationGrantReference,
) {
  let (host, file) = local_issuer_fixture(name, account_body~)
  let mutation = local_grant_test_original(host, file)
  let original = local_preparation_storage_original(
    host, mutation, "original-raw-read",
  )
  let reference = admit_native_local_preparation_grant_reference(
    epoch_test_crypto(),
    original.operation_cid,
    local_grant_original_packet(original).unwrap(),
  ).unwrap()
  (host, original, reference)
}

///|
fn retain_raw_read_storage_original(
  host : NativeLocalHostConnection,
  original : NativeLocalGrantOriginal,
) -> Unit {
  let target = preparation_target_storage_fixture(host, original)
  let key = local_grant_original_key(
    epoch_test_crypto(),
    original.request,
    original.operation_id,
  ).unwrap()
  host.journal
  .transaction(() => {
    let scope = @host.client_request_scope_cid(original.request)
    host.database
    .reserve_capacity_in_transaction(
      "client_local_grant_originals",
      scope,
      65536L,
      1L,
      host.journal.max_records.to_int64() * 65536L,
      host.journal.max_records.to_int64(),
    )
    .unwrap()
    |> ignore
    host.database
    .insert(
      "client_local_grant_originals",
      key,
      local_grant_original_packet(original).unwrap(),
    )
    .unwrap()
    |> ignore
    host.database
    .insert(
      "client_local_preparation_target_originals",
      key,
      local_preparation_target_record(host, original, target).unwrap(),
    )
    .unwrap()
    |> ignore
    let issued = host.database
      .read("client_local_grant_custody", "issued")
      .unwrap()
    host.database
    .compare_exchange(
      "client_local_grant_custody",
      "issued",
      issued.revision,
      @utf8.encode((issued.revision + 1L).to_string()),
    )
    .unwrap()
    |> ignore
    Ok(())
  })
  .unwrap()
}

///|
test "Native post closure target read distinguishes missing originals without issuer acquisition or repair" {
  let (host, original, reference) = preparation_raw_read_fixture(
    "raw-read-absence", preparation_raw_read_account,
  )
  let before = host.journal.retained(original.request).unwrap().unwrap().revision
  assert_true(
    host.preparation_raw_read_transaction(() => {
      host.original_preparation_raw_target_locked(
        epoch_test_crypto(),
        "operator",
        "cli",
        reference,
      )
    })
    is Err(UnavailableOriginalGrant),
  )
  local_grant_test_store(host, original)
  for _ in 0..<2 {
    assert_true(
      host.preparation_raw_read_transaction(() => {
        host.original_preparation_raw_target_locked(
          epoch_test_crypto(),
          "operator",
          "cli",
          reference,
        )
      })
      is Err(UnavailableOriginalTarget),
    )
  }
  let key = local_grant_original_key(
    epoch_test_crypto(),
    original.request,
    original.operation_id,
  ).unwrap()
  assert_true(
    host.database.read("client_local_preparation_target_originals", key)
    is Err(@sqlite.NotFound),
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    1L,
  )
  assert_eq(
    host.journal.retained(original.request).unwrap().unwrap().revision,
    before,
  )
  host.close().unwrap()
  // A separate fresh fixture retains both originals together. It never
  // backfills the legacy/missing target exercised above.
  let (host, original, reference) = preparation_raw_read_fixture(
    "raw-read-existing", preparation_raw_read_account,
  )
  retain_raw_read_storage_original(host, original)
  let before = host.journal.retained(original.request).unwrap().unwrap().revision
  for _ in 0..<2 {
    let saved = host
      .preparation_raw_read_transaction(() => {
        host.original_preparation_raw_target_locked(
          epoch_test_crypto(),
          "operator",
          "cli",
          reference,
        )
      })
      .unwrap()
    assert_eq(saved.resource, "salesforce://org-a/Account")
  }
  // Current read has its own authority; the old issuer's issue right is absent.
  assert_true(
    host.acquire_credential_issuer(
      epoch_test_crypto(),
      "raw-read-existing.issuer.json",
      "operator",
      "cli",
      original.operation_cid,
    )
    is Err(Authorization(@authorization.Denied)),
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    1L,
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
test "Native post closure target read independently refuses Run target and principal authorization" {
  for
    (name, account) in [
      (
        "raw-read-no-run",
        @utf8.encode(
          @utf8.decode(preparation_raw_read_account).replace_all(
            old="\"run\",",
            new="",
          ),
        ),
      ),
      (
        "raw-read-no-target",
        @utf8.encode(
          @utf8.decode(preparation_raw_read_account).replace_all(
            old=",\"salesforce://org-a/Account\"",
            new="",
          ),
        ),
      ),
    ] {
    let (host, original, reference) = preparation_raw_read_fixture(
      name, account,
    )
    retain_raw_read_storage_original(host, original)
    assert_true(
      host.preparation_raw_read_transaction(() => {
        host.original_preparation_raw_target_locked(
          epoch_test_crypto(),
          "operator",
          "cli",
          reference,
        )
      })
      is Err(Preparation(AuthorizationDenied)),
    )
    assert_eq(
      host.database.read("client_local_grant_custody", "issued").unwrap().revision,
      1L,
    )
    host.close().unwrap()
  }
  let (host, original, reference) = preparation_raw_read_fixture(
    "raw-read-principal", preparation_raw_read_account,
  )
  retain_raw_read_storage_original(host, original)
  for (principal, connection) in [("foreign", "cli"), ("operator", "foreign")] {
    assert_true(
      host.preparation_raw_read_transaction(() => {
        host.original_preparation_raw_target_locked(
          epoch_test_crypto(),
          principal,
          connection,
          reference,
        )
      })
      is Err(Preparation(ForeignInstallation)),
    )
  }
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    1L,
  )
  host.close().unwrap()
}
