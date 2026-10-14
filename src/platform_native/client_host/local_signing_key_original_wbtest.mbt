///|
// Independent DER/public-byte extraction and Python JSON/hashlib fixture only.
let signing_original_public_a_body : String =
  #|{"algorithm":"ed25519","public_key":"A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=","version":"actql-local-signing-public-key/0.1"}

///|
let signing_original_public_a_cid : String = "sha256:e749b44f58f00aea7462fff44345be1406f64320d52984005ad478213afa4b74"

///|
// Matching Native definitions only until explicitly allocated. Files contain
// synthetic descriptor text, not private PEMs; no grant, claim or signature.
let signing_original_public_a : String =
  #|-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAA6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=\n-----END PUBLIC KEY-----\n

///|
let signing_original_public_b : String =
  #|-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEA11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=\n-----END PUBLIC KEY-----\n

///|
fn signing_original_configuration(
  private_file : String,
  public_key : String,
  reviewer? : Bool = false,
) -> String {
  let wire = local_signing_account_key_wire
    .replace_all(old="host-attestation.pem", new=private_file)
    .replace_all(old="dummy-host-public-key", new=public_key)
  if reviewer {
    wire
    .replace_all(old="host_attestation", new="reviewer_proof")
    .replace_all(old="host-signer", new="reviewer")
    .replace_all(old="host-cli", new="review-cli")
    .replace_all(old="host-attestation-2026", new="release-approver-2026")
  } else {
    wire
  }
}

///|
fn signing_original_write(file : String, body : Bytes) -> Unit {
  let root = @filesystem.open_private_root(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap(),
  ).unwrap()
  let writer = root.create_writer(file + ".stage", 8192L).unwrap()
  writer.append(body).unwrap()
  writer.seal(file).unwrap() |> ignore
}

///|
fn signing_original_host(
  name : String,
  existing? : Bool = false,
) -> (NativeLocalHostConnection, String) {
  let key_file = name + ".signing.json"
  let private_file = name + ".descriptor"
  let account_file = name + ".account.json"
  if !existing {
    signing_original_write(
      key_file,
      @utf8.encode(
        signing_original_configuration(private_file, signing_original_public_a),
      ),
    )
    signing_original_write(private_file, b"synthetic-file-projection-only")
    signing_original_write(
      account_file,
      @utf8.encode(local_signing_account_wire),
    )
  }
  let crypto = @crypto.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(64),
  ).unwrap()
  let host = begin_native_local_host_adoption(
      @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap(),
      name + ".host",
      @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap(),
      account_file,
      "operator",
      crypto,
      existing_only=existing,
      configuration_files=[key_file],
    )
    .unwrap()
    .open_journal(local_journal_test_library(), crypto, 100.0, 8, 8388608L)
    .unwrap()
  (host, key_file)
}

///|
fn signing_original_binding(
  host : NativeLocalHostConnection,
  file : String,
) -> NativeLocalSigningAccountBinding {
  host
  .acquire_signing_key_account(host.epoch.crypto, file, @checkpoint.EffectSet)
  .unwrap()
}

