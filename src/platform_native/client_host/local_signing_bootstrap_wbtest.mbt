///|
// Real explicit adoption/Root/SQLite and public PEM metadata. Descriptor bytes
// are deliberately not a private key. No issuer, grant, use or signer is run.
fn signing_bootstrap_fixture(
  name : String,
  existing? : Bool = false,
  descriptor? : Bool = true,
  account_body? : String = reviewer_signing_scope_account,
) -> (
  NativeLocalAdoptionSession,
  @crypto.Library,
  NativeLocalSigningInstallationSelection,
) raise {
  let key_file = name + ".key.json"
  let reviewer_file = name + ".reviewer.json"
  let account_file = name + ".account.json"
  let private_file = name + ".descriptor"
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  if !existing {
    signing_original_write(
      key_file,
      @utf8.encode(
        signing_original_configuration(
          private_file,
          signing_original_public_a,
          reviewer=true,
        ),
      ),
    )
    signing_original_write(
      reviewer_file,
      @utf8.encode(
        local_reviewer_selection_wire
        .replace_all(old="\"operator\"", new="\"reviewer\"")
        .replace_all(old="\"cli\"", new="\"review-cli\""),
      ),
    )
    signing_original_write(account_file, @utf8.encode(account_body))
    if descriptor {
      signing_original_write(private_file, b"synthetic-file-generation-only")
    }
    let root = signing_grant_fixture_require(
      @filesystem.open_private_root(path),
      "bootstrap_fixture_root",
    )
    signing_grant_fixture_require(
      root.create_directory(name + ".parent"),
      "bootstrap_fixture_parent",
    )
    |> ignore
    signing_grant_fixture_require(root.close(), "bootstrap_fixture_root_close")
  }
  let crypto = signing_grant_fixture_require(
    @crypto.load_library(
      @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
      diagnostic_ceiling=Some(64),
    ),
    "bootstrap_public_crypto",
  )
  let adoption = signing_grant_fixture_require(
    begin_native_local_host_adoption(
      path + "/" + name + ".parent",
      name + ".host",
      path,
      account_file,
      "operator",
      crypto,
      configuration_files=[key_file, reviewer_file],
    ),
    "bootstrap_original_adoption",
  )
  (
    adoption,
    crypto,
    {
      key_configuration_file: key_file,
      reviewer_configuration_file: Some(reviewer_file),
      checkpoint_kind: @checkpoint.EffectSet,
    },
  )
}

///|
fn signing_bootstrap_restore(
  host : NativeLocalHostConnection,
  crypto : @crypto.Library,
  selected : NativeLocalSigningInstallationSelection,
) -> NativeLocalSigningKeyOriginal raise {
  let reviewer = signing_grant_fixture_require(
    host.install_effect_reviewer(
      configuration_file=selected.reviewer_configuration_file,
    ),
    "bootstrap_selected_reviewer",
  )
  let account = signing_grant_fixture_require(
    host.acquire_signing_key_account(
      crypto,
      selected.key_configuration_file,
      selected.checkpoint_kind,
      reviewer=Some(reviewer),
    ),
    "bootstrap_current_key_account",
  )
  signing_grant_fixture_require(
    account.restore_signing_key_original(),
    "bootstrap_restore_only_key",
  )
}

///|
fn signing_bootstrap_close_failure(
  result : Result[NativeLocalHostConnection, NativeLocalAdoptionIssue],
  session : NativeLocalAdoptionSession,
) -> NativeLocalAdoptionIssue raise {
  match result {
    Ok(host) => {
      host.close().unwrap()
      fail("unexpected bootstrap success")
    }
    Err(DatabasePending(database, issue)) => {
      database.close_checked().unwrap()
      assert_true(session.close())
      issue
    }
    Err(issue) => {
      assert_true(session.close())
      issue
    }
  }
}

