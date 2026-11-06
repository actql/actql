///|
let local_settings_original : Bytes = b"{\"nested\":{\"text\":\"e\\u0301\",\"missing\":null},\"line\":\"a\\r\\nb\"}\r\n"

///|
test "Native Local authority scope binds adopted caller without granting execution" {
  let session = local_settings_fixture("local-settings-authority")
  let crypto = epoch_test_crypto()
  let host = session
    .open_journal(local_journal_test_library(), crypto, 100.0, 8, 8388608L)
    .unwrap()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  assert_eq(host.authority_scope_cid("operator", "cli", crypto).unwrap(), scope)
  assert_true(
    host.authority_scope_cid("other", "cli", crypto).unwrap() != scope,
  )
  assert_true(
    host.authority_scope_cid("operator", "other", crypto).unwrap() != scope,
  )
  assert_true(
    host.authority_scope_cid("e\u{301}", "cli", crypto).unwrap() !=
    host.authority_scope_cid("é", "cli", crypto).unwrap(),
  )
  assert_true(host.authority_scope_cid("", "cli", crypto) is Err(InvalidInput))
  assert_true(
    host
    .authorize({
      principal: "operator",
      connection: "cli",
      resource: "run",
      operation: "submit",
    })
    .unwrap()
    is Deny(NoMatch),
  )
  host.close().unwrap()
  assert_true(
    host.authorize({
      principal: "operator",
      connection: "cli",
      resource: "run",
      operation: "submit",
    })
    is Err(Closed),
  )
}

///|
test "Native Local reconnect cannot create state or finish partial adoption" {
  let (path, account, parent, _) = local_selected_source(
    "local-settings-reconnect",
  )
  let crypto = epoch_test_crypto()
  assert_true(
    begin_native_local_host_adoption(
      path,
      "local-settings-no-host",
      path,
      account,
      "operator",
      crypto,
      existing_only=true,
    )
    is Err(CustodyLost),
  )
  assert_eq(parent.inspect_directory("local-settings-no-host").unwrap(), None)
  for stage in [false, true] {
    let name = "local-settings-partial-" + stage.to_string()
    let session = begin_native_local_host_adoption(
      path, name, path, account, "operator", crypto,
    ).unwrap()
    if stage {
      session.stage_configuration().unwrap()
    }
    assert_true(session.close())
    let restored = begin_native_local_host_adoption(
      path,
      name,
      path,
      account,
      "operator",
      crypto,
      existing_only=true,
    ).unwrap()
    assert_true(
      restored.open_journal(
        local_journal_test_library(),
        crypto,
        100.0,
        8,
        8388608L,
      )
      is Err(CustodyLost),
    )
    assert_eq(restored.root.inspect_generation("client.sqlite3").unwrap(), None)
    assert_eq(
      restored.root.inspect_generation("journal-initializing.json").unwrap(),
      None,
    )
    assert_eq(
      restored.root.inspect_generation("account.json").unwrap() is Some(_),
      stage,
    )
    assert_true(restored.close())
  }
}

///|
fn local_settings_fixture(
  name : String,
  state_parent? : String? = None,
) -> NativeLocalAdoptionSession {
  let (path, account_name, parent, _) = local_selected_source(name)
  let writer = parent.create_writer(name + ".settings.stage", 65536L).unwrap()
  writer.append(local_settings_original).unwrap()
  writer.seal(name + ".settings.json").unwrap() |> ignore
  parent.create_directory(name + ".managed").unwrap() |> ignore
  begin_native_local_host_adoption(
    state_parent.unwrap_or(path),
    name + ".host",
    path,
    account_name,
    "operator",
    epoch_test_crypto(),
    configuration_files=[name + ".settings.json"],
    managed_root_path=Some(path + "/" + name + ".managed"),
  ).unwrap()
}