///|
test "Local signing missing restore never installs and replay reopen keep the same HMAC row" {
  let name = "signing-original-reopen"
  let (host, file) = signing_original_host(name)
  let binding = signing_original_binding(host, file)
  assert_true(binding.restore_signing_key_original() is Err(_))
  assert_eq(host.installation_custody().unwrap().0, 0)
  let original = binding.capture_signing_key_original().unwrap()
  let row = host.database
    .read("client_local_installation_originals", file)
    .unwrap()
  assert_eq(row.revision, 0L)
  assert_eq(
    binding.capture_signing_key_original().unwrap().exported,
    original.exported,
  )
  assert_eq(
    binding.restore_signing_key_original().unwrap().generation_cid(),
    original.generation_cid(),
  )
  let usage = host.database.capacity_usage("client_local_settings").unwrap()
  assert_eq(usage.reserved_bytes, 8192L)
  assert_eq(usage.reserved_objects, 1L)
  let envelope = local_adoption_fields(row.body, ["payload", "tag"]).unwrap()
  let payload = @base64.decode(envelope[0]) catch {
    _ => fail("original payload missing")
  }
  let fields = local_adoption_fields(payload, [
    "adoption_cid", "authority_scope_cid", "installation_configuration_cid", "projection",
    "public_key_cid", "public_key_original", "purpose", "version",
  ]).unwrap()
  assert_eq(fields[0], host.adoption_cid)
  assert_eq(fields[1], binding.scope)
  assert_eq(fields[2], binding.file.content_cid)
  assert_eq(fields[4], signing_original_public_a_cid)
  assert_eq(fields[5], signing_original_public_a_body)
  assert_eq(fields[6], "host_attestation")
  assert_eq(fields[7], "actql-native-local-installation-original/0.1")
  assert_eq(original.public_key_cid(), signing_original_public_a_cid)
  host.close().unwrap()
  assert_true(original.require_current_key() is Err(_))
  let (restored, restored_file) = signing_original_host(name, existing=true)
  let retained = signing_original_binding(restored, restored_file)
    .restore_signing_key_original()
    .unwrap()
  assert_eq(retained.exported, original.exported)
  assert_eq(retained.public_key_cid(), signing_original_public_a_cid)
  assert_eq(
    restored.database.read("client_local_installation_originals", file).unwrap().body,
    row.body,
  )
  assert_eq(restored.installation_custody().unwrap().0, 1)
  restored.close().unwrap()
}

///|
test "Local signing original authenticates exact role scope config and Host without repair" {
  let (host, file) = signing_original_host("signing-original-auth")
  let binding = signing_original_binding(host, file)
  binding.capture_signing_key_original().unwrap() |> ignore
  let packet = host.database
    .read("client_local_installation_originals", file)
    .unwrap().body
  let envelope = local_adoption_fields(packet, ["payload", "tag"]).unwrap()
  let altered = local_adoption_record([
    ("payload", envelope[0]),
    ("tag", "0".repeat(64)),
  ]).unwrap()
  assert_true(
    read_local_installation_projection(host, binding.file, altered)
    is Err(CustodyLost),
  )
  let payload = read_local_installation_authenticated_payload(host, packet).unwrap()
  let text = @utf8.decode(payload)
  for
    (old, replacement) in [
      (host.adoption_cid, "sha256:" + "f".repeat(64)),
      (binding.scope, "sha256:" + "e".repeat(64)),
      (binding.file.content_cid, "sha256:" + "d".repeat(64)),
      ("host_attestation", "reviewer_proof"),
    ] {
    let signed_foreign = local_installation_packet(
      host,
      @utf8.encode(text.replace_all(old~, new=replacement)),
    ).unwrap()
    assert_true(
      read_local_installation_projection(host, binding.file, signed_foreign)
      is Err(CustodyLost),
    )
  }
  let (foreign, _) = signing_original_host("signing-original-foreign")
  assert_true(
    read_local_installation_projection(foreign, binding.file, packet)
    is Err(CustodyLost),
  )
  foreign.close().unwrap()
  assert_eq(
    host.database.read("client_local_installation_originals", file).unwrap().body,
    packet,
  )
  assert_true(binding.restore_signing_key_original() is Ok(_))
  host.close().unwrap()
}

///|
test "Local signing missing row reservation or counter stays unavailable and is never backfilled" {
  for damage in ["row", "reservation", "counter"] {
    let (host, file) = signing_original_host(
      "signing-original-missing-" + damage,
    )
    let binding = signing_original_binding(host, file)
    binding.capture_signing_key_original().unwrap() |> ignore
    match damage {
      "row" => {
        let table = b"client_local_installation_originals"
        let key = @utf8.encode(file)
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
            "installation:" + file,
            8192L,
            1L,
          )
          .unwrap(),
        )
      _ =>
        host.database
        .compare_exchange(
          "client_local_installation_custody", "issued", 1L, b"0",
        )
        .unwrap()
        |> ignore
    }
    assert_true(binding.restore_signing_key_original() is Err(_))
    assert_true(binding.capture_signing_key_original() is Err(_))
    if damage == "row" {
      assert_true(
        host.database.read("client_local_installation_originals", file)
        is Err(@sqlite.NotFound),
      )
    }
    host.close().unwrap()
  }
}

