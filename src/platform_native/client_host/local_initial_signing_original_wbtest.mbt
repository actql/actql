///|
fn initial_signing_original_fixture(
  name : String,
) -> NativeLocalHostConnection raise {
  let (_, _, session, crypto) = initial_signing_fixture(name)
  let material = session.create_initial_signing_material(crypto).unwrap()
  session
  .open_journal_with_initial_signing_material(
    material,
    @host.client_local_default_signing_bootstrap_policy(),
    local_journal_test_library(),
    crypto,
    100.0,
    8,
    8388608L,
  )
  .unwrap()
}

///|
test "initial Signing original commits same Store key policy and intent without an extra row or use" {
  let host = initial_signing_original_fixture("initial-original-first")
  let original = host.restore_initial_signing_original().unwrap()
  let policy = original.policy().unwrap()
  assert_eq(
    original.issuer_identity().unwrap(),
    "local-signing/" + host.session.intent_cid(),
  )
  assert_eq(policy.max_uses(), 1)
  let pem = host.epoch.crypto
    .ed25519_public_key_raw32(original.public_key_pem)
    .unwrap()
  assert_eq(original.public_key().unwrap().raw32().unwrap(), pem)
  let control = host.database
    .read("client_local_installation_custody", "host")
    .unwrap()
  assert_true(control.body != host.adoption_body && control.revision == 0L)
  assert_eq(host.installation_custody().unwrap(), (0, 0L))
  assert_true(
    host.database.scan_after("client_local_installation_originals", "")
    is Err(@sqlite.NotFound),
  )
  let usage = host.database.capacity_usage("client_local_settings").unwrap()
  assert_true(usage.reserved_bytes == 0L && usage.reserved_objects == 0L)
  assert_true(
    host.database.scan_after("client_local_installation_custody", "issued")
    is Err(@sqlite.NotFound),
  )
  assert_eq(
    host.database.read("client_local_adoption", "adoption").unwrap().body,
    host.adoption_body,
  )
  assert_true(control.body.length() <= 8192)
  host.close().unwrap()
  assert_true(original.require_current() is Err(Closed))
}

///|
test "initial Signing original cold restore keeps exact epoch key control and physical generation" {
  let host = initial_signing_original_fixture("initial-original-reopen")
  let original = host.restore_initial_signing_original().unwrap()
  let public_cid = original.public_key().unwrap().cid()
  let control = host.database
    .read("client_local_installation_custody", "host")
    .unwrap().body
  let epoch = host.database
    .read("client_submission_epoch", "authority")
    .unwrap().body
  let generation = host.session.root
    .inspect_generation("local-signing-key.pem")
    .unwrap()
  let parent = host.session.source_root
  let path = host.session.state_path
  // State is a child of this independently owned fixture parent.
  let top = path[:path.length() - "/initial-original-reopen.host".length()].to_owned()
  let source = host.session.source_name
  let crypto = host.epoch.crypto
  host.close().unwrap()
  let _ = parent
  let reopened = begin_native_local_host_adoption(
    top,
    "initial-original-reopen.host",
    top,
    source,
    "operator",
    crypto,
    existing_only=true,
  ).unwrap()
  assert_true(reopened.create_initial_signing_material(crypto) is Err(_))
  let restored = reopened
    .open_journal(local_journal_test_library(), crypto, 100.0, 8, 8388608L)
    .unwrap()
  assert_eq(
    restored
    .restore_initial_signing_original()
    .unwrap()
    .public_key()
    .unwrap()
    .cid(),
    public_cid,
  )
  assert_eq(
    restored.database.read("client_local_installation_custody", "host").unwrap().body,
    control,
  )
  assert_eq(
    restored.database.read("client_submission_epoch", "authority").unwrap().body,
    epoch,
  )
  assert_eq(
    restored.session.root.inspect_generation("local-signing-key.pem").unwrap(),
    generation,
  )
  restored.close().unwrap()
}

///|
test "initial Signing legacy host custody never backfills a current key or policy" {
  let (_, _, session, crypto) = initial_signing_fixture(
    "initial-original-legacy",
  )
  let material = session.create_initial_signing_material(crypto).unwrap()
  let host = session
    .open_journal(local_journal_test_library(), crypto, 100.0, 8, 8388608L)
    .unwrap()
  let prior = host.database
    .read("client_local_installation_custody", "host")
    .unwrap()
  assert_eq(prior.body, host.adoption_body)
  assert_true(host.restore_initial_signing_original() is Err(_))
  assert_true(
    session.open_journal_with_initial_signing_material(
      material,
      @host.client_local_default_signing_bootstrap_policy(),
      local_journal_test_library(),
      crypto,
      100.0,
      8,
      8388608L,
    )
    is Err(AmbiguousInitialization),
  )
  let retained = host.database
    .read("client_local_installation_custody", "host")
    .unwrap()
  assert_eq(retained.body, prior.body)
  assert_eq(retained.revision, prior.revision)
  assert_eq(host.installation_custody().unwrap(), (0, 0L))
  host.close().unwrap()
}

