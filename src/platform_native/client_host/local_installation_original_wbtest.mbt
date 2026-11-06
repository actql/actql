///|
// Matching Native storage definitions, compile-only until a selected physical
// run executes them. These never construct a started Work or authorize HTTP.
fn local_installation_fixture(
  name : String,
  existing? : Bool = false,
  state_parent? : String? = None,
) -> (
  NativeLocalHostConnection,
  NativeLocalSelectedFile,
  NativeLocalSelectedFile,
  NativeLocalPreparationInstallationSelection,
) {
  let setting = name + ".installation.json"
  let provider = name + ".provider.json"
  let credential = name + ".bearer"
  if !existing {
    let root = @filesystem.open_private_root(
      @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap(),
    ).unwrap()
    let selected = @utf8.encode(
      "{\"version\":\"actql-config/0.1\",\"native\":{\"preparation_credential\":{\"credential_file\":\"" +
      credential +
      "\",\"provider_file\":\"" +
      provider +
      "\"}}}",
    )
    for
      (suffix, file, body) in [
        ("installation", setting, selected),
        ("provider", provider, @utf8.encode(local_preparation_provider_wire)),
        ("bearer", credential, b"synthetic-installation-token"),
      ] {
      let writer = root
        .create_writer(name + "." + suffix + ".stage", 8192L)
        .unwrap()
      writer.append(body).unwrap()
      writer.seal(file).unwrap() |> ignore
    }
  }
  let host = policy_host_fixture(
    name,
    existing~,
    files=[setting, provider],
    account_body=local_preparation_account(true, true),
    state_parent~,
  )
  let setting = host.session.settings.files
    .iter()
    .find_first(file => file.name == setting)
    .unwrap()
  let provider = host.session.settings.files
    .iter()
    .find_first(file => file.name == provider)
    .unwrap()
  let selection = local_preparation_installation_selection(setting.body).unwrap()
  (host, setting, provider, selection)
}

///|
// Only the storage layer is exercised here. The public entry additionally
// requires its real opaque original Work/target and current checked binding.
fn local_installation_test_original(
  host : NativeLocalHostConnection,
  file : NativeLocalSelectedFile,
  provider : NativeLocalSelectedFile,
  selection : NativeLocalPreparationInstallationSelection,
  adopt : Bool,
) -> Result[@filesystem.PrivateFileProjection, NativeClientRunJournalIssue] {
  let scope = host
    .authority_scope_cid("operator", "cli", epoch_test_crypto())
    .unwrap()
  host.journal.transaction(() => {
    host.installation_original_locked(file, provider, selection, adopt, () => {
      if native_local_preparation_read_authorized(
          host,
          epoch_test_crypto(),
          "operator",
          "cli",
          scope,
          "connector://crm/main/r#v",
        ) {
        Ok(())
      } else {
        Err(AuthorizationDenied)
      }
    })
  })
}

///|
test "Native installation setting is finite and cannot introduce grants or invented scope" {
  let original = b"{\"version\":\"actql-config/0.1\",\"native\":{\"preparation_credential\":{\"credential_file\":\"bearer\",\"provider_file\":\"provider.json\"}}}"
  let selected = local_preparation_installation_selection(original).unwrap()
  assert_eq(selected.credential_file, "bearer")
  assert_eq(selected.provider_file, "provider.json")
  let text = @utf8.decode(original)
  for
    (old, replacement) in [
      ("\"bearer\"", "null"),
      ("\"bearer\"", "\"../bearer\""),
      ("\"bearer\"", "\"provider.json\""),
      ("\"bearer\"", "\"bearer\",\"grant\":true"),
      ("\"bearer\"", "\"bearer\",\"site_key\":\"invented\""),
      ("actql-config/0.1", "foreign-config"),
      ("\"provider_file\":\"provider.json\"", "\"provider_file\":\"\""),
      (
        "\"provider_file\":\"provider.json\"", "\"provider_file\":\"provider.json\",\"provider_file\":\"other.json\"",
      ),
    ] {
    assert_true(
      local_preparation_installation_selection(
        @utf8.encode(text.replace_all(old~, new=replacement)),
      )
      is Err(InvalidInput),
    )
  }
}