///|
test "Native Local selected originals and managed root survive exact adoption reopen" {
  let session = local_settings_fixture("local-settings-retained")
  let manifest = session.settings.manifest
  let original = session.intent_cid()
  let managed = session.settings.managed.unwrap().path
  let host = session
    .open_journal(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    )
    .unwrap()
  assert_eq(
    host
    .selected_configuration("local-settings-retained.settings.json")
    .unwrap(),
    local_settings_original,
  )
  assert_eq(host.managed_root_path().unwrap(), Some(managed))
  assert_eq(
    host.database.read("client_local_settings", "manifest").unwrap().body,
    manifest,
  )
  assert_eq(host.configuration().unwrap().entry_count(), 0)
  host.close().unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let restored = begin_native_local_host_adoption(
    path,
    "local-settings-retained.host",
    path,
    "local-settings-retained.account.json",
    "operator",
    epoch_test_crypto(),
    configuration_files=["local-settings-retained.settings.json"],
    managed_root_path=Some(managed),
    existing_only=true,
  ).unwrap()
  assert_eq(restored.intent_cid(), original)
  let host = restored
    .open_journal(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    )
    .unwrap()
  assert_eq(
    host
    .selected_configuration("local-settings-retained.settings.json")
    .unwrap(),
    local_settings_original,
  )
  assert_true(
    host.selected_configuration("unselected.json") is Err(InvalidInput),
  )
  host.close().unwrap()
}

///|
test "Native Local settings replacement cannot reuse the original installation identity" {
  let session = local_settings_fixture("local-settings-replaced")
  let parent = session.source_root
  let name = "local-settings-replaced.settings.json"
  let original = parent.inspect_generation(name).unwrap().unwrap()
  parent.reclaim_generation(name, original).unwrap()
  let writer = parent
    .create_writer("settings-replacement.stage", 65536L)
    .unwrap()
  writer.append(local_settings_original).unwrap()
  writer.seal(name).unwrap() |> ignore
  assert_true(session.stage_configuration() is Err(SourceChanged))
  assert_eq(session.root.inspect_generation("account.json").unwrap(), None)
  assert_true(session.close())
}

///|
test "Native Local lost selected-original custody is never recopied from source" {
  let session = local_settings_fixture("local-settings-lost")
  let host = session
    .open_journal(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    )
    .unwrap()
  let table = @utf8.encode("client_local_settings")
  let key = @utf8.encode("file:local-settings-lost.settings.json")
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
    host.selected_configuration("local-settings-lost.settings.json")
    is Err(CustodyLost),
  )
  assert_true(
    host.database.read(
      "client_local_settings", "file:local-settings-lost.settings.json",
    )
    is Err(@sqlite.NotFound),
  )
  let epoch = host.database
    .read("client_submission_epoch", "authority")
    .unwrap().body
  host.close().unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let restored = begin_native_local_host_adoption(
    path,
    "local-settings-lost.host",
    path,
    "local-settings-lost.account.json",
    "operator",
    epoch_test_crypto(),
    configuration_files=["local-settings-lost.settings.json"],
    managed_root_path=Some(path + "/local-settings-lost.managed"),
  ).unwrap()
  guard restored.open_journal(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    )
    is Err(DatabasePending(database, CustodyLost)) else {
    fail("lost original was silently recopied")
  }
  assert_eq(
    database.read("client_submission_epoch", "authority").unwrap().body,
    epoch,
  )
  assert_true(
    database.read(
      "client_local_settings", "file:local-settings-lost.settings.json",
    )
    is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
  assert_true(restored.close())
}

///|
test "Native Local selected managed-root custody cannot be replaced or detached" {
  let session = local_settings_fixture("local-settings-detached")
  let managed = session.settings.managed.unwrap()
  assert_true(
    session.parent
    .remove_directory("local-settings-detached.managed", managed.ownership)
    .unwrap(),
  )
  assert_true(session.stage_configuration() is Err(CustodyLost))
  assert_eq(session.root.inspect_generation("account.json").unwrap(), None)
  assert_true(session.close())
}

