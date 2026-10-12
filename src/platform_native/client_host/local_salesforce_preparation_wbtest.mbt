///|
let local_preparation_provider_wire : String =
  #|{"version":"actql-config/0.1","native":{"salesforce":{"connection_revision":"connection-original","connector_registration":"salesforce","connector_revision":"salesforce/0.1","environment":"local","namespace_id":"namespace-original","org_id":"00D000000000001EAA","resource_origin":"https://example.invalid"}}}

///|
// These matching Native definitions are compile-only until a separately
// selected physical fixture executes them. Selection is not a Work token.
test "Native preparation Provider selection preserves values without granting I/O" {
  let selected = admit_local_salesforce_preparation_selection(
    local_preparation_provider_wire.replace_all(
      old="\"namespace_id\":\"namespace-original\"",
      new="\"namespace_id\":\"e\\u0301\\r\\n\"",
    ),
  ).unwrap()
  assert_eq(selected.namespace_id, "e\u0301\r\n")
  assert_eq(selected.org_id, "00D000000000001EAA")
  assert_eq(selected.connector_registration, "salesforce")
  assert_eq(selected.connector_revision, "salesforce/0.1")
  assert_eq(selected.resource_origin, "https://example.invalid")
  for
    (old, replacement) in [
      ("\"environment\":\"local\",", ""),
      ("\"namespace_id\":\"namespace-original\"", "\"namespace_id\":null"),
      ("connection-original", ""),
      ("salesforce/0.1", "salesforce/unsupported"),
      (
        "\"connector_registration\":\"salesforce\"", "\"connector_registration\":\"other\"",
      ),
      ("https://example.invalid", "http://example.invalid"),
      ("https://example.invalid", "https://user@example.invalid"),
      ("https://example.invalid", "https://example.invalid/path"),
      ("https://example.invalid", "https://example.invalid?query"),
      ("https://example.invalid", "https://example.invalid#fragment"),
      ("https://example.invalid", "https://example.invalid\\r\\n"),
      ("https://example.invalid", "https://example.invalid\\t"),
      ("https://example.invalid", "https://"),
      (
        "\"environment\":\"local\"", "\"environment\":\"local\",\"secret_path\":\"token\"",
      ),
      (
        "\"environment\":\"local\"", "\"environment\":\"local\",\"site_key\":\"invented\"",
      ),
      ("namespace-original", "n".repeat(513)),
    ] {
    assert_true(
      admit_local_salesforce_preparation_selection(
        local_preparation_provider_wire.replace_all(old~, new=replacement),
      )
      is Err(InvalidSelection),
    )
  }
}

///|
fn local_preparation_account(submit : Bool, target_read : Bool) -> Bytes {
  let entries : Array[String] = []
  if submit {
    entries.push(
      (
        #|{"entry_id":"submit","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["submit"]},"exclusions":[]}
      ),
    )
  }
  if target_read {
    entries.push(
      (
        #|{"entry_id":"target-read","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["connector://crm/main/r#v"]},"operation":{"any_of":["read"]},"exclusions":[]}
      ),
    )
  }
  @utf8.encode(
    "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[" +
    entries.join(",") +
    "]}",
  )
}

///|
test "Native preparation target read requires both current Run and checked target authority" {
  let crypto = epoch_test_crypto()
  for
    (submit, target_read, expected) in [
      (false, false, false),
      (true, false, false),
      (false, true, false),
      (true, true, true),
    ] {
    let host = policy_host_fixture(
      "preparation-read-" + submit.to_string() + "-" + target_read.to_string(),
      account_body=local_preparation_account(submit, target_read),
    )
    let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
    assert_eq(
      native_local_preparation_read_authorized(
        host, crypto, "operator", "cli", scope, "connector://crm/main/r#v",
      ),
      expected,
    )
    // Read is neither issuer authority nor mutation apply/Reviewer approval.
    for
      (resource, operation) in [
        ("credential/credential-authority-a", "issue"),
        ("connector://crm/main/r#v", "update"),
        ("run", "approve"),
      ] {
      assert_true(
        host.authorize({
          principal: "operator",
          connection: "cli",
          resource,
          operation,
        })
        is Ok(@authorization.Deny(_)),
      )
    }
    host.close().unwrap()
  }
}

///|
test "Native preparation current read refuses foreign scope caller target and lost adoption" {
  let host = policy_host_fixture(
    "preparation-current-read",
    account_body=local_preparation_account(true, true),
  )
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  assert_true(
    native_local_preparation_read_authorized(
      host, crypto, "operator", "cli", scope, "connector://crm/main/r#v",
    ),
  )
  for
    (principal, connection, current_scope, resource) in [
      ("other", "cli", scope, "connector://crm/main/r#v"),
      ("operator", "other", scope, "connector://crm/main/r#v"),
      (
        "operator",
        "cli",
        "sha256:" + "a".repeat(64),
        "connector://crm/main/r#v",
      ),
      ("operator", "cli", scope, "connector://crm/main/other#v"),
    ] {
    assert_false(
      native_local_preparation_read_authorized(
        host, crypto, principal, connection, current_scope, resource,
      ),
    )
  }
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
    native_local_preparation_read_authorized(
      host, crypto, "operator", "cli", scope, "connector://crm/main/r#v",
    ),
  )
  assert_true(host.check_binding() is Err(CustodyLost))
  host.close().unwrap()
}

///|
test "Native preparation selection refuses discovery identical replacement and missing custody" {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(root).unwrap()
  for (suffix, replace) in [("replaced", true), ("missing", false)] {
    let name = "preparation-provider-" + suffix
    let file = name + ".provider.json"
    let writer = parent.create_writer(name + ".stage", 8192L).unwrap()
    writer.append(@utf8.encode(local_preparation_provider_wire)).unwrap()
    writer.seal(file).unwrap() |> ignore
    let host = policy_host_fixture(name, files=[file])
    let (original, _) = host.selected_salesforce_preparation(file).unwrap()
    assert_eq(original.body, @utf8.encode(local_preparation_provider_wire))
    assert_true(
      host.selected_salesforce_preparation("discovered.json")
      is Err(ForeignInstallation),
    )
    if replace {
      let generation = parent.inspect_generation(file).unwrap().unwrap()
      parent.reclaim_generation(file, generation).unwrap()
      let writer = parent
        .create_writer(name + ".replacement.stage", 8192L)
        .unwrap()
      writer.append(@utf8.encode(local_preparation_provider_wire)).unwrap()
      writer.seal(file).unwrap() |> ignore
    } else {
      let table = @utf8.encode("client_local_settings")
      let key = @utf8.encode("file:" + file)
      assert_true(
        submitted_test_remove_record(
          host.database,
          table,
          table.length(),
          key,
          key.length(),
        ),
      )
    }
    assert_true(host.selected_salesforce_preparation(file) is Err(Adoption(_)))
    host.close().unwrap()
    assert_true(
      host.selected_salesforce_preparation(file) is Err(Adoption(Closed)),
    )
  }
}