///|
test "Native installation append replay and reopen retain one exact original and reservation" {
  let name = "local-installation-reopen"
  let (host, file, provider, selection) = local_installation_fixture(name)
  let original = local_installation_test_original(
      host, file, provider, selection, true,
    )
    .unwrap()
    .export_original()
    .unwrap()
  let row = host.database
    .read("client_local_installation_originals", file.name)
    .unwrap()
  let original_adoption = host.adoption_cid
  let expected = @utf8.encode(
    "{\"adoption_cid\":\"" +
    original_adoption +
    "\",\"installation_configuration_cid\":\"" +
    file.content_cid +
    "\",\"provider_configuration_cid\":\"" +
    provider.content_cid +
    "\",\"projection\":\"" +
    @base64.encode(original) +
    "\",\"version\":\"actql-native-local-installation-original/0.1\"}",
  )
  assert_eq(
    local_installation_payload(host, file, provider, original).unwrap(),
    expected,
  )
  for adopt in [true, false, true] {
    let restored = local_installation_test_original(
      host, file, provider, selection, adopt,
    ).unwrap()
    assert_eq(restored.export_original().unwrap(), original)
    assert_eq(
      host.database
      .read("client_local_installation_originals", file.name)
      .unwrap().body,
      row.body,
    )
    assert_eq(
      host.database.read("client_local_installation_custody", "issued").unwrap().revision,
      1L,
    )
    assert_eq(
      host.database.capacity_usage("client_local_settings").unwrap().reserved_bytes,
      8192L,
    )
    assert_eq(
      host.database.capacity_usage("client_local_settings").unwrap().reserved_objects,
      1L,
    )
    assert_true(
      host.database.scan_after("client_runs", "") is Err(@sqlite.NotFound),
    )
    assert_eq(
      host.database.read("client_local_grant_custody", "issued").unwrap().body,
      b"0",
    )
  }
  host.close().unwrap()
  let (restored, file, provider, selection) = local_installation_fixture(
    name,
    existing=true,
  )
  assert_eq(restored.adoption_cid, original_adoption)
  assert_eq(
    local_installation_test_original(restored, file, provider, selection, false)
    .unwrap()
    .export_original()
    .unwrap(),
    original,
  )
  assert_eq(
    restored.database
    .read("client_local_installation_originals", file.name)
    .unwrap().body,
    row.body,
  )
  restored.close().unwrap()
}

