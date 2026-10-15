///|
fn runtime_upgrade_dependency_fixture(
  name : String,
) -> (NativeLocalHostConnection, @sqlite.NativeJournalValue) {
  let host = policy_upgrade_host_fixture(name)
  policy_upgrade_test_append(host, name).unwrap() |> ignore
  let row = host.database
    .read("client_local_installation_originals", local_policy_upgrade_key)
    .unwrap()
  (host, row)
}

///|
test "runtime dependency seam preserves ordinary original bytes without consulting a pair" {
  let (host, row) = runtime_upgrade_dependency_fixture("dependency-absolute")
  let calls = Ref(0)
  let original = read_local_policy_upgrade_original_with_runtime_dependency(
    host,
    row,
    (_, _) => {
      calls.val += 1
      Err(UnsupportedPreparation)
    },
  ).unwrap()
  let strict = read_local_policy_upgrade_original(host, row).unwrap()
  assert_eq(calls.val, 0)
  assert_eq(original.body, strict.body)
  assert_eq(original.packet, row.body)
  assert_eq(original.operation_id, "explicit-upgrade")
  let observed = local_policy_upgrade_receipt(host, original).unwrap()
  let expected = local_policy_upgrade_receipt(host, strict).unwrap()
  assert_eq(
    (
      observed.operation_id,
      observed.adoption_cid,
      observed.authority_scope_cid,
      observed.original_cid,
      observed.profile_cid,
    ),
    (
      expected.operation_id,
      expected.adoption_cid,
      expected.authority_scope_cid,
      expected.original_cid,
      expected.profile_cid,
    ),
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
test "runtime dependency seam rejects revision and broken HMAC before dependency resolution" {
  let (host, row) = runtime_upgrade_dependency_fixture("dependency-auth")
  let calls = Ref(0)
  let dependency : (String, Bytes) -> Result[
    @host.ClientNativeLocalScalarRuntimePair,
    NativeClientRunJournalIssue,
  ] = (_, _) => {
    calls.val += 1
    Err(CustodyLost)
  }
  assert_true(
    read_local_policy_upgrade_original_with_runtime_dependency(
      host,
      { body: row.body, revision: 1L, },
      dependency,
    )
    is Err(CustodyLost),
  )
  let fields = @host.client_local_original_record_fields(row.body, [
    "payload_head", "payload_tail", "tag",
  ]).unwrap()
  let forged = @host.client_local_original_record_body([
    ("payload_head", fields[0]),
    ("payload_tail", fields[1]),
    ("tag", "0".repeat(64)),
  ]).unwrap()
  assert_true(
    read_local_policy_upgrade_original_with_runtime_dependency(
      host,
      { body: forged, revision: 0L, },
      dependency,
    )
    is Err(CustodyLost),
  )
  assert_eq(calls.val, 0)
  host.close().unwrap()
}

///|
test "runtime dependency seam never resolves malformed authenticated originals" {
  let (host, row) = runtime_upgrade_dependency_fixture("dependency-closed")
  let body = local_policy_upgrade_payload(host, row.body).unwrap()
  let changed = @utf8.decode(body).replace(old="{", new="{\"unknown\":\"x\",")
  let packet = local_policy_upgrade_packet(host, @utf8.encode(changed)).unwrap()
  let calls = Ref(0)
  assert_true(
    read_local_policy_upgrade_original_with_runtime_dependency(
      host,
      { body: packet, revision: 0L, },
      (_, _) => {
        calls.val += 1
        Err(CustodyLost)
      },
    )
    is Err(CustodyLost),
  )
  assert_eq(calls.val, 0)
  host.close().unwrap()
}

///|
test "runtime dependency seam borrows only authenticated body and actual original scope" {
  let (host, row) = runtime_upgrade_dependency_fixture("dependency-runtime")
  let prior = local_policy_upgrade_payload(host, row.body).unwrap()
  // Deliberately unresolved metadata: no opaque pair/compatibility or new
  // accepted original is manufactured from this value. The typed failure must
  // stop at this branch; the normal reader still requires its current pair.
  let changed = @utf8.decode(prior)
    .replace(
      old="\"store_configuration_cid\":",
      new="\"runtime_pair_wire\":\"{}\",\"store_configuration_cid\":",
    )
    .replace(
      old="actql-local-run-policy-upgrade/0.1",
      new="actql-local-runtime-policy-upgrade/0.1",
    )
  let body = @utf8.encode(changed)
  let packet = local_policy_upgrade_packet(host, body).unwrap()
  let scope = host
    .authority_scope_cid("local-cli", "local", epoch_test_crypto())
    .unwrap()
  let calls = Ref(0)
  let exact = Ref(false)
  assert_true(
    read_local_policy_upgrade_original_with_runtime_dependency(
      host,
      { body: packet, revision: 0L, },
      (actual_scope, authenticated) => {
        calls.val += 1
        exact.val = actual_scope == scope && authenticated == body
        Err(UnsupportedPreparation)
      },
    )
    is Err(UnsupportedPreparation),
  )
  assert_eq(calls.val, 1)
  assert_true(exact.val)
  assert_true(
    read_local_policy_upgrade_original(host, { body: packet, revision: 0L, })
    is Err(CustodyLost),
  )
  // The original authenticated row, issued count and reservation are untouched.
  assert_eq(
    host.database
    .read("client_local_installation_originals", local_policy_upgrade_key)
    .unwrap().body,
    row.body,
  )
  assert_eq(
    host.database.read("client_local_installation_custody", "issued").unwrap().body,
    b"1",
  )
  assert_eq(
    host.database.capacity_usage("client_local_settings").unwrap().reserved_bytes,
    8192L,
  )
  host.close().unwrap()
}
