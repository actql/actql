///|
let local_issuer_fixture_wire : String =
  #|{"version":"actql-config/0.1","native":{"credential_issuer":{"enabled":true,"issuer_authority":"credential-authority-a","principal":"operator","connection":"cli","max_uses":2,"expires_at":"2099-01-01T00:00:00.000Z"}}}

///|
let local_issuer_fixture_account : Bytes = b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"issuer\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"credential/credential-authority-a\"]},\"operation\":{\"any_of\":[\"issue\"]},\"exclusions\":[]}]}"

///|
fn local_issuer_fixture(
  name : String,
  account_body? : Bytes = local_issuer_fixture_account,
  issuer_wire? : String = local_issuer_fixture_wire,
  state_parent? : String? = None,
) -> (NativeLocalHostConnection, String) {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(root).unwrap()
  let file = name + ".issuer.json"
  let writer = parent.create_writer(name + ".issuer.stage", 8192L).unwrap()
  writer.append(@utf8.encode(issuer_wire)).unwrap()
  writer.seal(file).unwrap() |> ignore
  (policy_host_fixture(name, files=[file], account_body~, state_parent~), file)
}

///|
test "Native finite issuer selection preserves exact values and rejects missing or excessive allowances" {
  let value = admit_native_local_credential_issuer_selection(
    local_issuer_fixture_wire.replace_all(
      old="\"issuer_authority\":\"credential-authority-a\"",
      new="\"issuer_authority\":\"e\\u0301\\r\\n\"",
    ),
  ).unwrap()
  assert_eq(value.issuer_authority, "e\u0301\r\n")
  assert_eq(value.max_uses, 2)
  assert_true(value.enabled)
  for replacement in ["0", "1025", "2.5", "null"] {
    assert_true(
      admit_native_local_credential_issuer_selection(
        local_issuer_fixture_wire.replace_all(
          old="\"max_uses\":2",
          new="\"max_uses\":" + replacement,
        ),
      )
      is Err(_),
    )
  }
  for
    (old, replacement) in [
      ("\"max_uses\":2,", ""),
      ("\"enabled\":true", "\"enabled\":null"),
      (
        "\"issuer_authority\":\"credential-authority-a\"", "\"issuer_authority\":\"\"",
      ),
      ("2099-01-01T00:00:00.000Z", "2099-02-30T00:00:00.000Z"),
      ("\"max_uses\":2", "\"max_uses\":2,\"automatic\":true"),
    ] {
    assert_true(
      admit_native_local_credential_issuer_selection(
        local_issuer_fixture_wire.replace_all(old~, new=replacement),
      )
      is Err(InvalidOriginal),
    )
  }
  assert_true(
    admit_native_local_credential_issuer_selection(
      local_issuer_fixture_wire.replace_all(
        old="\"enabled\":true",
        new="\"enabled\":false",
      ),
    )
    is Ok(_),
  )
}

///|
// These are physical Native boundary definitions, not executed acceptance.
// Syntax admission or an acquired issuer binding is deliberately not a grant.
test "Native adopted issuer acquisition uses the Account Owner and original intent without Run mutation" {
  let (host, file) = local_issuer_fixture("local-issuer-original")
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "issuer-original",
    "original-run",
    scope~,
  )
  let before = host.journal
    .bind_run(request, prepared, compiled, definition, true)
    .unwrap()
  let original_adoption = host.adoption_cid
  let intent = "sha256:" + "a".repeat(64)
  let binding = host
    .acquire_credential_issuer(crypto, file, "operator", "cli", intent)
    .unwrap()
  assert_eq(binding.file.body, @utf8.encode(local_issuer_fixture_wire))
  assert_eq(binding.operation_cid, intent)
  assert_eq(binding.selection.issuer_authority, "credential-authority-a")
  assert_eq(binding.selection.max_uses, 2)
  assert_eq(
    @authorization.dispatch_authorization_tuple(binding.authorization),
    {
      principal: "operator",
      connection: "cli",
      resource: "credential/credential-authority-a",
      operation: "issue",
    },
  )
  assert_true(binding.require_current(host, intent) is Ok(_))
  assert_true(
    binding.require_current(host, "sha256:" + "b".repeat(64))
    is Err(SelectionMismatch),
  )
  let expiry = @values.timestamp_epoch_milliseconds("2099-01-01T00:00:00.000Z").unwrap()
  assert_true(binding.require_current_at(host, intent, expiry - 1L) is Ok(_))
  assert_true(binding.require_current_at(host, intent, expiry) is Err(Expired))
  assert_true(
    binding.require_current_at(host, intent, -1L) is Err(InvalidClock),
  )
  guard host.journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("issuer acquisition lost the original Run")
  }
  assert_eq(after.revision, before.revision)
  assert_false(after.dispatch_reserved)
  assert_false(after.physical_start_claimed)
  assert_true(after.checkpoint is None)
  assert_eq(host.adoption_cid, original_adoption)
  host.close().unwrap()
  assert_true(binding.require_current(host, intent) is Err(Adoption(Closed)))
}

