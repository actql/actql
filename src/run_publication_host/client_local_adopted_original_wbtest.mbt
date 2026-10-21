///|
test "Host binding consumes the Account's exact admitted original" {
  let store = Ref(0)
  let account = @authorization.admit_account_configuration_json(
    @utf8.decode(adopted_current_test_account_original),
  ).unwrap()
  assert_true(
    account.retains_original_bytes(adopted_current_test_account_original),
  )
  let material = bind_client_local_adopted_host_material(store, () => {
    adopted_current_test_ok(adopted_current_test_observation(store, account~))
  }).unwrap()
  assert_true(physical_equal(material.account, account))
  assert_true(
    client_local_adopted_account_outcome(material, store, {
      principal: "operator",
      connection: "local-files",
      resource: "run",
      operation: "read",
    })
    is Ok(@authorization.Allow(_)),
  )
}

///|
test "Host binding preserves validation without a matching wire original" {
  let store = Ref(0)
  // A semantically equal spelling still takes the existing validation path;
  // this optimization does not make wire whitespace a new language refusal.
  let account = @authorization.admit_account_configuration_json(
    @utf8.decode(adopted_current_test_account_original) + "\n",
  ).unwrap()
  assert_true(
    !account.retains_original_bytes(adopted_current_test_account_original),
  )
  assert_true(
    bind_client_local_adopted_host_material(store, () => {
      adopted_current_test_ok(adopted_current_test_observation(store, account~))
    })
    is Ok(_),
  )
  for
    original in [
      b"{}", b"\xff", b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"foreign\",\"entries\":[]}",
    ] {
    assert_true(
      bind_client_local_adopted_host_material(store, () => {
        adopted_current_test_ok(
          adopted_current_test_observation(
            store,
            account~,
            account_original=original,
          ),
        )
      })
      is Err(InvalidOriginal),
    )
  }
}
