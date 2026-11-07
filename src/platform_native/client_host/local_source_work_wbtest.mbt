///|
fn local_source_authority_fixture(
  name : String,
  submit : Bool,
  read : Bool,
) -> NativeLocalHostConnection {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  let entries : Array[String] = []
  // Account wire entries must ascend by entry_id: source-read before submit.
  if read {
    entries.push(
      (
        #|{"entry_id":"source-read","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["connector://crm/main/r#v"]},"operation":{"any_of":["read"]},"exclusions":[]}
      ),
    )
  }
  if submit {
    entries.push(
      (
        #|{"entry_id":"submit","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["submit"]},"exclusions":[]}
      ),
    )
  }
  let body = @utf8.encode(
    "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[" +
    entries.join(",") +
    "]}",
  )
  let account = name + ".account.json"
  let writer = root.create_writer(name + ".stage", 4096L).unwrap()
  writer.append(body).unwrap()
  writer.seal(account).unwrap() |> ignore
  begin_native_local_host_adoption(
    path,
    name + ".host",
    path,
    account,
    "operator",
    epoch_test_crypto(),
  )
  .unwrap()
  .open_journal(
    local_journal_test_library(),
    epoch_test_crypto(),
    100.0,
    8,
    8388608L,
  )
  .unwrap()
}

///|
test "Native Local Source work requires independent submit and Source read permissions" {
  let crypto = epoch_test_crypto()
  // Expected outcomes are independent of the account Owner's returned decision.
  for
    (submit, read, expected) in [
      (false, false, false),
      (true, false, false),
      (false, true, false),
      (true, true, true),
    ] {
    let host = local_source_authority_fixture(
      "local-source-authority-" + submit.to_string() + "-" + read.to_string(),
      submit,
      read,
    )
    let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
    assert_eq(
      native_local_source_authorized(
        host, crypto, "operator", "cli", scope, "connector://crm/main/r#v",
      ),
      expected,
    )
    host.close().unwrap()
  }
}

///|
test "Native Local Source work refuses foreign caller scope Source and closed Host" {
  let host = local_source_authority_fixture("local-source-foreign", true, true)
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  assert_true(
    native_local_source_authorized(
      host, crypto, "operator", "cli", scope, "connector://crm/main/r#v",
    ),
  )
  for
    (principal, connection, checked_scope, source) in [
      ("other", "cli", scope, "connector://crm/main/r#v"),
      ("operator", "other", scope, "connector://crm/main/r#v"),
      ("operator", "cli", "altered-scope", "connector://crm/main/r#v"),
      ("operator", "cli", scope, "connector://crm/main/other#v"),
      (
        "other",
        "cli",
        host.authority_scope_cid("other", "cli", crypto).unwrap(),
        "connector://crm/main/r#v",
      ),
      (
        "operator",
        "other",
        host.authority_scope_cid("operator", "other", crypto).unwrap(),
        "connector://crm/main/r#v",
      ),
    ] {
    assert_false(
      native_local_source_authorized(
        host, crypto, principal, connection, checked_scope, source,
      ),
    )
  }
  host.close().unwrap()
  assert_false(
    native_local_source_authorized(
      host, crypto, "operator", "cli", scope, "connector://crm/main/r#v",
    ),
  )
}

///|
test "Native Local Source work rechecks original adoption custody after an earlier allow" {
  let host = local_source_authority_fixture(
    "local-source-lost-custody", true, true,
  )
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  assert_true(
    native_local_source_authorized(
      host, crypto, "operator", "cli", scope, "connector://crm/main/r#v",
    ),
  )
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
  assert_false(
    native_local_source_authorized(
      host, crypto, "operator", "cli", scope, "connector://crm/main/r#v",
    ),
  )
  assert_true(host.check_binding() is Err(CustodyLost))
  assert_true(
    host.database.read("client_local_adoption", "adoption")
    is Err(@sqlite.NotFound),
  )
  host.close().unwrap()
}