///|
test "initial Signing foreign material refuses before journal creation and authenticated fields remain closed" {
  let (_, _, owner, crypto) = initial_signing_fixture("initial-original-owner")
  let material = owner.create_initial_signing_material(crypto).unwrap()
  let (_, _, foreign, _) = initial_signing_fixture("initial-original-foreign")
  assert_true(
    foreign.open_journal_with_initial_signing_material(
      material,
      @host.client_local_default_signing_bootstrap_policy(),
      local_journal_test_library(),
      crypto,
      100.0,
      8,
      8388608L,
    )
    is Err(CustodyLost),
  )
  assert_eq(foreign.root.inspect_generation("client.sqlite3").unwrap(), None)
  assert_true(foreign.close())
  let host = owner
    .open_journal_with_initial_signing_material(
      material,
      @host.client_local_default_signing_bootstrap_policy(),
      local_journal_test_library(),
      crypto,
      100.0,
      8,
      8388608L,
    )
    .unwrap()
  let body = host.database
    .read("client_local_installation_custody", "host")
    .unwrap().body
  let header = local_adoption_fields(body, [
    "adoption_body", "initial_signing_original", "initial_host_attestation_original",
  ]).unwrap()
  let packet = @base64.decode(header[1])
  let payload = read_local_installation_authenticated_payload(host, packet).unwrap()
  let keys = [
    "adoption_cid", "initialization_intent_cid", "issuer_authority", "key_file",
    "key_projection", "policy_cid", "policy_original", "public_key_cid", "public_key_original",
    "public_key_pem", "purpose", "root_role", "version",
  ]
  let fields = local_adoption_fields(payload, keys).unwrap()
  // Keep this independent old Native vector: the physical initializer's new
  // typed writer and restore reader must preserve the original payload bytes.
  assert_eq(
    local_adoption_record(keys.mapi((i, key) => (key, fields[i]))).unwrap(),
    payload,
  )
  let typed = @host.read_client_local_initial_signing_payload(payload).unwrap()
  assert_eq(
    @host.client_local_initial_signing_payload_body(typed).unwrap(),
    payload,
  )
  assert_eq(typed.adoption_cid, host.adoption_cid)
  assert_eq(typed.initialization_intent_cid, host.session.intent_cid)
  assert_eq(typed.key_projection, fields[4])
  assert_eq(typed.public_key_pem, fields[9])
  // Authenticate each changed candidate with this real epoch only to isolate
  // independent binding rejection from the separate HMAC refusal below.
  for index in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] {
    let changed = local_adoption_record(
      keys.mapi((i, key) => {
        (key, if i == index { fields[i] + "x" } else { fields[i] })
      }),
    ).unwrap()
    let signed = local_installation_packet(host, changed).unwrap()
    let candidate = local_adoption_record([
      ("adoption_body", header[0]),
      ("initial_signing_original", @base64.encode(signed)),
    ]).unwrap()
    if read_local_initial_signing_control(host, candidate) is Ok(_) {
      fail("changed initial Signing field admitted: " + keys[index])
    }
  }
  for
    pem in [
      fields[9] + "x",
      fields[9].replace_all(old="\n", new="\r\n"),
      fields[9][:fields[9].length() - 1].to_owned() + "x",
    ] {
    assert_false(valid_initial_signing_public_pem(pem))
  }
  assert_true(valid_initial_signing_public_pem(fields[9]))
  let envelope = local_adoption_fields(packet, ["payload", "tag"]).unwrap()
  let tampered = local_adoption_record([
    ("payload", @base64.encode(b"changed")),
    ("tag", envelope[1]),
  ]).unwrap()
  let candidate = local_adoption_record([
    ("adoption_body", header[0]),
    ("initial_signing_original", @base64.encode(tampered)),
  ]).unwrap()
  assert_true(read_local_initial_signing_control(host, candidate) is Err(_))
  assert_true(host.restore_initial_signing_original() is Ok(_))
  host.close().unwrap()
}

