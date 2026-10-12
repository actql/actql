///|
// Definitions for the existing physical Native fixture. Until a matching
// diagnostic executes them, compiler success establishes no restart/ACK result.
fn policy_upgrade_host_fixture(
  name : String,
  existing? : Bool = false,
) -> NativeLocalHostConnection {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let names = [name + ".read", name + ".run", name + ".keep", name + ".store"]
  let account = name + ".account"
  if !existing {
    let originals = @host.client_local_product_originals(
      root,
      "/fixture/sqlite.dylib",
      "/fixture/crypto.dylib",
      "2026-10-12T00:00:00.000Z",
      @host.client_local_product_assets(),
    ).unwrap()
    let parent = @filesystem.open_private_root(root).unwrap()
    for
      (file, key) in [
        (account, "account.json"),
        (names[0], "read.json"),
        (names[1], "run.json"),
        (names[2], "retention.json"),
        (names[3], "store.json"),
      ] {
      let body = originals.iter().find_first(pair => pair.0 == key).unwrap().1
      let writer = parent.create_writer(file + ".stage", 65536L).unwrap()
      writer.append(body).unwrap()
      writer.seal(file).unwrap() |> ignore
    }
  }
  begin_native_local_host_adoption(
    root,
    name + ".host",
    root,
    account,
    "local-cli",
    epoch_test_crypto(),
    existing_only=existing,
    configuration_files=names,
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
fn policy_upgrade_test_append(
  host : NativeLocalHostConnection,
  name : String,
  operation? : String = "explicit-upgrade",
) -> Result[NativeLocalPolicyUpgradeReceipt, NativeClientRunJournalIssue] {
  host.upgrade_run_policy(
    epoch_test_crypto(),
    "local-cli",
    "local",
    operation,
    name + ".read",
    name + ".run",
    name + ".keep",
    name + ".store",
  )
}

///|
test "Native upgrade repeats and reopens one append without changing original adoption or files" {
  let name = "legacy-upgrade-reopen"
  let host = policy_upgrade_host_fixture(name)
  let adopted = host.adoption_body
  let files = host.session.settings.files.map(file => {
    (file.name, file.body, file.generation)
  })
  let first = policy_upgrade_test_append(host, name).unwrap()
  let packet = host.database
    .read("client_local_installation_originals", local_policy_upgrade_key)
    .unwrap()
  let repeated = policy_upgrade_test_append(host, name).unwrap()
  assert_eq(first.original_cid, repeated.original_cid)
  assert_eq(first.profile_cid, repeated.profile_cid)
  assert_eq(
    host.database.read("client_local_installation_custody", "issued").unwrap().body,
    b"1",
  )
  assert_eq(
    host.database.capacity_usage("client_local_settings").unwrap().reserved_bytes,
    8192L,
  )
  assert_eq(
    host.database.capacity_usage("client_local_settings").unwrap().reserved_objects,
    1L,
  )
  assert_eq(host.adoption_body, adopted)
  assert_eq(
    host.session.settings.files.map(file => {
      (file.name, file.body, file.generation)
    }),
    files,
  )
  host.close().unwrap()
  let reopened = policy_upgrade_host_fixture(name, existing=true)
  let restored = reopened
    .lookup_run_policy_upgrade(
      epoch_test_crypto(),
      "local-cli",
      "local",
      "explicit-upgrade",
    )
    .unwrap()
    .unwrap()
  assert_eq(restored.original_cid, first.original_cid)
  let row = reopened.database
    .read("client_local_installation_originals", local_policy_upgrade_key)
    .unwrap()
  assert_eq(row.body, packet.body)
  assert_eq(row.revision, packet.revision)
  assert_eq(reopened.adoption_body, adopted)
  assert_true(reopened.with_installation_custody(() => Ok(())) is Ok(_))
  reopened.close().unwrap()
}

///|
test "Native upgrade exact lookup rejects a different operation scope or selected roles" {
  let name = "legacy-upgrade-intent"
  let host = policy_upgrade_host_fixture(name)
  policy_upgrade_test_append(host, name).unwrap() |> ignore
  let before = host.database
    .read("client_local_installation_originals", local_policy_upgrade_key)
    .unwrap()
  assert_true(
    policy_upgrade_test_append(host, name, operation="another-upgrade")
    is Err(ChangedIntent),
  )
  assert_true(
    host.upgrade_run_policy(
      epoch_test_crypto(),
      "local-cli",
      "local",
      "explicit-upgrade",
      name + ".read",
      name + ".run",
      name + ".store",
      name + ".keep",
    )
    is Err(ChangedIntent),
  )
  assert_true(
    host.lookup_run_policy_upgrade(
      epoch_test_crypto(),
      "local-cli",
      "local",
      "another-upgrade",
    )
    is Err(ChangedIntent),
  )
  assert_true(
    host.lookup_run_policy_upgrade(
      epoch_test_crypto(),
      "foreign",
      "local",
      "explicit-upgrade",
    )
    is Err(_),
  )
  assert_eq(
    host.database
    .read("client_local_installation_originals", local_policy_upgrade_key)
    .unwrap().body,
    before.body,
  )
  assert_eq(
    host.database.read("client_local_installation_custody", "issued").unwrap().body,
    b"1",
  )
  host.close().unwrap()
}

///|
test "Native missing upgrade reservation fails lookup without repair or second append" {
  let name = "legacy-upgrade-reservation"
  let host = policy_upgrade_host_fixture(name)
  policy_upgrade_test_append(host, name).unwrap() |> ignore
  let before = host.database
    .read("client_local_installation_originals", local_policy_upgrade_key)
    .unwrap()
  assert_true(
    host.database.release_capacity(
      "client_local_settings",
      "installation:" + local_policy_upgrade_key,
      8192L,
      1L,
    )
    is Ok(true),
  )
  assert_true(
    host.lookup_run_policy_upgrade(
      epoch_test_crypto(),
      "local-cli",
      "local",
      "explicit-upgrade",
    )
    is Err(CustodyLost),
  )
  assert_eq(
    host.database.capacity_usage("client_local_settings").unwrap().reserved_bytes,
    0L,
  )
  assert_true(policy_upgrade_test_append(host, name) is Err(CustodyLost))
  assert_eq(
    host.database.capacity_usage("client_local_settings").unwrap().reserved_objects,
    0L,
  )
  assert_eq(
    host.database
    .read("client_local_installation_originals", local_policy_upgrade_key)
    .unwrap().body,
    before.body,
  )
  host.close().unwrap()
}

///|
test "Native journal records actual transaction ownership and refuses nested mutations" {
  let name = "legacy-upgrade-transaction"
  let host = policy_upgrade_host_fixture(name)
  assert_false(host.journal.transaction_active)
  let active = Ref(false)
  let readonly_joined = Ref(false)
  let mutation_refused = Ref(false)
  let stopped : Result[Unit, NativeClientRunJournalIssue] = host.journal.transaction(() => {
      active.val = host.journal.transaction_active
      readonly_joined.val = host.with_installation_custody(() => Ok(()))
        is Ok(_)
      mutation_refused.val = host.journal.transaction(() => Ok(()))
        is Err(Physical(@sqlite.Busy))
      Err(ChangedIntent)
    },
  )
  assert_true(active.val)
  assert_true(readonly_joined.val)
  assert_true(mutation_refused.val)
  assert_true(stopped is Err(ChangedIntent))
  assert_false(host.journal.transaction_active)
  assert_true(host.with_installation_custody(() => Ok(())) is Ok(_))
  assert_eq(
    host.database.capacity_usage("client_local_settings").unwrap().reserved_bytes,
    0L,
  )
  host.close().unwrap()
}

///|
test "Native upgrade packet cannot borrow another envelope role changed tag or oversized payload" {
  let name = "legacy-upgrade-packet"
  let host = policy_upgrade_host_fixture(name)
  policy_upgrade_test_append(host, name).unwrap() |> ignore
  let row = host.database
    .read("client_local_installation_originals", local_policy_upgrade_key)
    .unwrap()
  let fields = @host.client_local_original_record_fields(row.body, [
    "payload_head", "payload_tail", "tag",
  ]).unwrap()
  let changed = @host.client_local_original_record_body([
    ("payload_head", fields[0]),
    ("payload_tail", fields[1]),
    ("tag", "0".repeat(64)),
  ]).unwrap()
  assert_true(local_policy_upgrade_payload(host, changed) is Err(CustodyLost))
  assert_true(
    local_policy_upgrade_payload(host, b"{\"payload\":\"\",\"tag\":\"\"}")
    is Err(CustodyLost),
  )
  assert_true(
    local_policy_upgrade_packet(host, Bytes::make(5633, 0))
    is Err(CapacityExceeded),
  )
  assert_eq(
    host.database
    .read("client_local_installation_originals", local_policy_upgrade_key)
    .unwrap().body,
    row.body,
  )
  host.close().unwrap()
}

///|
test "Native upgrade binds old accepted Run facts and never fills a missing finite packet" {
  let name = "legacy-upgrade-old-run"
  let host = policy_upgrade_host_fixture(name)
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("local-cli", "local", crypto).unwrap()
  let epoch = host.epoch.issue_epoch(scope, true, 1000.0).unwrap()
  let reference = prepare_native_client_submission_reference(
    epoch, "old-request",
  ).unwrap()
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    preparation_values_document() +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let preparation = submitted_prepare(intent).unwrap()
  guard preparation.preparation is Computation(prepared) else {
    fail("ordinary input")
  }
  let (request, _, compiled, definition) = journal_test_prepared_run(
    prepared,
    reference.request_id,
    "old-run",
    scope~,
  )
  host.journal
  .record_submitted_intent(host.epoch, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  let accepted = host.journal
    .accept_submitted_run(
      host.epoch,
      reference,
      preparation,
      request,
      compiled,
      definition,
      scope,
      true,
      1001.0,
    )
    .unwrap()
  let before = host.journal.retained(request).unwrap().unwrap()
  policy_upgrade_test_append(host, name).unwrap() |> ignore
  let policy = host
    .bind_upgraded_run_policy(
      crypto,
      "local-cli",
      "local",
      name + ".read",
      name + ".run",
    )
    .unwrap()
    .unwrap()
  assert_true(policy.original_run_requires_finite_policy(request) is Ok(false))
  let after = host.journal.retained(request).unwrap().unwrap()
  assert_eq(run_record_body(before).unwrap(), run_record_body(after).unwrap())
  assert_true(after.local_run_policy_originals is None)
  assert_eq(
    host.journal.retained_submission(reference).unwrap().unwrap().run_admission.unwrap().revision,
    accepted.run_admission.unwrap().revision,
  )
  // A later Run lacking a packet is not in the immutable accepted legacy set.
  let (foreign, prepared, compiled, definition) = journal_test_run(
    "unproven-request",
    "unproven-run",
    scope~,
  )
  host.journal.bind_run(foreign, prepared, compiled, definition, true).unwrap()
  |> ignore
  assert_true(
    policy.original_run_requires_finite_policy(foreign) is Err(CustodyLost),
  )
  assert_true(
    host.journal.retained(foreign).unwrap().unwrap().local_run_policy_originals
    is None,
  )
  host.close().unwrap()
}
