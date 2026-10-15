///|
// Independent canonical Account preimage: exact selectors, sorted entry IDs.
let python_worker_account_expected : String =
  #|{"account_id":"local-cli","entries":[{"connection":{"any_of":["local"]},"entry_id":"local-result-read","exclusions":[],"operation":{"any_of":["read"]},"outcome":"allow","principal":{"any_of":["local-cli"]},"resource":{"any_of":["result/answer"]}},{"connection":{"any_of":["local"]},"entry_id":"local-run-control","exclusions":[],"operation":{"any_of":["cancel","publish","read","submit"]},"outcome":"allow","principal":{"any_of":["local-cli"]},"resource":{"any_of":["run"]}},{"connection":{"any_of":["local"]},"entry_id":"local-worker-provisioning","exclusions":[],"operation":{"any_of":["provision","read"]},"outcome":"allow","principal":{"any_of":["local-cli"]},"resource":{"any_of":["worker"]}}],"version":"actql-execution-account-config/0.1"}

///|
test "Python worker profile has an independent canonical Account and preserves SDK originals" {
  let root = "/private/python-local"
  let at = "2026-10-15T00:00:00.000Z"
  assert_eq(
    client_local_product_sdk_bootstrap_originals(root, at).map(_ => ()),
    Ok(()),
  )
  let old = client_local_product_sdk_bootstrap_originals(root, at).unwrap()
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
      @utf8.decode(old.original.common.account),
    ),
    Ok(
      "sha256:fd6d54cc5bcc0a7af2a7919981b4e06604a3380897bcf9ceb51cf764ecdfb396",
    ),
  )
  assert_eq(
    fresh.original.common.retention_dependencies,
    old.original.common.retention_dependencies,
  )
  assert_eq(
    fresh.original.common.retention_policy,
    old.original.common.retention_policy,
  )
  assert_eq(fresh.original.common.store, old.original.common.store)
  assert_eq(
    fresh.original.common.result_policy,
    old.original.common.result_policy,
  )
  assert_eq(fresh.original.environment, old.original.environment)
  assert_eq(fresh.original.compute, old.original.compute)
  assert_eq(
    client_local_run_policy_profile_wire(fresh.profile),
    client_local_run_policy_profile_wire(old.profile),
  )
  assert_eq(
    @publication.local_sdk_result_read_selection_wire(fresh.read),
    @publication.local_sdk_result_read_selection_wire(old.read),
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