///|
test "initial Signing commit response loss preserves same original or missing refusal without recapture" {
  for lost in [false, true] {
    let (path, source, session, crypto) = initial_signing_fixture(
      "initial-original-unknown-" + lost.to_string(),
    )
    let material = session.create_initial_signing_material(crypto).unwrap()
    let (ownership, adoption) = session.prepare_journal_file(crypto).unwrap()
    local_adoption_write(session.root, "journal-initializing.json", adoption).unwrap()
    |> ignore
    let capture = session
      .prepare_initial_signing_capture(
        material,
        @host.client_local_default_signing_bootstrap_policy(),
        crypto,
        adoption,
      )
      .unwrap()
    let database = local_journal_test_library()
      .initialize_owned_database(
        session.state_path + "/client.sqlite3",
        ownership,
        131072L,
      )
      .unwrap()
    if lost {
      client_test_fail_commit_reply(database, 1)
    } else {
      client_test_fail_commit(database, 1)
    }
    assert_true(
      initialize_native_local_client_custody(
        database,
        crypto,
        adoption,
        settings=Some(session.settings),
        initial_signing=Some(capture),
      )
      is Err(TransactionUnknown),
    )
    assert_true(database.transaction_fenced())
    assert_true(
      initialize_native_local_client_custody(
        database,
        crypto,
        adoption,
        initial_signing=Some(capture),
      )
      is Err(Fenced),
    )
    if !lost {
      database.rollback().unwrap()
    }
    database.close_checked().unwrap()
    assert_true(session.close())
    let reopened = begin_native_local_host_adoption(
      path,
      "initial-original-unknown-" + lost.to_string() + ".host",
      path,
      source,
      "operator",
      crypto,
      existing_only=true,
    ).unwrap()
    assert_true(reopened.create_initial_signing_material(crypto) is Err(_))
    let result = reopened.open_journal(
      local_journal_test_library(),
      crypto,
      100.0,
      8,
      8388608L,
    )
    if lost {
      let host = result.unwrap()
      let original = host.restore_initial_signing_original().unwrap()
      assert_eq(
        original.issuer_identity().unwrap(),
        "local-signing/" + reopened.intent_cid(),
      )
      assert_eq(host.installation_custody().unwrap(), (0, 0L))
      host.close().unwrap()
    } else {
      match result {
        Ok(host) => {
          host.close().unwrap()
          fail("rolled-back initialization was repaired")
        }
        Err(DatabasePending(database, _)) => database.close_checked().unwrap()
        Err(_) => ()
      }
      assert_true(reopened.close())
    }
  }
}

///|
test "initial Signing packet keeps exact existing payload bound and changed control never stays current" {
  let host = initial_signing_original_fixture("initial-original-bounds")
  let original = host.restore_initial_signing_original().unwrap()
  let exact = @utf8.encode("p".repeat(2048))
  let packet = local_installation_packet(host, exact).unwrap()
  assert_eq(
    read_local_installation_authenticated_payload(host, packet).unwrap(),
    exact,
  )
  assert_true(
    read_local_installation_authenticated_payload(
      host,
      local_installation_packet(host, @utf8.encode("p".repeat(2049))).unwrap(),
    )
    is Err(CustodyLost),
  )
  let row = host.database
    .read("client_local_installation_custody", "host")
    .unwrap()
  host.database
  .compare_exchange(
    "client_local_installation_custody",
    "host",
    row.revision,
    row.body,
  )
  .unwrap()
  |> ignore
  assert_true(original.require_current() is Err(CustodyLost))
  assert_true(host.restore_initial_signing_original() is Err(_))
  host.close().unwrap()
}

///|
test "initial Signing original rejects identical replacement file and foreign epoch without rewriting custody" {
  let host = initial_signing_original_fixture("initial-original-replaced")
  let original = host.restore_initial_signing_original().unwrap()
  let row = host.database
    .read("client_local_installation_custody", "host")
    .unwrap()
  let root = host.session.root
  let (private_key, generation) = local_adoption_read(
    root, "local-signing-key.pem", 119L,
  ).unwrap()
  root.reclaim_generation("local-signing-key.pem", generation).unwrap()
  let writer = root.create_writer("replacement-key.stage", 119L).unwrap()
  writer.append(private_key).unwrap()
  writer.seal("local-signing-key.pem").unwrap() |> ignore
  assert_true(original.require_current() is Err(_))
  assert_true(host.restore_initial_signing_original() is Err(Filesystem(_)))
  assert_eq(
    host.database.read("client_local_installation_custody", "host").unwrap().body,
    row.body,
  )
  host.close().unwrap()
  let other = initial_signing_original_fixture("initial-original-epoch")
  let original = other.restore_initial_signing_original().unwrap()
  let foreign = initial_signing_original_fixture("initial-original-other-epoch")
  let epoch = foreign.database
    .read("client_submission_epoch", "authority")
    .unwrap().body
  let own = other.database.read("client_submission_epoch", "authority").unwrap()
  other.database
  .compare_exchange("client_submission_epoch", "authority", own.revision, epoch)
  .unwrap()
  |> ignore
  assert_true(original.require_current() is Err(_))
  assert_true(other.restore_initial_signing_original() is Err(_))
  foreign.close().unwrap()
  other.close().unwrap()
}
