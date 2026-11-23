///|
test "explicit SDK bootstrap adds bounded read originals with the exact installed Account role" {
  let root = "/private/local"
  let at = "2026-10-12T00:00:00.000Z"
  let old = client_local_product_bootstrap_originals(root, at).unwrap()
  let fresh = client_local_product_sdk_bootstrap_originals(root, at).unwrap()
  let wire = @utf8.decode(fresh.original.common.account)
  let expected =
    #|{"account_id":"local-cli","entries":[{"connection":{"any_of":["local"]},"entry_id":"local-result-original-read","exclusions":[],"operation":{"any_of":["read"]},"outcome":"allow","principal":{"any_of":["local-cli"]},"resource":{"any_of":["result"]}},{"connection":{"any_of":["local"]},"entry_id":"local-run-control","exclusions":[],"operation":{"any_of":["cancel","publish","read","submit"]},"outcome":"allow","principal":{"any_of":["local-cli"]},"resource":{"any_of":["run"]}}],"version":"actql-execution-account-config/0.1"}
  assert_eq(wire, expected)
  assert_eq(
    @authorization.account_configuration_cid_json(wire),
    Ok(
      "sha256:aaa4d96c987f84530038f7a3e41fec16e094a8df585a5ec604d69bab646fb78e",
    ),
  )
  let installed = @authorization.admit_account_configuration_json(wire).unwrap()
  let legacy = @authorization.admit_account_configuration_json(
    @utf8.decode(old.common.account),
  ).unwrap()
  let named : @authorization.AccessTuple = {
    principal: "local-cli",
    connection: "local",
    resource: "result/before_change",
    operation: "read",
  }
  assert_eq(
    @authorization.local_result_read_authority_resource(installed, named, true),
    Some("result"),
  )
  assert_eq(
    @authorization.local_result_read_authority_resource(legacy, named, true),
    None,
  )
  assert_eq(
    @authorization.local_result_read_authority_resource(installed, named, false),
    None,
  )
  assert_eq(
    @authorization.local_result_read_authority_resource(
      legacy,
      { ..named, resource: "result/answer", },
      false,
    ),
    Some("result/answer"),
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
    client_local_run_policy_profile_cid(fresh.profile),
    "sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243",
  )
  assert_eq(
    @publication.local_sdk_result_read_selection_cid(fresh.read),
    "sha256:8e336e72421b0dcf0a561bdad1b880cf5f209176a6c3ab121a96858333025291",
  )
  assert_true(
    @utf8.encode(client_local_run_policy_profile_wire(fresh.profile)).length() <=
    8192,
  )
  assert_true(
    @utf8.encode(@publication.local_sdk_result_read_selection_wire(fresh.read)).length() <=
    8192,
  )
}

///|
test "explicit SDK metadata does not contain an adoption-time read expiry" {
  let first = client_local_product_sdk_bootstrap_originals(
    "/private/local", "2026-10-12T00:00:00.000Z",
  ).unwrap()
  let later = client_local_product_sdk_bootstrap_originals(
    "/private/local", "2026-10-13T00:00:00.001Z",
  ).unwrap()
  assert_eq(
    client_local_run_policy_profile_wire(first.profile),
    client_local_run_policy_profile_wire(later.profile),
  )
  assert_eq(
    @publication.local_sdk_result_read_selection_wire(first.read),
    @publication.local_sdk_result_read_selection_wire(later.read),
  )
  assert_false(
    @publication.local_sdk_result_read_selection_wire(first.read).contains(
      "expires_at",
    ),
  )
}