///|
test "Signing bootstrap explicit first installation retains only original metadata and no grant" {
  let (session, crypto, selected) = signing_bootstrap_fixture("bootstrap-first")
  let host = signing_grant_fixture_require(
    session.open_journal_with_signing_originals(
      local_journal_test_library(),
      crypto,
      100.0,
      8,
      8388608L,
      [selected],
    ),
    "bootstrap_first_open",
  )
  let key = signing_bootstrap_restore(host, crypto, selected)
  assert_eq(key.public_key_cid(), signing_original_public_a_cid)
  assert_eq(
    host.database.read("client_local_installation_custody", "issued").unwrap().revision,
    1L,
  )
  assert_eq(
    host.database
    .read(
      "client_local_installation_originals",
      selected.key_configuration_file,
    )
    .unwrap().revision,
    0L,
  )
  assert_eq(
    host.database.capacity_usage("client_local_settings").unwrap().reserved_bytes,
    8192L,
  )
  assert_true(
    host.database.scan_after("client_local_grant_originals", "")
    is Err(@sqlite.NotFound),
  )
  assert_false(
    host.authorize({
      principal: "operator",
      connection: "cli",
      resource: "credential/credential-authority-a",
      operation: "issue",
    })
    is Ok(@authorization.Allow(_)),
  )
  host.close().unwrap()
}

///|
test "Signing bootstrap reopens the same original generation without another capture or counter" {
  let name = "bootstrap-reopen"
  let (session, crypto, selected) = signing_bootstrap_fixture(name)
  let host = session
    .open_journal_with_signing_originals(
      local_journal_test_library(),
      crypto,
      100.0,
      8,
      8388608L,
      [selected],
    )
    .unwrap()
  let key = signing_bootstrap_restore(host, crypto, selected)
  let generation = key.generation_cid()
  let adoption = host.adoption_cid
  let row = host.database
    .read(
      "client_local_installation_originals",
      selected.key_configuration_file,
    )
    .unwrap()
  host.close().unwrap()
  // existing_only remains false: actual marker/DB state, not a caller flag,
  // still forces the existing authenticated restore-only branch.
  let (session, crypto, selected) = signing_bootstrap_fixture(
    name,
    existing=true,
  )
  let restored = session
    .open_journal_with_signing_originals(
      local_journal_test_library(),
      crypto,
      100.0,
      8,
      8388608L,
      [selected],
    )
    .unwrap()
  let key = signing_bootstrap_restore(restored, crypto, selected)
  assert_eq(key.generation_cid(), generation)
  assert_eq(restored.adoption_cid, adoption)
  assert_eq(
    restored.database
    .read(
      "client_local_installation_originals",
      selected.key_configuration_file,
    )
    .unwrap().body,
    row.body,
  )
  assert_eq(
    restored.database
    .read("client_local_installation_custody", "issued")
    .unwrap().revision,
    1L,
  )
  restored.close().unwrap()
}

///|
test "Signing bootstrap omitted default never reads a descriptor or repairs missing old originals" {
  let name = "bootstrap-no-default"
  let (session, crypto, selected) = signing_bootstrap_fixture(
    name,
    descriptor=false,
  )
  let host = session
    .open_journal(local_journal_test_library(), crypto, 100.0, 8, 8388608L)
    .unwrap()
  assert_true(
    host.database.scan_after("client_local_installation_originals", "")
    is Err(@sqlite.NotFound),
  )
  assert_eq(
    host.database.read("client_local_installation_custody", "issued").unwrap().revision,
    0L,
  )
  host.close().unwrap()
  signing_original_write(
    name + ".descriptor",
    b"synthetic-file-generation-only",
  )
  let (session, crypto, selected_again) = signing_bootstrap_fixture(
    name,
    existing=true,
  )
  let issue = signing_bootstrap_close_failure(
    session.open_journal_with_signing_originals(
      local_journal_test_library(),
      crypto,
      100.0,
      8,
      8388608L,
      [selected_again],
    ),
    session,
  )
  assert_true(issue is Journal(CustodyLost))
  let (session, crypto, _) = signing_bootstrap_fixture(name, existing=true)
  let old = session
    .open_journal(local_journal_test_library(), crypto, 100.0, 8, 8388608L)
    .unwrap()
  assert_true(
    old.database.read(
      "client_local_installation_originals",
      selected.key_configuration_file,
    )
    is Err(@sqlite.NotFound),
  )
  assert_eq(
    old.database.read("client_local_installation_custody", "issued").unwrap().revision,
    0L,
  )
  old.close().unwrap()
}

