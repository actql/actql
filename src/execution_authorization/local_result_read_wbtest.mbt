///|
test "original Result read requires the exact installed role and preserves named refusals" {
  let named : AccessTuple = {
    principal: "local-cli",
    connection: "local",
    resource: "result/before_change",
    operation: "read",
  }
  let role : RawAccountEntry = {
    entry_id: local_original_result_read_entry_id,
    outcome: Allow,
    scope: {
      principal: AnyOf(["local-cli"]),
      connection: AnyOf(["local"]),
      resource: AnyOf(["result"]),
      operation: AnyOf(["read"]),
    },
    exclusions: [],
  }
  let admitted = entries => {
    admit_account_configuration({
      account_id: "local-cli",
      entries,
      bootstrap: None,
    }).unwrap()
  }
  let installed = admitted([role])
  assert_eq(
    local_result_read_authority_resource(installed, named, true),
    Some("result"),
  )
  assert_eq(local_result_read_authority_resource(installed, named, false), None)
  assert_eq(
    local_result_read_authority_resource(
      admitted([{ ..role, scope: { ..role.scope, resource: All, }, }]),
      named,
      true,
    ),
    None,
  )
  let explicit = {
    ..role,
    entry_id: "named",
    scope: { ..role.scope, resource: AnyOf([named.resource]), },
  }
  assert_eq(
    local_result_read_authority_resource(admitted([explicit]), named, false),
    Some(named.resource),
  )
  for outcome in [ConfiguredOutcome::Deny, ConfiguredOutcome::Delegate] {
    assert_eq(
      local_result_read_authority_resource(
        admitted([role, { ..explicit, outcome, }]),
        named,
        true,
      ),
      None,
    )
  }
}

///|
test "installed File Result read uses its exact disjoint control connection" {
  let (control, wire) = local_standard_file_account_configuration_prepared(
    [("local", "small"), ("actql-local-control-0", "other")],
    _ => true,
  ).unwrap().unwrap()
  assert_eq(control, "actql-local-control-1")
  let account = admit_account_configuration_json(wire).unwrap()
  let tuple : AccessTuple = {
    principal: "local-cli",
    connection: control,
    resource: "result/main",
    operation: "read",
  }
  assert_eq(local_result_read_authority_resource(account, tuple, true), Some("result"))
  assert_eq(local_result_read_authority_resource(account, tuple, false), None)
  for connection in ["local", "actql-local-control-0", "actql-local-control-2"] {
    assert_eq(
      local_result_read_authority_resource(account, { ..tuple, connection, }, true),
      None,
    )
  }
  assert_eq(
    local_result_read_authority_resource({ ..account, bootstrap: None, }, tuple, true),
    None,
  )
}