///|
test "Material installation selects the tenth actual original and refuses an eleventh" {
  let (_, account, parent, _) = local_selected_source("local-settings-tenth")
  let names : Array[String] = []
  for index in 0..<10 {
    let name = "selected-" + index.to_string() + ".json"
    let writer = parent.create_writer("selected.stage", 65536L).unwrap()
    writer.append(b"{}").unwrap()
    writer.seal(name).unwrap() |> ignore
    names.push(name)
  }
  let selected = select_native_local_configuration(
    parent,
    account,
    names,
    None,
    epoch_test_crypto(),
  ).unwrap()
  assert_eq(selected.files.length(), 10)
  selected.check_source(parent).unwrap()
  for file in selected.files {
    assert_eq(file.body, b"{}")
    assert_true(names.contains(file.name))
  }
  // The eleventh name has no file: count refusal must precede physical intake.
  names.push("not-created.json")
  assert_true(
    select_native_local_configuration(
      parent,
      account,
      names,
      None,
      epoch_test_crypto(),
    )
    is Err(ConfigurationLimit),
  )
  parent.close().unwrap()
}

///|
test "Native Local selection rejects duplicate escape and over-budget originals before state creation" {
  let (path, account, parent, _) = local_selected_source(
    "local-settings-invalid",
  )
  for
    names in [
      [account],
      ["../settings"],
      ["same.json", "same.json"],
      ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"],
    ] {
    assert_true(
      begin_native_local_host_adoption(
        path,
        "local-settings-invalid.host",
        path,
        account,
        "operator",
        epoch_test_crypto(),
        configuration_files=names,
      )
      is Err(_),
    )
    assert_eq(
      parent.inspect_directory("local-settings-invalid.host").unwrap(),
      None,
    )
  }
  let writer = parent.create_writer("settings-large.stage", 65537L).unwrap()
  writer.append(Bytes::make(65537, 32)).unwrap()
  writer.seal("settings-large.json").unwrap() |> ignore
  assert_true(
    begin_native_local_host_adoption(
      path,
      "local-settings-invalid.host",
      path,
      account,
      "operator",
      epoch_test_crypto(),
      configuration_files=["settings-large.json"],
    )
    is Err(ConfigurationLimit),
  )
  assert_eq(
    parent.inspect_directory("local-settings-invalid.host").unwrap(),
    None,
  )
}

///|
test "Native Local selected originals commit atomically with original epoch custody" {
  for reply_lost in [false, true] {
    let name = "local-settings-commit-" + reply_lost.to_string()
    let session = local_settings_fixture(name)
    let database = epoch_test_database(name)
    if reply_lost {
      client_test_fail_commit_reply(database, 1)
    } else {
      client_test_fail_commit(database, 1)
    }
    assert_true(
      initialize_native_local_client_custody(
        database,
        epoch_test_crypto(),
        b"original-adoption",
        settings=Some(session.settings),
      )
      is Err(TransactionUnknown),
    )
    if !reply_lost {
      database.rollback().unwrap()
    }
    database.close_checked().unwrap()
    let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
    let restored = local_journal_test_library()
      .open_existing_database(path + "/" + name + ".sqlite3", 65536L)
      .unwrap()
    if reply_lost {
      assert_eq(
        restored
        .read("client_local_settings", "file:" + name + ".settings.json")
        .unwrap().body,
        local_settings_original,
      )
      assert_true(
        restored.read("client_submission_epoch", "authority") is Ok(_),
      )
      assert_true(
        initialize_native_local_client_custody(
          restored,
          epoch_test_crypto(),
          b"replacement",
          settings=Some(session.settings),
        )
        is Err(CustodyLost),
      )
    } else {
      assert_true(
        restored.scan_after("client_local_settings", "")
        is Err(@sqlite.NotFound),
      )
      assert_true(
        restored.read("client_submission_epoch", "authority")
        is Err(@sqlite.NotFound),
      )
    }
    restored.close_checked().unwrap()
    assert_true(session.close())
  }
}
