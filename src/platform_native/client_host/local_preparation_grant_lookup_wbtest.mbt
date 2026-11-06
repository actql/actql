///|
// Matching physical custody/reopen definitions, not executed public recovery.
// The existing fixture creates identity/storage only, never a live Work token.
let local_preparation_lookup_account : Bytes = b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"issuer\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"credential/credential-authority-a\"]},\"operation\":{\"any_of\":[\"issue\"]},\"exclusions\":[]},{\"entry_id\":\"original-run-read\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":[\"read\"]},\"exclusions\":[]}]}"

///|
test "Native preparation grant reference is exact bounded identity and not Resume" {
  let (host, _, mutation) = local_grant_storage_fixture("preparation-reference")
  let original = local_preparation_storage_original(
    host, mutation, "observe-explicit",
  )
  let crypto = epoch_test_crypto()
  let packet = local_grant_original_packet(original).unwrap()
  let reference = admit_native_local_preparation_grant_reference(
    crypto,
    original.operation_cid,
    packet,
  ).unwrap()
  assert_eq(reference.operation_cid(), original.operation_cid)
  assert_eq(local_grant_original_packet(reference.original).unwrap(), packet)
  assert_true(
    admit_native_local_preparation_grant_reference(
      crypto,
      mutation.operation_cid,
      local_grant_original_packet(mutation).unwrap(),
    )
    is Err(ChangedIntent),
  )
  let wire = @utf8.decode(packet) catch { _ => fail("fixture UTF-8") }
  for
    invalid in [
      @utf8.encode(wire + " "),
      @utf8.encode(
        wire.replace_all(old="observe-explicit", new="altered-operation"),
      ),
      @utf8.encode(
        wire.replace_all(old="observe-original", new="altered-attempt"),
      ),
      @utf8.encode(
        wire.replace_all(old="\"grant\":", new="\"automatic\":true,\"grant\":"),
      ),
      @utf8.encode(" ".repeat(49153)),
    ] {
    assert_true(
      admit_native_local_preparation_grant_reference(
        crypto,
        original.operation_cid,
        invalid,
      )
      is Err(_),
    )
  }
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    0L,
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    0L,
  )
  host.close().unwrap()
}

///|
test "Native preparation original lookup survives reopen without grant renewal or Run mutation" {
  let name = "preparation-lookup-reopen"
  let (host, _, mutation) = local_grant_storage_fixture(
    name,
    account_body=local_preparation_lookup_account,
  )
  let original = local_preparation_storage_original(
    host, mutation, "observe-explicit",
  )
  let crypto = epoch_test_crypto()
  let reference_wire = local_grant_original_packet(original).unwrap()
  let reference = admit_native_local_preparation_grant_reference(
    crypto,
    original.operation_cid,
    reference_wire,
  ).unwrap()
  let file = name + ".issuer.json"
  assert_true(
    host.lookup_preparation_grant_operation(
      crypto, file, "operator", "cli", reference,
    )
    is Ok(UnresolvedOriginal),
  )
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    0L,
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    0L,
  )
  local_grant_test_store(host, original)
  let before = host.journal.retained(original.request).unwrap().unwrap()
  host.close().unwrap()
  let host = policy_host_fixture(name, existing=true, files=[file])
  let restored = admit_native_local_preparation_grant_reference(
    crypto,
    original.operation_cid,
    reference_wire,
  ).unwrap()
  for _ in 0..<3 {
    assert_true(
      host.lookup_preparation_grant_operation(
        crypto, file, "operator", "cli", restored,
      )
      is Ok(RetainedOriginal),
    )
  }
  let after = host.journal.retained(original.request).unwrap().unwrap()
  assert_eq(after.revision, before.revision)
  assert_eq(after.physical_start_claimed, before.physical_start_claimed)
  assert_eq(after.dispatch_reserved, before.dispatch_reserved)
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    1L,
  )
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    65536L,
  )
  guard original.grant is PreparationGrant(grant) else {
    fail("fixture original Preparation grant")
  }
  let changed_grant = @credential.prepare_local_preparation_credential_grant(
    "credential-authority-a",
    {
      ..@credential.local_preparation_credential_grant_scope(grant),
      request_path: "/services/data/v65.0/sobjects/Account/other",
    },
    @values.timestamp_epoch_milliseconds("2099-01-01T00:00:00.000Z").unwrap(),
    2,
  ).unwrap()
  let changed = local_preparation_grant_original(
    crypto,
    original.operation_id,
    original.request,
    original.issuer_selection_cid,
    changed_grant,
  ).unwrap()
  let divergent = admit_native_local_preparation_grant_reference(
    crypto,
    changed.operation_cid,
    local_grant_original_packet(changed).unwrap(),
  ).unwrap()
  // A valid identity reader cannot make a changed grant the original operation.
  // The same user operation ID still addresses the immutable original row.
  assert_true(
    host.lookup_preparation_grant_operation(
      crypto, file, "operator", "cli", divergent,
    )
    is Err(Journal(ChangedIntent)),
  )
  let wrong_operation = local_preparation_storage_original(
    host, mutation, "other-operation",
  )
  let wrong = admit_native_local_preparation_grant_reference(
    crypto,
    wrong_operation.operation_cid,
    local_grant_original_packet(wrong_operation).unwrap(),
  ).unwrap()
  // An explicit different operation addresses its own absent row. It is still
  // unresolved, never permission to issue a replacement or consume a use.
  assert_true(
    host.lookup_preparation_grant_operation(
      crypto, file, "operator", "cli", wrong,
    )
    is Ok(UnresolvedOriginal),
  )
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    1L,
  )
  host.close().unwrap()
}

