///|
fn runtime_policy_upgrade_test_pair() -> ClientNativeLocalScalarRuntimePair {
  scalar_pair_test_inspect(
    scalar_pair_test_admit(scalar_pair_test_current_runtime_wire()),
  ).unwrap()
}

///|
fn runtime_policy_upgrade_test_admit(
  body : Bytes,
  runtime : ClientNativeLocalScalarRuntimePair,
) -> Result[ClientLocalRuntimePolicyUpgrade, ClientLocalRunPolicyProfileIssue] {
  admit_client_local_runtime_policy_upgrade(
    body,
    client_local_run_policy_profile(product_common_test_originals()).unwrap(),
    policy_upgrade_old_read,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "explicit-upgrade-1",
    policy_upgrade_files(),
    runtime,
  )
}

///|
test "runtime upgrade alternative retains the entire original policy and pair without changing old bytes" {
  let prior = policy_upgrade_restore(policy_upgrade_fixture).unwrap()
  let pair = runtime_policy_upgrade_test_pair()
  let original = bind_client_local_runtime_policy_upgrade(prior, pair).unwrap()
  let body = client_local_runtime_policy_upgrade_body(original)
  // Independent Python composition of the original policy/pair input vectors.
  assert_eq(body.length(), 2978)
  assert_eq(
    @sha.hex(body),
    "49d9e9c8f6cce49d488734013b9727c2c934c01692f4ba79a79522231e825526",
  )
  assert_eq(
    client_local_run_policy_upgrade_body(
      client_local_runtime_policy_upgrade_policy(original),
    ),
    @utf8.encode(policy_upgrade_fixture),
  )
  assert_eq(
    @sha.hex(prior.body),
    "50ea4cfc8971b947f7e988bf525f637606bc19a92b88078c8e368374085df4e1",
  )
  assert_eq(
    client_native_local_scalar_runtime_pair_body(
      client_local_runtime_policy_upgrade_runtime(original),
    ),
    pair.body,
  )
  let saved = runtime_policy_upgrade_test_admit(body, pair).unwrap()
  assert_eq(client_local_runtime_policy_upgrade_body(saved), body)
  assert_eq(
    client_local_run_policy_upgrade_legacy_runs(saved.policy),
    policy_upgrade_legacy(),
  )
  assert_eq(
    client_local_run_policy_upgrade_read_wire(saved.policy),
    policy_upgrade_read,
  )
}

///|
test "old and runtime upgrade alternatives refuse each other rather than backfilling missing correspondence" {
  let prior = policy_upgrade_restore(policy_upgrade_fixture).unwrap()
  let pair = runtime_policy_upgrade_test_pair()
  let upgraded = bind_client_local_runtime_policy_upgrade(prior, pair).unwrap()
  assert_eq(
    runtime_policy_upgrade_test_admit(prior.body, pair).map(_ => 0),
    Err(InvalidOriginal),
  )
  assert_eq(
    policy_upgrade_restore(@utf8.decode(upgraded.body)).map(_ => 0),
    Err(InvalidOriginal),
  )
  let wire = @utf8.decode(upgraded.body)
  for
    (before, after) in [
      (
        "actql-local-runtime-policy-upgrade/0.1", "actql-local-run-policy-upgrade/0.1",
      ),
      ("primitive-scalar-values", "all-values"),
      ("8bdf4835", "00000000"),
      ("explicit-upgrade-1", "foreign-operation"),
      ("work.json", "foreign.json"),
      ("86400000", "86400001"),
    ] {
    assert_eq(
      runtime_policy_upgrade_test_admit(
        @utf8.encode(wire.replace(old=before, new=after)),
        pair,
      ).map(_ => 0),
      Err(InvalidOriginal),
    )
  }
  assert_eq(
    runtime_policy_upgrade_test_admit(@utf8.encode(wire + " "), pair).map(_ => 0),
    Err(InvalidOriginal),
  )
}

///|
test "runtime upgrade restoration binds exact current manifest independently of policy identity" {
  let prior = policy_upgrade_restore(policy_upgrade_fixture).unwrap()
  let pair = runtime_policy_upgrade_test_pair()
  let upgraded = bind_client_local_runtime_policy_upgrade(prior, pair).unwrap()
  let foreign = scalar_pair_test_inspect(
    scalar_pair_test_admit(
      scalar_pair_test_current_runtime_wire().replace(
        old="b".repeat(40),
        new="c".repeat(40),
      ),
    ),
  ).unwrap()
  assert_eq(
    runtime_policy_upgrade_test_admit(upgraded.body, foreign).map(_ => 0),
    Err(InvalidOriginal),
  )
  assert_eq(prior.body, @utf8.encode(policy_upgrade_fixture))
}