///|
test "Local signing byte identical file replacement cannot become the old key generation" {
  let name = "signing-original-generation"
  let (host, file) = signing_original_host(name)
  let binding = signing_original_binding(host, file)
  let original = binding.capture_signing_key_original().unwrap()
  let before = host.database
    .read("client_local_installation_originals", file)
    .unwrap()
  let private_file = name + ".descriptor"
  let root = host.session.source_root
  root
  .reclaim_generation(
    private_file,
    root.inspect_generation(private_file).unwrap().unwrap(),
  )
  .unwrap()
  let writer = root.create_writer(name + ".replacement.stage", 8192L).unwrap()
  writer.append(b"synthetic-file-projection-only").unwrap()
  writer.seal(private_file).unwrap() |> ignore
  assert_true(original.require_current_key() is Err(_))
  assert_true(binding.restore_signing_key_original() is Err(_))
  assert_true(binding.capture_signing_key_original() is Err(_))
  assert_eq(
    host.database.read("client_local_installation_originals", file).unwrap().body,
    before.body,
  )
  assert_eq(host.installation_custody().unwrap().0, 1)
  host.close().unwrap()
}

///|
test "Local signing roles reject same raw32 across differently encoded public originals" {
  for
    (name, public_key, same_file, expected) in [
      (
        "same-key",
        signing_original_public_a.replace_all(old="\\n", new="\\r\\n"),
        false,
        false,
      ),
      ("different-key", signing_original_public_b, false, true),
      ("same-file", signing_original_public_b, true, false),
      ("unknown-key", "invalid-public-key", false, false),
    ] {
    let name = "signing-role-" + name
    let host_file = name + ".host-key.json"
    let reviewer_file = name + ".reviewer-key.json"
    let registration_file = name + ".reviewer.json"
    let host_descriptor = name + ".host-descriptor"
    let reviewer_descriptor = if same_file {
      host_descriptor
    } else {
      name + ".review-descriptor"
    }
    let account_file = name + ".account.json"
    signing_original_write(
      host_file,
      @utf8.encode(signing_original_configuration(host_descriptor, public_key)),
    )
    signing_original_write(
      reviewer_file,
      @utf8.encode(
        signing_original_configuration(
          reviewer_descriptor,
          signing_original_public_a,
          reviewer=true,
        ),
      ),
    )
    signing_original_write(
      registration_file,
      @utf8.encode(
        local_reviewer_selection_wire
        .replace_all(old="\"operator\"", new="\"reviewer\"")
        .replace_all(old="\"cli\"", new="\"review-cli\""),
      ),
    )
    signing_original_write(host_descriptor, b"synthetic-file-projection-only")
    if !same_file {
      signing_original_write(
        reviewer_descriptor, b"synthetic-file-projection-only",
      )
    }
    let account = local_reviewer_account.replace_all(
      old="\"original-client-read\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":[\"read\"]}",
      new="\"original-host-key-sign\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"host-signer\"]},\"connection\":{\"any_of\":[\"host-cli\"]},\"resource\":{\"any_of\":[\"key/host-attestation-2026\"]},\"operation\":{\"any_of\":[\"sign\"]}",
    )
    signing_original_write(account_file, @utf8.encode(account))
    let crypto = @crypto.load_library(
      @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
      diagnostic_ceiling=Some(64),
    ).unwrap()
    let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
    let host = begin_native_local_host_adoption(
        path,
        name + ".host",
        path,
        account_file,
        "operator",
        crypto,
        configuration_files=[host_file, reviewer_file, registration_file],
      )
      .unwrap()
      .open_journal(local_journal_test_library(), crypto, 100.0, 8, 8388608L)
      .unwrap()
    let reviewer = host
      .install_effect_reviewer(configuration_file=Some(registration_file))
      .unwrap()
    let original = host
      .acquire_signing_key_account(
        crypto,
        reviewer_file,
        @checkpoint.EffectSet,
        reviewer=Some(reviewer),
      )
      .unwrap()
      .capture_signing_key_original()
      .unwrap()
    let binding = signing_original_binding(host, host_file)
    let result = binding.capture_signing_key_original()
    assert_eq(result is Ok(_), expected)
    assert_true(original.require_current_key() is Ok(_))
    assert_eq(
      host.installation_custody().unwrap().0,
      if expected {
        2
      } else {
        1
      },
    )
    host.close().unwrap()
  }
}

///|
test "Local signing foreign settings reservation refuses before copying a new original" {
  let (host, file) = signing_original_host("signing-original-capacity")
  let binding = signing_original_binding(host, file)
  assert_true(
    host.database
    .reserve_capacity(
      "client_local_settings", "unrelated", 65536L, 8L, 65536L, 8L,
    )
    .unwrap(),
  )
  assert_true(binding.capture_signing_key_original() is Err(_))
  assert_true(
    host.database.read("client_local_installation_originals", file)
    is Err(@sqlite.NotFound),
  )
  let usage = host.database.capacity_usage("client_local_settings").unwrap()
  assert_eq(usage.reserved_bytes, 65536L)
  assert_eq(usage.reserved_objects, 8L)
  host.close().unwrap()
}

///|
test "Local signing and preparation cannot borrow the same original descriptor in either order" {
  for signing_first in [false, true] {
    let name = if signing_first {
      "signing-shared-first"
    } else {
      "preparation-shared-first"
    }
    let descriptor = name + ".descriptor"
    let signing_file = name + ".signing.json"
    let preparation_file = name + ".preparation.json"
    let provider_file = name + ".provider.json"
    let account_file = name + ".account.json"
    let preparation_wire = "{\"version\":\"actql-config/0.1\",\"native\":{\"preparation_credential\":{\"credential_file\":\"" +
      descriptor +
      "\",\"provider_file\":\"" +
      provider_file +
      "\"}}}"
    signing_original_write(descriptor, b"synthetic-file-projection-only")
    signing_original_write(
      signing_file,
      @utf8.encode(
        signing_original_configuration(descriptor, signing_original_public_a),
      ),
    )
    signing_original_write(preparation_file, @utf8.encode(preparation_wire))
    signing_original_write(
      provider_file,
      @utf8.encode(local_preparation_provider_wire),
    )
    let original_account = @utf8.decode(local_preparation_account(true, true))
    guard original_account.has_suffix("]}") else {
      fail("independent Account fixture changed")
    }
    let signing_entry = "{\"entry_id\":\"original-host-key-sign\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"host-signer\"]},\"connection\":{\"any_of\":[\"host-cli\"]},\"resource\":{\"any_of\":[\"key/host-attestation-2026\"]},\"operation\":{\"any_of\":[\"sign\"]},\"exclusions\":[]}"
    let account = original_account[0:original_account.length() - 2].to_owned() +
      "," +
      signing_entry +
      "]}"
    signing_original_write(account_file, @utf8.encode(account))
    let crypto = @crypto.load_library(
      @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
      diagnostic_ceiling=Some(64),
    ).unwrap()
    let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
    let host = begin_native_local_host_adoption(
        path,
        name + ".host",
        path,
        account_file,
        "operator",
        crypto,
        configuration_files=[signing_file, preparation_file, provider_file],
      )
      .unwrap()
      .open_journal(local_journal_test_library(), crypto, 100.0, 8, 8388608L)
      .unwrap()
    let selected = host.session.settings.files
      .iter()
      .find_first(file => file.name == preparation_file)
      .unwrap()
    let provider = host.session.settings.files
      .iter()
      .find_first(file => file.name == provider_file)
      .unwrap()
    let preparation = local_preparation_installation_selection(selected.body).unwrap()
    let signing = signing_original_binding(host, signing_file)
    if signing_first {
      signing.capture_signing_key_original().unwrap() |> ignore
      assert_true(
        local_installation_test_original(
          host, selected, provider, preparation, true,
        )
        is Err(ChangedIntent),
      )
    } else {
      local_installation_test_original(
        host, selected, provider, preparation, true,
      ).unwrap()
      |> ignore
      assert_true(
        signing.capture_signing_key_original()
        is Err(SigningJournal(ChangedIntent)),
      )
    }
    assert_eq(host.installation_custody().unwrap().0, 1)
    assert_eq(
      host.database.capacity_usage("client_local_settings").unwrap().reserved_bytes,
      8192L,
    )
    host.close().unwrap()
  }
}

///|
test "legacy authenticated signing row remains immutable and cannot recapture public identity" {
  // Fresh disposable fixture only. Build the historical six-field original
  // through the existing HMAC/counter/capacity transaction, without signing.
  let (host, file) = signing_original_host(
    "signing-original-legacy-public-missing",
  )
  let binding = signing_original_binding(host, file)
  let (_, _, _, _, _, _, private_file, _) = @credential_resource.native_local_signing_key_selection_projection(
    binding.selection,
  )
  let projection = host.session.source_root
    .adopt_private_file_projection(private_file)
    .unwrap()
    .export_original()
    .unwrap()
  let payload = local_adoption_record([
    ("adoption_cid", host.adoption_cid),
    ("authority_scope_cid", binding.scope),
    ("installation_configuration_cid", binding.file.content_cid),
    ("projection", @base64.encode(projection)),
    ("purpose", "host_attestation"),
    ("version", "actql-native-local-installation-original/0.1"),
  ]).unwrap()
  let packet = local_installation_packet(host, payload).unwrap()
  host.journal
  .transaction(() => {
    try {
      let (count, revision) = local_signing_installation_value(
        host.installation_custody().map_err(_ => CustodyLost),
      )
      if count != 0 {
        return Err(CustodyLost)
      }
      if !local_signing_installation_value(
          host.database
          .reserve_capacity_in_transaction(
            "client_local_settings",
            "installation:" + file,
            8192L,
            1L,
            65536L,
            8L,
          )
          .map_err(issue => Physical(issue)),
        ) {
        return Err(CustodyLost)
      }
      local_signing_installation_value(
        host.database
        .insert("client_local_installation_originals", file, packet)
        .map_err(issue => Physical(issue)),
      )
      |> ignore
      local_signing_installation_value(
        host.database
        .compare_exchange(
          "client_local_installation_custody", "issued", revision, b"1",
        )
        .map_err(issue => Physical(issue)),
      )
      |> ignore
      Ok(())
    } catch {
      LocalInstallationJournalStop(issue) => Err(issue)
    }
  })
  .unwrap()
  assert_eq(host.installation_custody().unwrap().0, 1)
  assert_eq(
    read_local_installation_projection(host, binding.file, packet).unwrap(),
    projection,
  )
  assert_true(
    binding.restore_signing_key_original() is Err(SigningOriginalUnavailable),
  )
  assert_true(
    binding.capture_signing_key_original() is Err(SigningOriginalUnavailable),
  )
  let retained = host.database
    .read("client_local_installation_originals", file)
    .unwrap()
  assert_eq(retained.revision, 0L)
  assert_eq(retained.body, packet)
  assert_eq(host.installation_custody().unwrap().0, 1)
  let usage = host.database.capacity_usage("client_local_settings").unwrap()
  assert_eq(usage.reserved_bytes, 8192L)
  assert_eq(usage.reserved_objects, 1L)
  host.close().unwrap()
}