///|
test "Native issuer acquisition never substitutes submit or read permission for issuance" {
  let (host, file) = local_issuer_fixture(
    "local-issuer-denied",
    account_body=policy_account_original,
  )
  assert_true(
    host.authorize({
      principal: "operator",
      connection: "cli",
      resource: "run",
      operation: "submit",
    })
    is Ok(@authorization.Allow(_)),
  )
  assert_true(
    host.acquire_credential_issuer(
      epoch_test_crypto(),
      file,
      "operator",
      "cli",
      "sha256:" + "a".repeat(64),
    )
    is Err(Authorization(@authorization.Denied)),
  )
  host.close().unwrap()
}

///|
test "Native issuer binding refuses foreign selection principal connection intent and Host" {
  let (host, file) = local_issuer_fixture("local-issuer-foreign")
  let crypto = epoch_test_crypto()
  let intent = "sha256:" + "a".repeat(64)
  for
    (selected, principal, connection) in [
      ("unselected.issuer.json", "operator", "cli"),
      (file, "other", "cli"),
      (file, "operator", "other"),
    ] {
    assert_true(
      host.acquire_credential_issuer(
        crypto, selected, principal, connection, intent,
      )
      is Err(SelectionMismatch),
    )
  }
  assert_true(
    host.acquire_credential_issuer(crypto, file, "operator", "cli", "altered")
    is Err(Authorization(@authorization.InvalidSubject)),
  )
  let binding = host
    .acquire_credential_issuer(crypto, file, "operator", "cli", intent)
    .unwrap()
  // Both live Hosts retain their own exclusive Adoption namespace.
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(path).unwrap()
  let state_name = "local-issuer-other-parent"
  parent.create_directory(state_name).unwrap() |> ignore
  parent.close().unwrap()
  let (foreign, _) = local_issuer_fixture(
    "local-issuer-other-host",
    state_parent=Some(path + "/" + state_name),
  )
  assert_true(
    binding.require_current(foreign, intent) is Err(SelectionMismatch),
  )
  foreign.close().unwrap()
  host.close().unwrap()
}

///|
test "Native issuer binding refuses identical file replacement and lost adoption without repair" {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(root).unwrap()
  let crypto = epoch_test_crypto()
  let intent = "sha256:" + "a".repeat(64)
  let (host, file) = local_issuer_fixture("local-issuer-replaced")
  let binding = host
    .acquire_credential_issuer(crypto, file, "operator", "cli", intent)
    .unwrap()
  let generation = parent.inspect_generation(file).unwrap().unwrap()
  parent.reclaim_generation(file, generation).unwrap()
  let writer = parent
    .create_writer("local-issuer-replacement.stage", 8192L)
    .unwrap()
  writer.append(@utf8.encode(local_issuer_fixture_wire)).unwrap()
  writer.seal(file).unwrap() |> ignore
  assert_true(binding.require_current(host, intent) is Err(Adoption(_)))
  host.close().unwrap()
  let (host, file) = local_issuer_fixture("local-issuer-lost-custody")
  let binding = host
    .acquire_credential_issuer(crypto, file, "operator", "cli", intent)
    .unwrap()
  let table = @utf8.encode("client_local_adoption")
  let key = @utf8.encode("adoption")
  assert_true(
    submitted_test_remove_record(
      host.database,
      table,
      table.length(),
      key,
      key.length(),
    ),
  )
  assert_true(
    binding.require_current(host, intent) is Err(Adoption(CustodyLost)),
  )
  assert_true(
    host.database.read("client_local_adoption", "adoption")
    is Err(@sqlite.NotFound),
  )
  host.close().unwrap()
}

///|
test "Native issuer acquisition refuses explicitly disabled or expired selection" {
  for
    (name, old, replacement, expired) in [
      ("local-issuer-disabled", "\"enabled\":true", "\"enabled\":false", false),
      (
        "local-issuer-expired", "2099-01-01T00:00:00.000Z", "2020-01-01T00:00:00.000Z",
        true,
      ),
    ] {
    let (host, file) = local_issuer_fixture(
      name,
      issuer_wire=local_issuer_fixture_wire.replace_all(old~, new=replacement),
    )
    let result = host.acquire_credential_issuer(
      epoch_test_crypto(),
      file,
      "operator",
      "cli",
      "sha256:" + "a".repeat(64),
    )
    if expired {
      assert_true(result is Err(Expired))
    } else {
      assert_true(result is Err(Disabled))
    }
    host.close().unwrap()
  }
}