///|
test "Signing bootstrap refuses replacement physical generation instead of recapturing" {
  let name = "bootstrap-replaced"
  let (session, crypto, selected) = signing_bootstrap_fixture(name)
  let host = session
    .open_journal_with_signing_originals(
      local_journal_test_library(),
      crypto,
      100.0,
      8,
      8388608L,
      [selected],
    )
    .unwrap()
  let root = host.session.source_root
  let file = name + ".descriptor"
  root
  .reclaim_generation(file, root.inspect_generation(file).unwrap().unwrap())
  .unwrap()
  let writer = root.create_writer(name + ".replacement.stage", 4096L).unwrap()
  writer.append(b"synthetic-file-generation-only").unwrap()
  writer.seal(file).unwrap() |> ignore
  let row = host.database
    .read(
      "client_local_installation_originals",
      selected.key_configuration_file,
    )
    .unwrap()
  host.close().unwrap()
  let (session, crypto, selected) = signing_bootstrap_fixture(
    name,
    existing=true,
  )
  let result = session.open_journal_with_signing_originals(
    local_journal_test_library(),
    crypto,
    100.0,
    8,
    8388608L,
    [selected],
  )
  match result {
    Err(DatabasePending(database, issue)) => {
      assert_true(issue is Journal(CustodyLost) || issue is CustodyLost)
      let after = database
        .read(
          "client_local_installation_originals",
          selected.key_configuration_file,
        )
        .unwrap()
      assert_eq(after.revision, row.revision)
      assert_eq(after.body, row.body)
      assert_eq(
        database.read("client_local_installation_custody", "issued").unwrap().revision,
        1L,
      )
      database.close_checked().unwrap()
      assert_true(session.close())
    }
    _ => {
      signing_bootstrap_close_failure(result, session) |> ignore
      fail("expected replaced original with retained cleanup handle")
    }
  }
}

///|
test "Signing bootstrap rejects duplicate or unselected metadata before database initialization" {
  let (session, crypto, selected) = signing_bootstrap_fixture(
    "bootstrap-invalid-selection",
  )
  assert_true(
    session.open_journal_with_signing_originals(
      local_journal_test_library(),
      crypto,
      100.0,
      8,
      8388608L,
      [selected, selected],
    )
    is Err(InvalidInput),
  )
  assert_true(session.root.inspect_generation("client.sqlite3") is Ok(None))
  assert_true(
    session.open_journal_with_signing_originals(
      local_journal_test_library(),
      crypto,
      100.0,
      8,
      8388608L,
      [{ ..selected, key_configuration_file: "not-selected.json", }],
    )
    is Err(InvalidInput),
  )
  assert_true(session.root.inspect_generation("client.sqlite3") is Ok(None))
  assert_true(session.close())
}

///|
test "Signing bootstrap denied current Reviewer does not create an installation original" {
  let account = reviewer_signing_scope_account.replace_all(
    old="\"operation\":{\"any_of\":[\"resolve\"]}",
    new="\"operation\":{\"any_of\":[\"read\"]}",
  )
  let (session, crypto, selected) = signing_bootstrap_fixture(
    "bootstrap-denied-reviewer",
    account_body=account,
  )
  let result = session.open_journal_with_signing_originals(
    local_journal_test_library(),
    crypto,
    100.0,
    8,
    8388608L,
    [selected],
  )
  match result {
    Err(DatabasePending(database, issue)) => {
      assert_true(issue is CustodyLost)
      assert_true(
        database.scan_after("client_local_installation_originals", "")
        is Err(@sqlite.NotFound),
      )
      assert_eq(
        database.read("client_local_installation_custody", "issued").unwrap().revision,
        0L,
      )
      database.close_checked().unwrap()
      assert_true(session.close())
    }
    _ => {
      signing_bootstrap_close_failure(result, session) |> ignore
      fail("expected typed denied bootstrap with retained database")
    }
  }
}