///|
test "Native installation restore never bootstraps a missing original or reservation" {
  for
    damage in [
      "never-adopted", "original", "reservation", "witness", "extra-witness",
    ] {
    let (host, file, provider, selection) = local_installation_fixture(
      "local-installation-lost-" + damage,
    )
    if damage != "never-adopted" {
      local_installation_test_original(host, file, provider, selection, true).unwrap()
      |> ignore
    }
    match damage {
      "original" | "witness" => {
        let table = @utf8.encode(
          if damage == "original" {
            "client_local_installation_originals"
          } else {
            "client_local_installation_custody"
          },
        )
        let key = @utf8.encode(
          if damage == "original" {
            file.name
          } else {
            "issued"
          },
        )
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
      "reservation" =>
        assert_true(
          host.database
          .release_capacity(
            "client_local_settings",
            "installation:" + file.name,
            8192L,
            1L,
          )
          .unwrap(),
        )
      "extra-witness" =>
        host.database
        .insert("client_local_installation_custody", "zzz", b"extra")
        .unwrap()
        |> ignore
      _ => ()
    }
    let before = host.database.capacity_usage("client_local_settings").unwrap()
    assert_true(
      local_installation_test_original(host, file, provider, selection, false)
      is Err(CustodyLost),
    )
    let after = host.database.capacity_usage("client_local_settings").unwrap()
    assert_eq(after.reserved_bytes, before.reserved_bytes)
    assert_eq(after.reserved_objects, before.reserved_objects)
    assert_true(
      host.database.scan_after("client_runs", "") is Err(@sqlite.NotFound),
    )
    host.close().unwrap()
  }
}

///|
test "Native installation original rejects altered bytes foreign Host and foreign selection" {
  let (host, file, provider, selection) = local_installation_fixture(
    "local-installation-auth",
  )
  let original = local_installation_test_original(
      host, file, provider, selection, true,
    )
    .unwrap()
    .export_original()
    .unwrap()
  let packet = host.database
    .read("client_local_installation_originals", file.name)
    .unwrap().body
  let envelope = local_adoption_fields(packet, ["payload", "tag"]).unwrap()
  let altered = local_adoption_record([
    ("payload", envelope[0]),
    ("tag", "0".repeat(64)),
  ]).unwrap()
  assert_true(
    read_local_installation_projection(host, file, altered) is Err(CustodyLost),
  )
  for
    changed in [
      { ..file, content_cid: "sha256:" + "0".repeat(64), },
      {
        ..file,
        body: file.body + b" ",
        content_cid: "sha256:" + "1".repeat(64),
      },
    ] {
    assert_true(
      read_local_installation_projection(host, changed, packet)
      is Err(CustodyLost),
    )
  }
  // The foreign Host keeps its own exclusive Adoption parent while the
  // original remains live; both retain the same Account source root.
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(path).unwrap()
  let state_name = "local-installation-foreign-parent"
  parent.create_directory(state_name).unwrap() |> ignore
  parent.close().unwrap()
  let (foreign, _, _, _) = local_installation_fixture(
    "local-installation-foreign",
    state_parent=Some(path + "/" + state_name),
  )
  assert_true(
    read_local_installation_projection(foreign, file, packet)
    is Err(CustodyLost),
  )
  foreign.close().unwrap()
  let payload = local_installation_payload(host, file, provider, original).unwrap()
  let text = @utf8.decode(payload)
  for
    (old, replacement) in [
      (host.adoption_cid, "sha256:" + "2".repeat(64)),
      (provider.content_cid, "sha256:" + "3".repeat(64)),
      (
        "actql-native-local-installation-original/0.1", "foreign-installation-original",
      ),
    ] {
    let signed_foreign = local_installation_packet(
      host,
      @utf8.encode(text.replace_all(old~, new=replacement)),
    ).unwrap()
    assert_true(
      read_local_installation_projection(host, file, signed_foreign)
      is Err(CustodyLost),
    )
  }
  host.close().unwrap()
}

///|
test "Native installation byte identical replacement refuses without replacing saved custody" {
  let (host, file, provider, selection) = local_installation_fixture(
    "local-installation-generation",
  )
  local_installation_test_original(host, file, provider, selection, true).unwrap()
  |> ignore
  let before = host.database
    .read("client_local_installation_originals", file.name)
    .unwrap()
  let root = host.session.source_root
  root
  .reclaim_generation(
    selection.credential_file,
    root.inspect_generation(selection.credential_file).unwrap().unwrap(),
  )
  .unwrap()
  let writer = root
    .create_writer("local-installation-replaced.stage", 8192L)
    .unwrap()
  writer.append(b"synthetic-installation-token").unwrap()
  writer.seal(selection.credential_file).unwrap() |> ignore
  for adopt in [false, true] {
    assert_true(
      local_installation_test_original(host, file, provider, selection, adopt)
      is Err(CustodyLost),
    )
  }
  assert_eq(
    host.database
    .read("client_local_installation_originals", file.name)
    .unwrap().body,
    before.body,
  )
  assert_eq(
    host.database.read("client_local_installation_custody", "issued").unwrap().revision,
    1L,
  )
  host.close().unwrap()
}

///|
test "Native installation current denial at each append boundary rolls back original and capacity" {
  for deny_at in [0, 1, 2] {
    let (host, file, provider, selection) = local_installation_fixture(
      "local-installation-denied-" + deny_at.to_string(),
    )
    let mut observed = 0
    assert_true(
      host.journal.transaction(() => {
        host.installation_original_locked(file, provider, selection, true, () => {
          let current = observed
          observed += 1
          if current == deny_at {
            Err(AuthorizationDenied)
          } else {
            Ok(())
          }
        })
      })
      is Err(AuthorizationDenied),
    )
    assert_eq(observed, deny_at + 1)
    assert_true(
      host.database.read("client_local_installation_originals", file.name)
      is Err(@sqlite.NotFound),
    )
    assert_eq(
      host.database.read("client_local_installation_custody", "issued").unwrap().body,
      b"0",
    )
    assert_eq(
      host.database.capacity_usage("client_local_settings").unwrap().reserved_bytes,
      0L,
    )
    host.close().unwrap()
  }
}
