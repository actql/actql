///|
fn historical_upgrade_test_manifest(
  wire? : String = historical_upgrade_test_a3b_runtime(),
) -> @host.ClientNativeLocalRuntime {
  @host.admit_client_native_local_runtime(
    wire,
    "a3b1643fbedc5180db38b6e08459a188f05b1135",
    "darwin-arm64",
    @sha.hex(@utf8.encode(wire)),
  ).unwrap()
}

///|
fn historical_upgrade_test_host(
  name : String,
  runtime_wire? : String = historical_upgrade_test_old_runtime(),
  existing? : Bool = false,
) -> NativeLocalHostConnection {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let names = [
    name + ".read",
    name + ".run",
    name + ".keep",
    name + ".store",
    name + ".runtime",
  ]
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
    let writer = parent.create_writer(names[4] + ".stage", 65536L).unwrap()
    writer.append(@utf8.encode(runtime_wire)).unwrap()
    writer.seal(names[4]).unwrap() |> ignore
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
// Issue only a fresh test candidate from a genuine old fifteen-key original.
// The runtime alternative is deliberately not inserted, so the normal row,
// issued counter, reservation and ordinary lookup stay on their strict path.
fn historical_upgrade_test_candidate(
  host : NativeLocalHostConnection,
  name : String,
) -> @sqlite.NativeJournalValue {
  policy_upgrade_test_append(host, name).unwrap() |> ignore
  let row = host.database
    .read("client_local_installation_originals", local_policy_upgrade_key)
    .unwrap()
  let original = read_local_policy_upgrade_original(host, row).unwrap()
  let old = @host.admit_client_native_local_runtime(
    historical_upgrade_test_old_runtime(),
    "109564ef9a4f8241096292843b875d4c81fbb6f3",
    "darwin-arm64",
    "80731853b15f4d600ef391b3778c734bc40bfb6caed246c0c145916b419e49bd",
  ).unwrap()
  let pair = @host.restore_client_native_local_historical_scalar_runtime_pair_metadata(
    historical_upgrade_test_pair_body(),
    old,
    historical_upgrade_test_manifest(),
  ).unwrap()
  let runtime = @host.bind_client_local_runtime_policy_upgrade(
    original.original,
    pair,
  ).unwrap()
  let packet = local_policy_upgrade_packet(
    host,
    @host.client_local_runtime_policy_upgrade_body(runtime),
  ).unwrap()
  { body: packet, revision: 0L, }
}

///|
fn historical_upgrade_test_read(
  host : NativeLocalHostConnection,
  name : String,
  row : @sqlite.NativeJournalValue,
  manifest? : @host.ClientNativeLocalRuntime = historical_upgrade_test_manifest(),
  runtime_file? : String = name + ".runtime",
) -> Result[NativeLocalPolicyUpgradeOriginal, NativeClientRunJournalIssue] {
  read_local_historical_runtime_upgrade_original(
    host, row, "local-cli", "local", runtime_file, manifest,
  )
}

///|
test "historical dependency validates authenticated candidate without changing strict stored lookup" {
  let name = "historical-dependency-exact"
  let host = historical_upgrade_test_host(name)
  let candidate = historical_upgrade_test_candidate(host, name)
  let stored = host.database
    .read("client_local_installation_originals", local_policy_upgrade_key)
    .unwrap()
  let before = host.adoption_body
  let files = host.session.settings.files.map(file => {
    (file.name, file.content_cid, file.generation)
  })
  let result = historical_upgrade_test_read(host, name, candidate)
  let strict = read_local_policy_upgrade_original(host, candidate)
  let stored_result = historical_upgrade_test_read(host, name, stored)
  let unchanged = host.database
    .read("client_local_installation_originals", local_policy_upgrade_key)
    .unwrap().body ==
    stored.body &&
    host.database.read("client_local_installation_custody", "issued").unwrap().body ==
    b"1" &&
    host.database.capacity_usage("client_local_settings").unwrap().reserved_bytes ==
    8192L &&
    host.adoption_body == before &&
    host.session.settings.files.map(file => {
      (file.name, file.content_cid, file.generation)
    }) ==
    files
  host.close().unwrap()
  let original = result.unwrap()
  assert_eq(original.packet, candidate.body)
  assert_eq(original.operation_id, "explicit-upgrade")
  assert_true(strict is Err(CustodyLost))
  assert_true(stored_result is Err(UnsupportedPreparation))
  assert_true(unchanged)
}

///|
test "historical dependency rejects packet revision HMAC changed pair and malformed authenticated body" {
  let name = "historical-dependency-auth"
  let host = historical_upgrade_test_host(name)
  let candidate = historical_upgrade_test_candidate(host, name)
  let payload = local_policy_upgrade_payload(host, candidate.body).unwrap()
  let text = @utf8.decode(payload)
  let fields = @host.client_local_original_record_fields(candidate.body, [
    "payload_head", "payload_tail", "tag",
  ]).unwrap()
  let broken_hmac = @host.client_local_original_record_body([
    ("payload_head", fields[0]),
    ("payload_tail", fields[1]),
    ("tag", "0".repeat(64)),
  ]).unwrap()
  let wrong_revision = historical_upgrade_test_read(host, name, {
      body: candidate.body,
      revision: 1L,
    })
    is Err(CustodyLost)
  let wrong_hmac = historical_upgrade_test_read(host, name, {
      body: broken_hmac,
      revision: 0L,
    })
    is Err(CustodyLost)
  let mut rejected = true
  for
    changed in [
      text.replace(old="2b06a81d", new="3b06a81d") + " ",
      text.replace(old="8bdf4835", new="9bdf4835"),
      text.replace(old="{", new="{\"unrecognized\":\"x\","),
      text.replace(old="authority_scope_cid", new="foreign_scope_cid"),
    ] {
    let packet = local_policy_upgrade_packet(host, @utf8.encode(changed)).unwrap()
    rejected = rejected &&
      historical_upgrade_test_read(host, name, { body: packet, revision: 0L, })
      is Err(CustodyLost)
  }
  host.close().unwrap()
  assert_true(wrong_revision && wrong_hmac && rejected)
}

///|
test "historical dependency refuses foreign selected manifest role and missing original without search" {
  let name = "historical-dependency-original"
  let host = historical_upgrade_test_host(name)
  let candidate = historical_upgrade_test_candidate(host, name)
  let missing = historical_upgrade_test_read(
      host,
      name,
      candidate,
      runtime_file="unselected.runtime",
    )
    is Err(CustodyLost)
  let wrong_role = historical_upgrade_test_read(
      host,
      name,
      candidate,
      runtime_file=name + ".read",
    )
    is Err(CustodyLost)
  let changed = historical_upgrade_test_manifest(
    wire=historical_upgrade_test_a3b_runtime().replace(old="5585", new="5586"),
  )
  let changed_asset = historical_upgrade_test_read(
      host,
      name,
      candidate,
      manifest=changed,
    )
    is Err(CustodyLost)
  host.close().unwrap()
  assert_true(missing && wrong_role && changed_asset)
}

///|
test "historical dependency refuses a selected current manifest in place of the adopted old original" {
  let name = "historical-dependency-substituted"
  let host = historical_upgrade_test_host(
    name,
    runtime_wire=historical_upgrade_test_a3b_runtime(),
  )
  let candidate = historical_upgrade_test_candidate(host, name)
  let result = historical_upgrade_test_read(host, name, candidate)
  host.close().unwrap()
  assert_true(result is Err(CustodyLost))
}

///|
test "historical dependency preserves original scope adoption and closed Host fences" {
  let name = "historical-dependency-current"
  let host = historical_upgrade_test_host(name)
  let candidate = historical_upgrade_test_candidate(host, name)
  let payload = local_policy_upgrade_payload(host, candidate.body).unwrap()
  let foreign_adoption = @utf8.decode(payload).replace(
    old=host.adoption_cid,
    new="sha256:" + "0".repeat(64),
  )
  let packet = local_policy_upgrade_packet(host, @utf8.encode(foreign_adoption)).unwrap()
  let adoption = historical_upgrade_test_read(host, name, {
      body: packet,
      revision: 0L,
    })
    is Err(CustodyLost)
  let scope = host
    .authority_scope_cid("local-cli", "local", epoch_test_crypto())
    .unwrap()
  let foreign_scope = @utf8.decode(payload).replace(
    old=scope,
    new="sha256:" + "0".repeat(64),
  )
  let packet = local_policy_upgrade_packet(host, @utf8.encode(foreign_scope)).unwrap()
  let scope_refused = historical_upgrade_test_read(host, name, {
      body: packet,
      revision: 0L,
    })
    is Err(CustodyLost)
  host.close().unwrap()
  let closed = historical_upgrade_test_read(host, name, candidate) is Err(_)
  assert_true(adoption && scope_refused && closed)
}
