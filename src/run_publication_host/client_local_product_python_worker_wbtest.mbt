///|
// Independent canonical Account preimage: exact selectors, sorted entry IDs.
let python_worker_account_expected : String =
  #|{"account_id":"local-cli","entries":[{"connection":{"any_of":["local"]},"entry_id":"local-result-read","exclusions":[],"operation":{"any_of":["read"]},"outcome":"allow","principal":{"any_of":["local-cli"]},"resource":{"any_of":["result/answer"]}},{"connection":{"any_of":["local"]},"entry_id":"local-run-control","exclusions":[],"operation":{"any_of":["cancel","publish","read","submit"]},"outcome":"allow","principal":{"any_of":["local-cli"]},"resource":{"any_of":["run"]}},{"connection":{"any_of":["local"]},"entry_id":"local-worker-provisioning","exclusions":[],"operation":{"any_of":["provision","read"]},"outcome":"allow","principal":{"any_of":["local-cli"]},"resource":{"any_of":["worker"]}}],"version":"actql-execution-account-config/0.1"}

///|
test "Python worker profile preserves its canonical Account and retained fixed read" {
  let root = "/private/python-local"
  let at = "2026-10-15T00:00:00.000Z"
  let old = client_local_product_bootstrap_originals(root, at).unwrap()
  let fresh = client_local_product_python_worker_bootstrap_originals(root, at).unwrap()
  let wire = @utf8.decode(fresh.original.common.account)
  assert_eq(wire, python_worker_account_expected)
  assert_eq(
    @authorization.account_configuration_cid_json(wire),
    Ok(
      "sha256:3cc3f50ac60482bd2362dd7ce4325ffe268f41a379153b1cba05ec97b2e2cc8c",
    ),
  )
  assert_eq(
    @authorization.account_configuration_cid_json(
      @utf8.decode(old.common.account),
    ),
    Ok(
      "sha256:fd6d54cc5bcc0a7af2a7919981b4e06604a3380897bcf9ceb51cf764ecdfb396",
    ),
  )
  assert_eq(
    fresh.original.common.retention_dependencies,
    old.common.retention_dependencies,
  )
  assert_eq(fresh.original.common.retention_policy, old.common.retention_policy)
  assert_eq(fresh.original.common.store, old.common.store)
  assert_eq(fresh.original.common.result_policy, old.common.result_policy)
  assert_eq(fresh.original.environment, old.environment)
  assert_eq(fresh.original.compute, old.compute)
  assert_eq(
    client_local_run_policy_profile_wire(fresh.profile),
    run_profile_fixture,
  )
  // This is the canonical fixed SDK read from before named-result adoption.
  let retained_read =
    #|{"connection":"local","data_policy_cids":["sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"],"formats":["jsonl"],"max_bytes":65536,"max_uses":1,"principal":"local-cli","purpose":"python-local-read","result_names":["answer"],"run_policy_profile_cid":"sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243","sink":"sdk-rows","version":"actql-local-sdk-result-read-selection/0.1"}
  assert_eq(
    @publication.local_sdk_result_read_selection_wire(fresh.read),
    retained_read,
  )
  let restored = @publication.admit_local_sdk_result_read_selection(
    retained_read, "sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243",
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
  ).unwrap()
  assert_eq(
    @publication.local_sdk_result_read_selection_cid(restored),
    "sha256:13906dcd43b46a467520bf3ea87a8889fd9d04701106b814e85142703e751f27",
  )
  assert_true(
    @publication.local_sdk_result_read_selection_accepts_name(
      restored, "answer",
    ),
  )
  assert_false(
    @publication.local_sdk_result_read_selection_accepts_name(
      restored, "before_change",
    ),
  )
  let account = @authorization.admit_account_configuration_json(wire).unwrap()
  let named : @authorization.AccessTuple = {
    principal: "local-cli",
    connection: "local",
    resource: "result/answer",
    operation: "read",
  }
  let installed = @publication.local_sdk_result_read_selection_uses_installed_result_authority(
    restored,
  )
  assert_false(installed)
  assert_eq(
    @authorization.local_result_read_authority_resource(
      account, named, installed,
    ),
    Some("result/answer"),
  )
  assert_eq(
    @authorization.local_result_read_authority_resource(
      account,
      { ..named, resource: "result/before_change", },
      installed,
    ),
    None,
  )
}

///|
test "Python worker Account permits only the exact existing local worker operations" {
  let fresh = client_local_product_python_worker_bootstrap_originals(
    "/private/python-local", "2026-10-15T00:00:00.000Z",
  ).unwrap()
  let account = @authorization.admit_account_configuration_json(
    @utf8.decode(fresh.original.common.account),
  ).unwrap()
  assert_eq(account.bootstrap_profile(), None)
  for operation in ["provision", "read"] {
    assert_true(
      @authorization.evaluate_account(account, {
        principal: "local-cli",
        connection: "local",
        resource: "worker",
        operation,
      })
      is @authorization.Allow("local-worker-provisioning"),
    )
  }
  for
    (principal, connection, resource, operation) in [
      ("operator", "local", "worker", "provision"),
      ("local-cli", "remote", "worker", "read"),
      ("local-cli", "local", "worker/other", "provision"),
      ("local-cli", "local", "worker", "launch"),
      ("local-cli", "local", "worker", "settle"),
      ("local-cli", "local", "source/table", "read"),
      ("local-cli", "local", "model", "invoke"),
      ("local-cli", "local", "effect", "write"),
    ] {
    assert_true(
      @authorization.evaluate_account(account, {
        principal,
        connection,
        resource,
        operation,
      })
      is @authorization.Deny(_),
    )
  }
  let old = client_local_product_sdk_bootstrap_originals(
    "/private/python-local", "2026-10-15T00:00:00.000Z",
  ).unwrap()
  let old_account = @authorization.admit_account_configuration_json(
    @utf8.decode(old.original.common.account),
  ).unwrap()
  for operation in ["provision", "read"] {
    assert_true(
      @authorization.evaluate_account(old_account, {
        principal: "local-cli",
        connection: "local",
        resource: "worker",
        operation,
      })
      is @authorization.Deny(_),
    )
  }
}

///|
test "Python worker metadata keeps existing path and clock refusal" {
  assert_true(
    client_local_product_python_worker_bootstrap_originals(
      "relative", "2026-10-15T00:00:00.000Z",
    )
    is Err(InvalidLocation),
  )
  assert_true(
    client_local_product_python_worker_bootstrap_originals(
      "/private/python-local", "invalid",
    )
    is Err(InvalidObservationTime),
  )
}