///|
test "Native preparation lookup requires independent current Run read and issuer authority" {
  let crypto = epoch_test_crypto()
  for
    (name, account, expected_read) in [
      ("preparation-lookup-no-read", local_issuer_fixture_account, false),
      ("preparation-lookup-no-issue", policy_account_original, true),
    ] {
    let (host, file) = local_issuer_fixture(name, account_body=account)
    let mutation = local_grant_test_original(host, file)
    let original = local_preparation_storage_original(
      host, mutation, "observe-explicit",
    )
    let reference = admit_native_local_preparation_grant_reference(
      crypto,
      original.operation_cid,
      local_grant_original_packet(original).unwrap(),
    ).unwrap()
    let outcome = host.lookup_preparation_grant_operation(
      crypto, file, "operator", "cli", reference,
    )
    if expected_read {
      assert_true(outcome is Err(Issuer(Authorization(@authorization.Denied))))
    } else {
      assert_true(outcome is Err(AuthorizationDenied))
    }
    assert_eq(
      host.database.read("client_local_grant_custody", "issued").unwrap().revision,
      0L,
    )
    assert_eq(
      host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
      0L,
    )
    host.close().unwrap()
  }
}

///|
test "Native preparation lookup refuses foreign references and lost original custody without repair" {
  let name = "preparation-lookup-custody"
  let (host, _, mutation) = local_grant_storage_fixture(
    name,
    account_body=local_preparation_lookup_account,
  )
  let crypto = epoch_test_crypto()
  let original = local_preparation_storage_original(
    host, mutation, "observe-explicit",
  )
  let reference = admit_native_local_preparation_grant_reference(
    crypto,
    original.operation_cid,
    local_grant_original_packet(original).unwrap(),
  ).unwrap()
  let file = name + ".issuer.json"
  for (principal, connection) in [("other", "cli"), ("operator", "other")] {
    assert_true(
      host.lookup_preparation_grant_operation(
        crypto, file, principal, connection, reference,
      )
      is Err(ForeignInstallation),
    )
  }
  // The foreign installation stays live beside the original and therefore
  // owns a separate exclusive Adoption parent, with the same Account source.
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(path).unwrap()
  let state_name = "preparation-lookup-other-parent"
  parent.create_directory(state_name).unwrap() |> ignore
  parent.close().unwrap()
  let (foreign, _) = local_issuer_fixture(
    "preparation-lookup-other-host",
    account_body=local_preparation_lookup_account,
    state_parent=Some(path + "/" + state_name),
  )
  assert_true(
    foreign.lookup_preparation_grant_operation(
      crypto, "preparation-lookup-other-host.issuer.json", "operator", "cli", reference,
    )
    is Err(ForeignInstallation),
  )
  foreign.close().unwrap()
  local_grant_test_store(host, original)
  let key = @utf8.encode(
    local_grant_original_key(crypto, original.request, original.operation_id).unwrap(),
  )
  let table = @utf8.encode("client_local_grant_originals")
  assert_true(
    submitted_test_remove_record(
      host.database,
      table,
      table.length(),
      key,
      key.length(),
    ),
  )
  for _ in 0..<2 {
    assert_true(
      host.lookup_preparation_grant_operation(
        crypto, file, "operator", "cli", reference,
      )
      is Err(Journal(CustodyLost)),
    )
  }
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    1L,
  )
  assert_eq(
    host.database.capacity_usage("client_local_grant_originals").unwrap().reserved_bytes,
    65536L,
  )
  host.close().unwrap()
}

///|
test "Native preparation reference matching does not accept another admitted submission request" {
  let (host, _, mutation) = local_grant_storage_fixture(
    "preparation-request-match",
  )
  let original = local_preparation_storage_original(
    host, mutation, "observe-original-match",
  )
  let reference = admit_native_local_preparation_grant_reference(
    epoch_test_crypto(),
    original.operation_cid,
    local_grant_original_packet(original).unwrap(),
  ).unwrap()
  assert_true(reference.matches_original_request(original.request))
  let (foreign, _, _, _) = journal_test_run(
    "different-submission",
    "original-run",
    scope=@host.client_request_authority_scope_cid(original.request),
  )
  assert_false(reference.matches_original_request(foreign))
  assert_eq(
    host.database.read("client_local_grant_custody", "issued").unwrap().revision,
    0L,
  )
  host.close().unwrap()
}
